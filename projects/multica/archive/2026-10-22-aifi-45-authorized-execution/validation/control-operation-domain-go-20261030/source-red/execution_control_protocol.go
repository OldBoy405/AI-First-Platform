// Package governance: control channel wire protocol (trust manifest + envelope signing).
//
// The signatures and digests here must be byte-identical to
// tools/skills/shared/crctl/scripts/lib/execution-control-protocol.mjs, because the same
// envelope is minted on one side and verified on the other. Any re-encoding on either side
// changes the signed bytes, so both sides sign and verify raw payload bytes.
package governance

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

// 域名字符串由 plan §2 L88（业务域）与 L90（D7）固定，并被绑进签名前像：
// 改名会让链上每一帧的 digest 全部失效，所以这里是常量而不是可配置项。
const (
	ControlCommandDomain   = "execution-control-command/v1"
	VerdictDomain          = "execution-verdict/v1"
	CheckpointDomain       = "execution-control-checkpoint/v1"
	ResumeDomain           = "execution-repair-resume/v1"
	ReadinessRequestDomain = "execution-policy-readiness-request/v1"
	ReadinessVerdictDomain = "execution-policy-readiness/v1"
	// DeploymentObservationDomain 是 D7 部署观测的独立域：只有登记的 observer 能签。
	DeploymentObservationDomain = "execution-deployment-observation/v1"

	TrustManifestSchema = "execution-control-trust-manifest/v1"

	maxManifestBytes = 1024 * 1024
	maxKeyBytes      = 64 * 1024
	maxPayloadBytes  = 2 * 1024 * 1024
)

var (
	ErrControlInputInvalid      = errors.New("EXECUTION_CONTROL_INPUT_INVALID")
	ErrControlSignatureInvalid  = errors.New("EXECUTION_CONTROL_SIGNATURE_INVALID")
	ErrControlKeyInvalid        = errors.New("EXECUTION_CONTROL_KEY_INVALID")
	ErrControlKeyPurposeInvalid = errors.New("EXECUTION_CONTROL_KEY_PURPOSE_INVALID")
	ErrControlBindingMismatch   = errors.New("EXECUTION_CONTROL_BINDING_MISMATCH")
	ErrControlManifestInvalid   = errors.New("EXECUTION_CONTROL_TRUST_MANIFEST_INVALID")
)

var (
	controlCharRE  = regexp.MustCompile(`[\x00-\x1f\x7f-\x9f]`)
	controlKeyRE   = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$`)
	controlHexRE   = regexp.MustCompile(`^[0-9a-f]{64}$`)
	controlStampRE = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$`)
)

type controlOperation struct {
	schema  string
	domain  string
	purpose string
}

// 三种 purpose 各有其签发者（plan §2 L86-87）：command 默认独立 key，attestation 只签
// verdict/checkpoint/readiness，human 只签 resume。合成两种会让「attestation 签 command」
// 成为合法路径，而 SC-VC-008 明确要求拒绝。
var controlOperations = map[string]controlOperation{
	"command":           {"execution-control-command/v1", ControlCommandDomain, "control-command"},
	"verdict":           {"execution-control-verdict/v1", VerdictDomain, "tool-attestation"},
	"checkpoint":        {"execution-control-checkpoint/v1", CheckpointDomain, "tool-attestation"},
	"readiness-request": {"execution-readiness-request/v1", ReadinessRequestDomain, "tool-attestation"},
	"readiness-verdict": {"execution-readiness-verdict/v1", ReadinessVerdictDomain, "tool-attestation"},
	"resume":            {"execution-resume/v1", ResumeDomain, "human"},
	// D7：部署观测用独立 purpose 的登记密钥，不能由 agent enrollment 取得。
	"deployment-observer": {"execution-deployment-observation/v1", DeploymentObservationDomain, "deployment-observer"},
}

var controlKeyPurposes = map[string]bool{"control-command": true, "tool-attestation": true, "human": true, "deployment-observer": true}

var controlScopeDimensions = map[string]bool{
	"workspace_id": true, "project_id": true, "cr_id": true,
	"daemon_id": true, "store_id": true, "lineage_id": true, "deployment_id": true,
}

// ControlScope 精确限制 key 的适用范围；plan §2 L85 要求「签发、验签两端均检查」，
// 因此它是 key 的字段，而不是调用方可选的口径。
type ControlScope map[string]string

type ControlError struct {
	Code error
	Msg  string
}

func (e *ControlError) Error() string { return e.Code.Error() + ": " + e.Msg }
func (e *ControlError) Unwrap() error { return e.Code }

func controlReject(code error, format string, args ...any) error {
	return &ControlError{Code: code, Msg: fmt.Sprintf(format, args...)}
}

type ControlKey struct {
	KeyID      string
	Purpose    string
	Domains    []string
	Scope      ControlScope
	ValidFrom  time.Time
	ValidUntil time.Time
	PublicKey  ed25519.PublicKey
	Path       string
	SHA256     string
}

type ControlDeployment struct {
	DeploymentID    string
	Scope           string
	Generation      int64
	RequiredProfile string
	TrustRevision   int64
}

type ControlTrustManifest struct {
	ManifestID  string
	Keys        map[string]ControlKey
	Deployments map[string]ControlDeployment
	Path        string
	SHA256      string
}

// validateStrictValue walks the whole JSON value and refuses duplicate object keys at every
// depth. Go's encoding/json silently keeps the last duplicate, which is exactly how two
// verifiers end up disagreeing about which key or payload was signed.
func validateStrictValue(decoder *json.Decoder) error {
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	delim, isDelim := token.(json.Delim)
	if !isDelim {
		return nil
	}
	switch delim {
	case '{':
		seen := map[string]bool{}
		for decoder.More() {
			keyToken, err := decoder.Token()
			if err != nil {
				return err
			}
			key, ok := keyToken.(string)
			if !ok {
				return errors.New("object key is not a string")
			}
			if seen[key] {
				return fmt.Errorf("duplicate key %q", key)
			}
			seen[key] = true
			if err := validateStrictValue(decoder); err != nil {
				return err
			}
		}
		closing, err := decoder.Token()
		if err != nil {
			return err
		}
		if closing != json.Delim('}') {
			return errors.New("object not terminated")
		}
	case '[':
		for decoder.More() {
			if err := validateStrictValue(decoder); err != nil {
				return err
			}
		}
		closing, err := decoder.Token()
		if err != nil {
			return err
		}
		if closing != json.Delim(']') {
			return errors.New("array not terminated")
		}
	default:
		return fmt.Errorf("unexpected delimiter %v", delim)
	}
	return nil
}

func decodeStrictObject(raw []byte) (map[string]json.RawMessage, error) {
	validator := json.NewDecoder(bytes.NewReader(raw))
	validator.UseNumber()
	if err := validateStrictValue(validator); err != nil {
		return nil, err
	}
	if _, err := validator.Token(); err != io.EOF {
		return nil, errors.New("trailing data after value")
	}

	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	token, err := decoder.Token()
	if err != nil {
		return nil, err
	}
	if delim, ok := token.(json.Delim); !ok || delim != '{' {
		return nil, errors.New("not a JSON object")
	}
	fields := map[string]json.RawMessage{}
	for decoder.More() {
		keyToken, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		key, ok := keyToken.(string)
		if !ok {
			return nil, errors.New("object key is not a string")
		}
		if _, duplicated := fields[key]; duplicated {
			return nil, fmt.Errorf("duplicate key %q", key)
		}
		var value json.RawMessage
		if err := decoder.Decode(&value); err != nil {
			return nil, err
		}
		fields[key] = value
	}
	if _, err := decoder.Token(); err != nil {
		return nil, err
	}
	if decoder.More() {
		return nil, errors.New("trailing data after object")
	}
	return fields, nil
}

func exactControlKeys(fields map[string]json.RawMessage, keys ...string) bool {
	if len(fields) != len(keys) {
		return false
	}
	for _, key := range keys {
		if _, ok := fields[key]; !ok {
			return false
		}
	}
	return true
}

// rawInt reads a JSON number as an int64. A float or a string is a type error, not a
// rounding: 1.0 must not silently become 1 when the value is a signed chain position.
func rawInt(fields map[string]json.RawMessage, key string) (int64, bool) {
	raw, ok := fields[key]
	if !ok {
		return 0, false
	}
	var value json.Number
	if err := json.Unmarshal(raw, &value); err != nil {
		return 0, false
	}
	parsed, err := value.Int64()
	if err != nil {
		return 0, false
	}
	return parsed, true
}

func rawString(fields map[string]json.RawMessage, key string) (string, bool) {
	raw, ok := fields[key]
	if !ok {
		return "", false
	}
	var value string
	if err := json.Unmarshal(raw, &value); err != nil {
		return "", false
	}
	return value, true
}

func hasControlChars(text string) bool {
	stripped := strings.NewReplacer("\n", "", "\r", "", "\t", "").Replace(text)
	return controlCharRE.MatchString(stripped)
}

// decodeStrictBase64 requires canonical standard base64: a payload that decodes two ways
// would let two callers disagree about the signed bytes.
func decodeStrictBase64(text string, limit int) ([]byte, error) {
	if text == "" || len(text)%4 != 0 {
		return nil, errors.New("base64 field missing or has illegal length")
	}
	bytes, err := base64.StdEncoding.DecodeString(text)
	if err != nil {
		return nil, err
	}
	if base64.StdEncoding.EncodeToString(bytes) != text {
		return nil, errors.New("base64 field is not canonical")
	}
	if limit > 0 && len(bytes) > limit {
		return nil, errors.New("base64 field exceeds size limit")
	}
	return bytes, nil
}

func parseControlJSON(bytes []byte, message string) (map[string]json.RawMessage, error) {
	if !utf8.Valid(bytes) {
		return nil, fmt.Errorf("%s: not valid UTF-8", message)
	}
	if hasControlChars(string(bytes)) {
		return nil, fmt.Errorf("%s: contains control characters", message)
	}
	fields, err := decodeStrictObject(bytes)
	if err != nil {
		return nil, fmt.Errorf("%s: not a single valid JSON object (%v)", message, err)
	}
	return fields, nil
}

func parseControlScope(fields map[string]json.RawMessage, key string, code error, label string) (ControlScope, error) {
	raw, ok := fields[key]
	if !ok {
		return nil, controlReject(code, "%s 缺失", label)
	}
	object, err := decodeStrictObject(raw)
	if err != nil {
		return nil, controlReject(code, "%s 必须是对象", label)
	}
	if len(object) == 0 {
		return nil, controlReject(code, "%s 不能为空", label)
	}
	scope := ControlScope{}
	for dimension, valueRaw := range object {
		if !controlScopeDimensions[dimension] {
			return nil, controlReject(code, "%s 含未知维度 %s", label, dimension)
		}
		var value string
		if err := json.Unmarshal(valueRaw, &value); err != nil || value == "" || hasControlChars(value) {
			return nil, controlReject(code, "%s.%s 不合法", label, dimension)
		}
		scope[dimension] = value
	}
	return scope, nil
}

func scopeDimensions(scope ControlScope) []string {
	dimensions := make([]string, 0, len(scope))
	for dimension := range scope {
		dimensions = append(dimensions, dimension)
	}
	sort.Strings(dimensions)
	return dimensions
}

// controlScopesEqual 用精确匹配：维度集合与取值都必须相等，不做通配，避免
// 「声明了 workspace 就隐含全部 project」。
func controlScopesEqual(declared, requested ControlScope) bool {
	if len(declared) != len(requested) || len(declared) == 0 {
		return false
	}
	for dimension, value := range declared {
		if requested[dimension] != value {
			return false
		}
	}
	return true
}

func parseControlStamp(value string, code error, label string) (time.Time, error) {
	if !controlStampRE.MatchString(value) {
		return time.Time{}, controlReject(code, "%s 必须形如 2026-01-01T00:00:00Z", label)
	}
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return time.Time{}, controlReject(code, "%s 必须形如 2026-01-01T00:00:00Z", label)
	}
	return parsed, nil
}

// assertKeyPolicy 是 plan §2 L85 的落地：域、scope、有效期三件事签发端与验签端都要核。
func assertKeyPolicy(key ControlKey, domain string, scope ControlScope, now time.Time) error {
	allowed := false
	for _, declared := range key.Domains {
		if declared == domain {
			allowed = true
			break
		}
	}
	if !allowed {
		return controlReject(ErrControlKeyInvalid, "key %s 未被授权签发 domain %s", key.KeyID, domain)
	}
	if !controlScopesEqual(key.Scope, scope) {
		return controlReject(ErrControlKeyInvalid, "key %s 的 scope 与请求不匹配", key.KeyID)
	}
	if now.Before(key.ValidFrom) {
		return controlReject(ErrControlKeyInvalid, "key %s 尚未生效", key.KeyID)
	}
	if !now.Before(key.ValidUntil) {
		return controlReject(ErrControlKeyInvalid, "key %s 已过期", key.KeyID)
	}
	return nil
}

// LoadControlTrustManifest loads the operator-pinned manifest. A key file inside an
// agent-writable root is not a trust root: whoever can rewrite the key can rewrite the
// verdict.
func LoadControlTrustManifest(manifestPath string, forbiddenRoots []string) (*ControlTrustManifest, error) {
	if !filepath.IsAbs(manifestPath) {
		return nil, controlReject(ErrControlManifestInvalid, "trust manifest 必须使用绝对路径")
	}
	stat, err := os.Stat(manifestPath)
	if err != nil || !stat.Mode().IsRegular() || stat.Size() > maxManifestBytes {
		return nil, controlReject(ErrControlManifestInvalid, "trust manifest 不是普通文件或超过大小上限")
	}
	raw, err := os.ReadFile(manifestPath)
	if err != nil {
		return nil, controlReject(ErrControlManifestInvalid, "trust manifest 不可读: %v", err)
	}
	document, err := parseControlJSON(raw, "trust manifest")
	if err != nil {
		return nil, controlReject(ErrControlManifestInvalid, "%v", err)
	}
	manifestID, ok := rawString(document, "manifest_id")
	if !exactControlKeys(document, "schema", "manifest_id", "keys", "deployments") ||
		!ok || manifestID == "" || hasControlChars(manifestID) {
		return nil, controlReject(ErrControlManifestInvalid, "trust manifest 顶层字段/版本不合法")
	}
	if schema, _ := rawString(document, "schema"); schema != TrustManifestSchema {
		return nil, controlReject(ErrControlManifestInvalid, "trust manifest schema 不匹配")
	}
	var keyEntries []json.RawMessage
	if err := json.Unmarshal(document["keys"], &keyEntries); err != nil || len(keyEntries) == 0 {
		return nil, controlReject(ErrControlManifestInvalid, "trust manifest 必须声明至少一个 key")
	}
	var deploymentEntries []json.RawMessage
	if err := json.Unmarshal(document["deployments"], &deploymentEntries); err != nil {
		return nil, controlReject(ErrControlManifestInvalid, "trust manifest deployments 必须是数组")
	}

	forbidden := make([]string, 0, len(forbiddenRoots))
	for _, root := range forbiddenRoots {
		if filepath.IsAbs(root) {
			forbidden = append(forbidden, filepath.Clean(root))
		}
	}

	keys := map[string]ControlKey{}
	for _, entryRaw := range keyEntries {
		entry, err := decodeStrictObject(entryRaw)
		if err != nil {
			return nil, controlReject(ErrControlManifestInvalid, "trust manifest key 条目不是对象")
		}
		// plan §2 L85 的字段表 + 唯一键材料形式：pin 文件（L84）或内联公钥，二者只能取一。
		pinned := exactControlKeys(entry, "key_id", "purpose", "domains", "scope", "valid_from", "valid_until", "path", "sha256")
		inline := exactControlKeys(entry, "key_id", "purpose", "domains", "scope", "valid_from", "valid_until", "public_key")
		keyID, _ := rawString(entry, "key_id")
		purpose, _ := rawString(entry, "purpose")
		if (!pinned && !inline) || !controlKeyRE.MatchString(keyID) || !controlKeyPurposes[purpose] {
			return nil, controlReject(ErrControlManifestInvalid, "trust manifest key 条目字段不合法")
		}
		var declaredDomains []string
		if err := json.Unmarshal(entry["domains"], &declaredDomains); err != nil || len(declaredDomains) == 0 {
			return nil, controlReject(ErrControlManifestInvalid, "key %s 必须声明非空 domains", keyID)
		}
		seenDomains := map[string]bool{}
		for _, declared := range declaredDomains {
			if !knownControlDomain(declared) {
				return nil, controlReject(ErrControlManifestInvalid, "key %s 声明了未知 domain %s", keyID, declared)
			}
			if seenDomains[declared] {
				return nil, controlReject(ErrControlManifestInvalid, "key %s 重复声明 domain %s", keyID, declared)
			}
			seenDomains[declared] = true
		}
		scope, err := parseControlScope(entry, "scope", ErrControlManifestInvalid, "key "+keyID)
		if err != nil {
			return nil, err
		}
		validFromRaw, _ := rawString(entry, "valid_from")
		validUntilRaw, _ := rawString(entry, "valid_until")
		validFrom, err := parseControlStamp(validFromRaw, ErrControlManifestInvalid, "key "+keyID+".valid_from")
		if err != nil {
			return nil, err
		}
		validUntil, err := parseControlStamp(validUntilRaw, ErrControlManifestInvalid, "key "+keyID+".valid_until")
		if err != nil {
			return nil, err
		}
		if !validFrom.Before(validUntil) {
			return nil, controlReject(ErrControlManifestInvalid, "key %s 的有效期区间为空", keyID)
		}
		if _, duplicated := keys[keyID]; duplicated {
			return nil, controlReject(ErrControlManifestInvalid, "trust manifest 重复声明 key %s", keyID)
		}

		var pemBytes []byte
		keyPath, keySHA := "", ""
		if inline {
			publicKeyText, _ := rawString(entry, "public_key")
			if publicKeyText == "" {
				return nil, controlReject(ErrControlKeyInvalid, "key %s 的 public_key 不合法", keyID)
			}
			pemBytes = []byte(publicKeyText)
			sum := sha256.Sum256(pemBytes)
			keySHA = hex.EncodeToString(sum[:])
		} else {
			keyPath, _ = rawString(entry, "path")
			keySHA, _ = rawString(entry, "sha256")
			if !filepath.IsAbs(keyPath) || !controlHexRE.MatchString(keySHA) {
				return nil, controlReject(ErrControlManifestInvalid, "trust manifest key 条目字段不合法")
			}
			resolved := filepath.Clean(keyPath)
			for _, root := range forbidden {
				if resolved == root || strings.HasPrefix(resolved, root+string(filepath.Separator)) {
					return nil, controlReject(ErrControlKeyInvalid, "key %s 位于 agent 可写根内，不能作为信任根", keyID)
				}
			}
			keyStat, statErr := os.Stat(resolved)
			if statErr != nil || !keyStat.Mode().IsRegular() || keyStat.Size() > maxKeyBytes {
				return nil, controlReject(ErrControlKeyInvalid, "key %s 不是普通文件或超过大小上限", keyID)
			}
			read, readErr := os.ReadFile(resolved)
			if readErr != nil {
				return nil, controlReject(ErrControlKeyInvalid, "key %s 不可读", keyID)
			}
			pemBytes = read
			sum := sha256.Sum256(pemBytes)
			if hex.EncodeToString(sum[:]) != keySHA {
				return nil, controlReject(ErrControlKeyInvalid, "key %s 与 pin 的 SHA256 不一致", keyID)
			}
			keyPath = resolved
		}
		block, _ := pem.Decode(pemBytes)
		if block == nil {
			return nil, controlReject(ErrControlKeyInvalid, "key %s 不是合法的 PEM 公钥", keyID)
		}
		parsed, parseErr := x509.ParsePKIXPublicKey(block.Bytes)
		if parseErr != nil {
			return nil, controlReject(ErrControlKeyInvalid, "key %s 不是合法的 PEM 公钥", keyID)
		}
		publicKey, isEd25519 := parsed.(ed25519.PublicKey)
		if !isEd25519 {
			return nil, controlReject(ErrControlKeyInvalid, "key %s 不是 Ed25519 公钥", keyID)
		}
		keys[keyID] = ControlKey{
			KeyID: keyID, Purpose: purpose, Domains: declaredDomains, Scope: scope,
			ValidFrom: validFrom, ValidUntil: validUntil,
			PublicKey: publicKey, Path: keyPath, SHA256: keySHA,
		}
	}

	deployments := map[string]ControlDeployment{}
	for _, entryRaw := range deploymentEntries {
		entry, err := decodeStrictObject(entryRaw)
		if err != nil {
			return nil, controlReject(ErrControlManifestInvalid, "trust manifest deployment 条目不是对象")
		}
		if !exactControlKeys(entry, "deployment_id", "scope", "generation", "required_profile", "trust_revision") {
			return nil, controlReject(ErrControlManifestInvalid, "trust manifest deployment 条目字段不合法")
		}
		deploymentID, _ := rawString(entry, "deployment_id")
		scope, _ := rawString(entry, "scope")
		profile, _ := rawString(entry, "required_profile")
		var generation, revision int64
		if err := json.Unmarshal(entry["generation"], &generation); err != nil {
			return nil, controlReject(ErrControlManifestInvalid, "trust manifest deployment generation 不合法")
		}
		if err := json.Unmarshal(entry["trust_revision"], &revision); err != nil {
			return nil, controlReject(ErrControlManifestInvalid, "trust manifest deployment trust_revision 不合法")
		}
		if deploymentID == "" || scope == "" || generation < 1 ||
			(profile != "channel-component" && profile != "strict-production") || revision < 1 {
			return nil, controlReject(ErrControlManifestInvalid, "trust manifest deployment 条目字段不合法")
		}
		if _, duplicated := deployments[deploymentID]; duplicated {
			return nil, controlReject(ErrControlManifestInvalid, "trust manifest 重复声明 deployment %s", deploymentID)
		}
		deployments[deploymentID] = ControlDeployment{
			DeploymentID: deploymentID, Scope: scope, Generation: generation,
			RequiredProfile: profile, TrustRevision: revision,
		}
	}

	manifestSum := sha256.Sum256(raw)
	return &ControlTrustManifest{
		ManifestID: manifestID, Keys: keys, Deployments: deployments,
		Path: filepath.Clean(manifestPath), SHA256: hex.EncodeToString(manifestSum[:]),
	}, nil
}

func knownControlDomain(domain string) bool {
	for _, operation := range controlOperations {
		if operation.domain == domain {
			return true
		}
	}
	return false
}

type ControlVerification struct {
	Payload      map[string]json.RawMessage
	PayloadBytes []byte
	PayloadScope ControlScope
	KeyID        string
	KeyPurpose   string
	Schema       string
	Digest       string
}

// controlPreimage is plan §2 L88's `domain || 原始 payload bytes`: the domain string carries
// its own trailing NUL, and nothing else is prepended. Binding the domain into the signature
// is what makes "same payload, different domain" impossible rather than merely discouraged.
func controlPreimage(domain string, payloadBytes []byte) []byte {
	prefix := make([]byte, 0, len(domain)+1+len(payloadBytes))
	prefix = append(prefix, domain...)
	prefix = append(prefix, 0)
	return append(prefix, payloadBytes...)
}

// VerifyControlEnvelope checks one envelope. The order of refusals mirrors the Node
// implementation: input shape first, then key identity, then purpose and key policy, then
// payload bytes, then signature, then the binding triple.
//
// `now` 为零值时取当前时间；测试与重放校验必须显式传入，否则同一份字节的结论会随时间漂移。
func VerifyControlEnvelope(raw []byte, expectedPurpose, domain string, scope ControlScope, manifest *ControlTrustManifest, now time.Time) (ControlVerification, error) {
	operation, known := controlOperations[expectedPurpose]
	if !known {
		return ControlVerification{}, controlReject(ErrControlInputInvalid, "未知的操作 purpose：%s", expectedPurpose)
	}
	if domain == "" {
		return ControlVerification{}, controlReject(ErrControlInputInvalid, "domain 缺失")
	}
	if len(scope) == 0 {
		return ControlVerification{}, controlReject(ErrControlInputInvalid, "scope 非法")
	}
	for dimension, value := range scope {
		if !controlScopeDimensions[dimension] || value == "" || hasControlChars(value) {
			return ControlVerification{}, controlReject(ErrControlInputInvalid, "scope 非法")
		}
	}
	if manifest == nil || manifest.Keys == nil {
		return ControlVerification{}, controlReject(ErrControlManifestInvalid, "未加载 trust manifest")
	}
	if now.IsZero() {
		now = time.Now()
	}

	envelope, err := parseControlJSON(raw, "control envelope")
	if err != nil {
		return ControlVerification{}, controlReject(ErrControlInputInvalid, "%v", err)
	}
	if !exactControlKeys(envelope, "key_id", "payload_b64", "signature") {
		return ControlVerification{}, controlReject(ErrControlInputInvalid, "envelope 必须恰好是 key_id/payload_b64/signature")
	}
	keyID, _ := rawString(envelope, "key_id")
	if !controlKeyRE.MatchString(keyID) {
		return ControlVerification{}, controlReject(ErrControlInputInvalid, "envelope key_id 不合法")
	}
	key, present := manifest.Keys[keyID]
	if !present {
		return ControlVerification{}, controlReject(ErrControlKeyInvalid, "key %s 不在 trust manifest 中", keyID)
	}
	if key.Purpose != operation.purpose {
		return ControlVerification{}, controlReject(ErrControlKeyPurposeInvalid,
			"key purpose %s 不能签发 %s（需要 %s）", key.Purpose, expectedPurpose, operation.purpose)
	}
	if err := assertKeyPolicy(key, domain, scope, now); err != nil {
		return ControlVerification{}, err
	}

	payloadB64, _ := rawString(envelope, "payload_b64")
	payloadBytes, err := decodeStrictBase64(payloadB64, maxPayloadBytes)
	if err != nil {
		return ControlVerification{}, controlReject(ErrControlInputInvalid, "payload_b64 非法: %v", err)
	}
	signatureB64, _ := rawString(envelope, "signature")
	signature, err := decodeStrictBase64(signatureB64, 0)
	if err != nil {
		return ControlVerification{}, controlReject(ErrControlInputInvalid, "signature 非法: %v", err)
	}
	if len(signature) != ed25519.SignatureSize {
		return ControlVerification{}, controlReject(ErrControlSignatureInvalid, "Ed25519 签名必须为 64 bytes")
	}

	payload, err := parseControlJSON(payloadBytes, "control payload")
	if err != nil {
		return ControlVerification{}, controlReject(ErrControlInputInvalid, "%v", err)
	}
	schema, ok := rawString(payload, "schema")
	if !ok || schema == "" || hasControlChars(schema) {
		return ControlVerification{}, controlReject(ErrControlInputInvalid, "control payload 缺少 schema")
	}
	if schema != operation.schema {
		return ControlVerification{}, controlReject(ErrControlBindingMismatch,
			"payload schema %s 与 %s 的 %s 不符", schema, expectedPurpose, operation.schema)
	}
	preimage := controlPreimage(domain, payloadBytes)
	if !ed25519.Verify(key.PublicKey, preimage, signature) {
		return ControlVerification{}, controlReject(ErrControlSignatureInvalid, "签名无效或签名域不匹配")
	}
	payloadPurpose, _ := rawString(payload, "purpose")
	if payloadPurpose != expectedPurpose {
		return ControlVerification{}, controlReject(ErrControlBindingMismatch,
			"payload purpose %s 与期望 %s 不符", payloadPurpose, expectedPurpose)
	}
	payloadDomain, _ := rawString(payload, "domain")
	if payloadDomain != domain {
		return ControlVerification{}, controlReject(ErrControlBindingMismatch,
			"payload domain %s 与期望 %s 不符", payloadDomain, domain)
	}
	payloadScope, scopeErr := parseControlScope(payload, "scope", ErrControlBindingMismatch, "payload")
	if scopeErr != nil || !controlScopesEqual(payloadScope, scope) {
		return ControlVerification{}, controlReject(ErrControlBindingMismatch, "payload scope 与期望不符")
	}
	digest := sha256.Sum256(preimage)
	return ControlVerification{
		Payload: payload, PayloadBytes: payloadBytes, PayloadScope: payloadScope,
		KeyID: key.KeyID, KeyPurpose: key.Purpose, Schema: schema,
		Digest: hex.EncodeToString(digest[:]),
	}, nil
}

// SignControlRequest 携带签发端需要的全部策略输入：没有 manifest 就无从核 key 的
// domains/scope/有效期（plan §2 L85「签发、验签两端均检查」），所以 manifest 是可选的
// ——只有刻意构造伪造 envelope 的测试才省略它。
type SignControlRequest struct {
	KeyID      string
	PrivateKey ed25519.PrivateKey
	Schema     string
	Domain     string
	Scope      ControlScope
	Manifest   *ControlTrustManifest
	Now        time.Time
}

// SignControlEnvelope exists so tests and the worker produce exactly the bytes the verifier
// expects; the private key never comes from the manifest.
func SignControlEnvelope(payload map[string]any, request SignControlRequest) ([]byte, error) {
	if payload == nil {
		return nil, controlReject(ErrControlInputInvalid, "payload 必须是对象")
	}
	body := map[string]any{}
	for key, value := range payload {
		body[key] = value
	}
	body["schema"] = request.Schema
	payloadBytes, err := json.Marshal(body)
	if err != nil {
		return nil, controlReject(ErrControlInputInvalid, "payload 无法编码: %v", err)
	}
	return SignControlPayloadBytes(payloadBytes, request)
}

// SignControlPayloadBytes signs the payload exactly as given. Cross-language equality is
// only meaningful over the same bytes: re-marshalling a map changes key order and therefore
// the signature, even when the JSON means the same thing.
func SignControlPayloadBytes(payloadBytes []byte, request SignControlRequest) ([]byte, error) {
	if !controlKeyRE.MatchString(request.KeyID) {
		return nil, controlReject(ErrControlInputInvalid, "keyId 不合法")
	}
	if request.Schema == "" {
		return nil, controlReject(ErrControlInputInvalid, "schema 缺失")
	}
	if request.Domain == "" {
		return nil, controlReject(ErrControlInputInvalid, "domain 缺失")
	}
	if len(request.Scope) == 0 {
		return nil, controlReject(ErrControlInputInvalid, "scope 非法")
	}
	signed, err := parseControlJSON(payloadBytes, "control payload")
	if err != nil {
		return nil, controlReject(ErrControlInputInvalid, "%v", err)
	}
	if payloadSchema, _ := rawString(signed, "schema"); payloadSchema != request.Schema {
		return nil, controlReject(ErrControlBindingMismatch, "payload schema 与签名 schema 不符")
	}
	if request.Manifest != nil {
		declared, present := request.Manifest.Keys[request.KeyID]
		if !present {
			return nil, controlReject(ErrControlKeyInvalid, "key %s 不在 trust manifest 中", request.KeyID)
		}
		now := request.Now
		if now.IsZero() {
			now = time.Now()
		}
		if err := assertKeyPolicy(declared, request.Domain, request.Scope, now); err != nil {
			return nil, err
		}
	}
	preimage := controlPreimage(request.Domain, payloadBytes)
	signature := ed25519.Sign(request.PrivateKey, preimage)
	envelope := map[string]string{
		"key_id":      request.KeyID,
		"payload_b64": base64.StdEncoding.EncodeToString(payloadBytes),
		"signature":   base64.StdEncoding.EncodeToString(signature),
	}
	return json.Marshal(envelope)
}
