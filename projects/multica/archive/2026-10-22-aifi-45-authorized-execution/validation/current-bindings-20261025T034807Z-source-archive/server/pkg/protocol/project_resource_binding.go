package protocol

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/url"
	"strings"
	"unicode"
)

// ProjectResourceBinding is the immutable, versioned resource identity frozen
// into an execution authorization. AIFIRST AIFI-45: it describes what the
// human selected, not that the remote repository is cloneable or that a
// daemon's local path currently resolves to the same real directory.
//
// JSON field order is part of the cross-repository contract.
type ProjectResourceBinding struct {
	ResourceID    string `json:"resource_id"`
	WorkspaceID   string `json:"workspace_id"`
	ProjectID     string `json:"project_id"`
	ResourceType  string `json:"resource_type"`
	IdentityB64   string `json:"identity_b64"`
	BindingDigest string `json:"binding_digest"`
}

const projectResourceBindingDomain = "project-resource-binding/v1\x00"

// NewProjectResourceBinding derives the binding digest from the server-stored
// resource row. resourceRef is the raw project_resource.resource_ref JSON as
// stored; only the identity fields are copied, never labels or secrets.
func NewProjectResourceBinding(resourceID, workspaceID, projectID, resourceType string, resourceRef []byte) (ProjectResourceBinding, error) {
	if !isLowerCanonicalUUID(resourceID) || !isLowerCanonicalUUID(workspaceID) || !isLowerCanonicalUUID(projectID) {
		return ProjectResourceBinding{}, errors.New("project resource binding: ids must be lowercase canonical UUIDs")
	}

	var identity []byte
	switch resourceType {
	case "local_directory":
		encoded, err := localDirectoryBindingIdentity(resourceRef)
		if err != nil {
			return ProjectResourceBinding{}, err
		}
		identity = encoded
	case "github_repo":
		encoded, err := githubRepoBindingIdentity(resourceRef)
		if err != nil {
			return ProjectResourceBinding{}, err
		}
		identity = encoded
	default:
		return ProjectResourceBinding{}, errors.New("project resource binding: unsupported resource_type")
	}

	binding := ProjectResourceBinding{
		ResourceID:   resourceID,
		WorkspaceID:  workspaceID,
		ProjectID:    projectID,
		ResourceType: resourceType,
		IdentityB64:  base64.StdEncoding.EncodeToString(identity),
	}
	projection, err := json.Marshal(struct {
		ResourceID   string `json:"resource_id"`
		WorkspaceID  string `json:"workspace_id"`
		ProjectID    string `json:"project_id"`
		ResourceType string `json:"resource_type"`
		IdentityB64  string `json:"identity_b64"`
	}{
		ResourceID:   binding.ResourceID,
		WorkspaceID:  binding.WorkspaceID,
		ProjectID:    binding.ProjectID,
		ResourceType: binding.ResourceType,
		IdentityB64:  binding.IdentityB64,
	})
	if err != nil {
		return ProjectResourceBinding{}, err
	}
	digest := sha256.New()
	_, _ = digest.Write([]byte(projectResourceBindingDomain))
	_, _ = digest.Write(projection)
	binding.BindingDigest = hex.EncodeToString(digest.Sum(nil))
	return binding, nil
}

// AIFIRST AIFI-45: local identity intentionally excludes resource label and
// any server-unknown fields. An absent mode means in_place for legacy rows.
type localDirectoryIdentity struct {
	DaemonID      string `json:"daemon_id"`
	LocalPath     string `json:"local_path"`
	ExecutionMode string `json:"execution_mode"`
}

func localDirectoryBindingIdentity(resourceRef []byte) ([]byte, error) {
	var ref struct {
		DaemonID      string `json:"daemon_id"`
		LocalPath     string `json:"local_path"`
		ExecutionMode string `json:"execution_mode"`
	}
	if err := json.Unmarshal(resourceRef, &ref); err != nil {
		return nil, errors.New("project resource binding: invalid local_directory resource_ref")
	}
	if strings.TrimSpace(ref.DaemonID) == "" || hasControl(ref.DaemonID) {
		return nil, errors.New("project resource binding: local_directory daemon_id is required")
	}
	if !isPlatformAbsolutePath(ref.LocalPath) {
		return nil, errors.New("project resource binding: local_directory local_path must be an absolute path")
	}
	switch ref.ExecutionMode {
	case "":
		ref.ExecutionMode = "in_place"
	case "in_place", "worktree":
	default:
		return nil, errors.New("project resource binding: invalid local_directory execution_mode")
	}
	return json.Marshal(localDirectoryIdentity{
		DaemonID:      ref.DaemonID,
		LocalPath:     ref.LocalPath,
		ExecutionMode: ref.ExecutionMode,
	})
}

// AIFIRST AIFI-45: github identity keeps the registered declaration. The
// binding does not prove the remote exists or that the URL is fetchable.
type githubRepoIdentity struct {
	URL               string `json:"url"`
	Ref               string `json:"ref"`
	DefaultBranchHint string `json:"default_branch_hint"`
}

func githubRepoBindingIdentity(resourceRef []byte) ([]byte, error) {
	var ref struct {
		URL               string `json:"url"`
		Ref               string `json:"ref"`
		DefaultBranchHint string `json:"default_branch_hint"`
	}
	if err := json.Unmarshal(resourceRef, &ref); err != nil {
		return nil, errors.New("project resource binding: invalid github_repo resource_ref")
	}
	if err := validateGithubBindingURL(ref.URL); err != nil {
		return nil, err
	}
	if hasControl(ref.Ref) || hasControl(ref.DefaultBranchHint) {
		return nil, errors.New("project resource binding: github_repo identity contains control characters")
	}
	return json.Marshal(githubRepoIdentity{
		URL:               ref.URL,
		Ref:               ref.Ref,
		DefaultBranchHint: ref.DefaultBranchHint,
	})
}

func validateGithubBindingURL(raw string) error {
	if raw == "" || strings.TrimSpace(raw) != raw || hasControl(raw) || strings.ContainsAny(raw, " \t\r\n") {
		return errors.New("project resource binding: github_repo url is required")
	}
	if strings.ContainsAny(raw, "?#") {
		return errors.New("project resource binding: github_repo url must not contain query or fragment")
	}

	if strings.Contains(raw, "://") {
		parsed, err := url.Parse(raw)
		if err != nil || parsed == nil || parsed.Host == "" {
			return errors.New("project resource binding: invalid github_repo url")
		}
		hostname := parsed.Hostname()
		if hostname == "" {
			return errors.New("project resource binding: invalid github_repo url")
		}
		// ponytail: v1 signs only the Go/WHATWG shared URL subset. Go accepts
		// IPv6 zone identifiers, but WHATWG consumers reject them, so refuse
		// them here instead of signing a binding the Node side cannot accept.
		// Add cross-language vectors before supporting zones.
		if strings.Contains(hostname, "%") {
			return errors.New("project resource binding: github_repo url IPv6 zone is unsupported by the v1 shared URL subset")
		}
		switch parsed.Scheme {
		case "http", "https":
			if parsed.User != nil {
				return errors.New("project resource binding: http(s) github_repo url must not contain userinfo")
			}
		case "ssh":
			if parsed.User != nil {
				if _, hasPassword := parsed.User.Password(); hasPassword {
					return errors.New("project resource binding: ssh github_repo url must not contain a password")
				}
			}
		default:
			return errors.New("project resource binding: unsupported github_repo url scheme")
		}
		return nil
	}

	colon := strings.Index(raw, ":")
	if colon <= 0 || colon == len(raw)-1 {
		return errors.New("project resource binding: invalid scp-style github_repo url")
	}
	for _, scheme := range []string{"http", "https", "ssh", "git", "ftp"} {
		if strings.EqualFold(raw[:colon], scheme) {
			return errors.New("project resource binding: invalid github_repo url")
		}
	}
	hostStart := 0
	if at := strings.Index(raw, "@"); at >= 0 {
		if at >= colon || at == 0 || strings.Contains(raw[:at], ":") {
			return errors.New("project resource binding: invalid scp-style github_repo url userinfo")
		}
		hostStart = at + 1
	}
	host := raw[hostStart:colon]
	path := raw[colon+1:]
	if host == "" || path == "" || strings.ContainsAny(host, "/\\") {
		return errors.New("project resource binding: invalid scp-style github_repo url")
	}
	return nil
}

func isLowerCanonicalUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i := 0; i < len(s); i++ {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if s[i] != '-' {
				return false
			}
			continue
		}
		c := s[i]
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return false
		}
	}
	return true
}

func isPlatformAbsolutePath(s string) bool {
	if s == "" || hasControl(s) {
		return false
	}
	if strings.HasPrefix(s, "/") {
		return true
	}
	if strings.HasPrefix(s, `\\`) {
		// A complete UNC path is \\server\share with an optional
		// backslash-separated tail. One component is drive-relative and a
		// forward slash would make the native resolver platform-dependent.
		rest := s[2:]
		if rest == "" || strings.Contains(rest, "/") {
			return false
		}
		parts := strings.Split(rest, `\`)
		if len(parts) < 2 || parts[0] == "" || parts[1] == "" {
			return false
		}
		for i := 2; i < len(parts); i++ {
			if parts[i] == "" && i != len(parts)-1 {
				return false
			}
		}
		return true
	}
	return len(s) >= 3 &&
		((s[0] >= 'a' && s[0] <= 'z') || (s[0] >= 'A' && s[0] <= 'Z')) &&
		s[1] == ':' && (s[2] == '\\' || s[2] == '/')
}

func hasControl(s string) bool {
	for _, r := range s {
		if unicode.IsControl(r) {
			return true
		}
	}
	return false
}
