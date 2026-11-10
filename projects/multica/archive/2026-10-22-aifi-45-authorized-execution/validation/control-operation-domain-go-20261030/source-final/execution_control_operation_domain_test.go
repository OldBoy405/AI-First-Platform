package governance

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"testing"
	"time"
)

func TestControlOperationDomainBindings(t *testing.T) {
	operations := []struct{ purpose, schema, domain, keyPurpose string }{
		{"command", "execution-control-command/v1", "execution-control-command/v1", "control-command"},
		{"verdict", "execution-control-verdict/v1", "execution-verdict/v1", "tool-attestation"},
		{"checkpoint", "execution-control-checkpoint/v1", "execution-control-checkpoint/v1", "tool-attestation"},
		{"readiness-request", "execution-readiness-request/v1", "execution-policy-readiness-request/v1", "tool-attestation"},
		{"readiness-verdict", "execution-readiness-verdict/v1", "execution-policy-readiness/v1", "tool-attestation"},
		{"resume", "execution-resume/v1", "execution-repair-resume/v1", "human"},
		{"deployment-observer", "execution-deployment-observation/v1", "execution-deployment-observation/v1", "deployment-observer"},
	}
	if len(controlOperations) != len(operations) {
		t.Fatalf("unexpected operation count: %d", len(controlOperations))
	}
	for _, op := range operations {
		actual, ok := controlOperations[op.purpose]
		if !ok || actual.schema != op.schema || actual.domain != op.domain || actual.purpose != op.keyPurpose {
			t.Fatalf("unexpected fixed operation table entry: %s", op.purpose)
		}
	}
	now := time.Date(2026, 10, 27, 0, 0, 0, 0, time.UTC)
	privateKey := ed25519.NewKeyFromSeed(bytes.Repeat([]byte{7}, ed25519.SeedSize))
	publicKey := privateKey.Public().(ed25519.PublicKey)
	scope := ControlScope{"workspace_id": "fictional-workspace"}
	domains := make([]string, 0, len(operations))
	seen := make(map[string]bool)
	for _, op := range operations {
		if seen[op.domain] {
			t.Fatalf("duplicate expected domain: %s", op.domain)
		}
		seen[op.domain] = true
		domains = append(domains, op.domain)
	}

	for _, op := range operations {
		for _, domain := range domains {
			t.Run(op.purpose+"/"+domain, func(t *testing.T) {
				manifest := &ControlTrustManifest{Keys: map[string]ControlKey{"fixture-key": {
					KeyID: "fixture-key", Purpose: op.keyPurpose, Domains: domains, Scope: scope,
					ValidFrom: now.Add(-time.Hour), ValidUntil: now.Add(time.Hour), PublicKey: publicKey,
				}}}
				payload := map[string]any{"purpose": op.purpose, "domain": domain, "scope": scope}
				raw, err := SignControlEnvelope(payload, SignControlRequest{
					KeyID: "fixture-key", PrivateKey: privateKey, Schema: op.schema,
					Domain: domain, Scope: scope, Manifest: manifest, Now: now,
				})
				if err != nil {
					t.Fatalf("fixture signing failed: %v", err)
				}
				var envelope struct {
					PayloadB64 string `json:"payload_b64"`
					Signature  string `json:"signature"`
				}
				if err := json.Unmarshal(raw, &envelope); err != nil {
					t.Fatalf("fixture envelope decode failed: %v", err)
				}
				body, bodyErr := base64.StdEncoding.DecodeString(envelope.PayloadB64)
				sig, sigErr := base64.StdEncoding.DecodeString(envelope.Signature)
				preimage := append(append([]byte(domain), 0), body...)
				if bodyErr != nil || sigErr != nil || !ed25519.Verify(publicKey, preimage, sig) {
					t.Fatal("fixture signature verification failed")
				}
				_, err = VerifyControlEnvelope(raw, op.purpose, domain, scope, manifest, now)
				if domain == op.domain {
					if err != nil {
						t.Fatalf("fixed domain refused: %v", err)
					}
				} else if !errors.Is(err, ErrControlBindingMismatch) {
					t.Fatalf("foreign domain not rejected as binding mismatch: %v", err)
				}
			})
		}
	}
}
