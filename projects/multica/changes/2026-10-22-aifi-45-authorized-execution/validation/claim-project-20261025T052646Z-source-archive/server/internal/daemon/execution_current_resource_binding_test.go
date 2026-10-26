package daemon

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/multica-ai/multica/server/pkg/protocol"
)

const (
	aifi45ClientWorkspaceID      = "11111111-1111-4111-8111-111111111111"
	aifi45ClientProjectID        = "22222222-2222-4222-8222-222222222222"
	aifi45ClientOtherWorkspaceID = "33333333-3333-4333-8333-333333333333"
	aifi45ClientOtherProjectID   = "44444444-4444-4444-8444-444444444444"
	aifi45ClientResourceA        = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	aifi45ClientResourceB        = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
)

func aifi45ClientBinding(t *testing.T, resourceID, workspaceID, projectID, repoURL string) protocol.ProjectResourceBinding {
	t.Helper()
	resourceRef := `{"url":"` + repoURL + `","ref":"main","default_branch_hint":"main"}`
	binding, err := protocol.NewProjectResourceBinding(resourceID, workspaceID, projectID, "github_repo", []byte(resourceRef))
	if err != nil {
		t.Fatalf("NewProjectResourceBinding(%s): %v", resourceID, err)
	}
	return binding
}

func aifi45ClientBindingsJSON(t *testing.T, bindings []protocol.ProjectResourceBinding) string {
	t.Helper()
	raw, err := json.Marshal(bindings)
	if err != nil {
		t.Fatalf("marshal bindings: %v", err)
	}
	return string(raw)
}

func aifi45ClientDigest(t *testing.T, binding protocol.ProjectResourceBinding) string {
	t.Helper()
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
		t.Fatalf("marshal binding projection: %v", err)
	}
	h := sha256.New()
	_, _ = h.Write([]byte("project-resource-binding/v1\x00"))
	_, _ = h.Write(projection)
	return hex.EncodeToString(h.Sum(nil))
}

func aifi45ClientServe(t *testing.T, status int, body string) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		if _, err := w.Write([]byte(body)); err != nil {
			t.Errorf("write response: %v", err)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

func aifi45ClientSnapshot(t *testing.T, bindings []protocol.ProjectResourceBinding) string {
	t.Helper()
	raw, err := json.Marshal(struct {
		WorkspaceID             string                            `json:"workspace_id"`
		Repos                   []any                             `json:"repos"`
		ReposVersion            string                            `json:"repos_version"`
		Settings                map[string]any                    `json:"settings"`
		ProjectID               string                            `json:"project_id"`
		ProjectResourceBindings []protocol.ProjectResourceBinding `json:"project_resource_bindings"`
	}{
		WorkspaceID:             aifi45ClientWorkspaceID,
		Repos:                   []any{},
		ReposVersion:            "legacy-v1",
		Settings:                map[string]any{"legacy": true},
		ProjectID:               aifi45ClientProjectID,
		ProjectResourceBindings: bindings,
	})
	if err != nil {
		t.Fatalf("marshal snapshot: %v", err)
	}
	return string(raw)
}

func TestExecutionCurrentProjectResourceBindingsClient(t *testing.T) {
	ctx := context.Background()
	bindingA := aifi45ClientBinding(t, aifi45ClientResourceA, aifi45ClientWorkspaceID, aifi45ClientProjectID, "https://example.test/org/one.git")
	bindingB := aifi45ClientBinding(t, aifi45ClientResourceB, aifi45ClientWorkspaceID, aifi45ClientProjectID, "https://example.test/org/two.git")

	t.Run("valid descriptor with correct path and query", func(t *testing.T) {
		bindings := []protocol.ProjectResourceBinding{bindingA, bindingB}
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodGet {
				t.Errorf("method = %s, want GET", r.Method)
			}
			wantPath := "/api/daemon/workspaces/" + aifi45ClientWorkspaceID + "/repos"
			if r.URL.Path != wantPath {
				t.Errorf("path = %q, want %q", r.URL.Path, wantPath)
			}
			wantQuery := "project_id=" + aifi45ClientProjectID
			if r.URL.RawQuery != wantQuery {
				t.Errorf("raw query = %q, want %q", r.URL.RawQuery, wantQuery)
			}
			w.Header().Set("Content-Type", "application/json")
			response := map[string]any{
				"workspace_id":              aifi45ClientWorkspaceID,
				"repos":                     []any{},
				"repos_version":             "legacy-v1",
				"settings":                  map[string]any{"legacy": true},
				"project_id":                aifi45ClientProjectID,
				"project_resource_bindings": bindings,
			}
			if err := json.NewEncoder(w).Encode(response); err != nil {
				t.Errorf("encode response: %v", err)
			}
		}))
		t.Cleanup(srv.Close)

		got, err := NewClient(srv.URL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID)
		if err != nil {
			t.Fatalf("GetProjectResourceBindings: %v", err)
		}
		if !reflect.DeepEqual(got, bindings) {
			t.Fatalf("bindings = %#v, want %#v", got, bindings)
		}
	})

	t.Run("explicit empty array succeeds non-nil", func(t *testing.T) {
		body := `{"workspace_id":"` + aifi45ClientWorkspaceID + `","project_id":"` + aifi45ClientProjectID + `","project_resource_bindings":[]}`
		srv := aifi45ClientServe(t, http.StatusOK, body)

		got, err := NewClient(srv.URL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID)
		if err != nil {
			t.Fatalf("GetProjectResourceBindings: %v", err)
		}
		if got == nil {
			t.Fatal("bindings = nil, want non-nil empty slice")
		}
		if len(got) != 0 {
			t.Fatalf("len(bindings) = %d, want 0", len(got))
		}
	})

	validBindings := aifi45ClientBindingsJSON(t, []protocol.ProjectResourceBinding{bindingA, bindingB})
	crossWorkspaceBinding := aifi45ClientBinding(t, aifi45ClientResourceB, aifi45ClientOtherWorkspaceID, aifi45ClientProjectID, "https://example.test/org/two.git")
	crossProjectBinding := aifi45ClientBinding(t, aifi45ClientResourceB, aifi45ClientWorkspaceID, aifi45ClientOtherProjectID, "https://example.test/org/two.git")
	crossWorkspaceBindings := aifi45ClientBindingsJSON(t, []protocol.ProjectResourceBinding{bindingA, crossWorkspaceBinding})
	crossProjectBindings := aifi45ClientBindingsJSON(t, []protocol.ProjectResourceBinding{bindingA, crossProjectBinding})
	duplicateBindings := aifi45ClientBindingsJSON(t, []protocol.ProjectResourceBinding{bindingA, bindingA})

	tamperedDigest := bindingA
	tamperedDigest.BindingDigest = strings.Repeat("0", 64)
	tamperedDigestBindings := aifi45ClientBindingsJSON(t, []protocol.ProjectResourceBinding{tamperedDigest})

	malformedIdentity := bindingA
	malformedIdentity.IdentityB64 = "!!!!not-base64!!!!"
	malformedIdentity.BindingDigest = aifi45ClientDigest(t, malformedIdentity)
	malformedIdentityBindings := aifi45ClientBindingsJSON(t, []protocol.ProjectResourceBinding{malformedIdentity})

	nonCanonicalIdentity := bindingA
	nonCanonicalIdentity.IdentityB64 = base64.StdEncoding.EncodeToString([]byte(`{"ref":"main","url":"https://example.test/org/one.git","default_branch_hint":"main"}`))
	nonCanonicalIdentity.BindingDigest = aifi45ClientDigest(t, nonCanonicalIdentity)
	nonCanonicalIdentityBindings := aifi45ClientBindingsJSON(t, []protocol.ProjectResourceBinding{nonCanonicalIdentity})

	negativeCases := []struct {
		name string
		body string
	}{
		{
			name: "old service missing new fields",
			body: `{"workspace_id":"` + aifi45ClientWorkspaceID + `","repos":[],"repos_version":"legacy-v1"}`,
		},
		{
			name: "null project resource bindings",
			body: `{"workspace_id":"` + aifi45ClientWorkspaceID + `","project_id":"` + aifi45ClientProjectID + `","project_resource_bindings":null}`,
		},
		{
			name: "null project id",
			body: `{"workspace_id":"` + aifi45ClientWorkspaceID + `","project_id":null,"project_resource_bindings":` + validBindings + `}`,
		},
		{
			name: "wrong workspace",
			body: `{"workspace_id":"` + aifi45ClientOtherWorkspaceID + `","project_id":"` + aifi45ClientProjectID + `","project_resource_bindings":` + validBindings + `}`,
		},
		{
			name: "wrong project",
			body: `{"workspace_id":"` + aifi45ClientWorkspaceID + `","project_id":"` + aifi45ClientOtherProjectID + `","project_resource_bindings":` + validBindings + `}`,
		},
		{
			name: "entry crosses workspace scope",
			body: `{"workspace_id":"` + aifi45ClientWorkspaceID + `","project_id":"` + aifi45ClientProjectID + `","project_resource_bindings":` + crossWorkspaceBindings + `}`,
		},
		{
			name: "entry crosses project scope",
			body: `{"workspace_id":"` + aifi45ClientWorkspaceID + `","project_id":"` + aifi45ClientProjectID + `","project_resource_bindings":` + crossProjectBindings + `}`,
		},
		{
			name: "duplicate resource uuid",
			body: `{"workspace_id":"` + aifi45ClientWorkspaceID + `","project_id":"` + aifi45ClientProjectID + `","project_resource_bindings":` + duplicateBindings + `}`,
		},
		{
			name: "tampered binding digest",
			body: `{"workspace_id":"` + aifi45ClientWorkspaceID + `","project_id":"` + aifi45ClientProjectID + `","project_resource_bindings":` + tamperedDigestBindings + `}`,
		},
		{
			name: "malformed identity b64",
			body: `{"workspace_id":"` + aifi45ClientWorkspaceID + `","project_id":"` + aifi45ClientProjectID + `","project_resource_bindings":` + malformedIdentityBindings + `}`,
		},
		{
			name: "noncanonical identity b64",
			body: `{"workspace_id":"` + aifi45ClientWorkspaceID + `","project_id":"` + aifi45ClientProjectID + `","project_resource_bindings":` + nonCanonicalIdentityBindings + `}`,
		},
	}

	for _, tc := range negativeCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			srv := aifi45ClientServe(t, http.StatusOK, tc.body)
			if _, err := NewClient(srv.URL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID); err == nil {
				t.Fatal("GetProjectResourceBindings succeeded, want error")
			}
		})
	}

	t.Run("server 503", func(t *testing.T) {
		srv := aifi45ClientServe(t, http.StatusServiceUnavailable, `{"error":"unavailable"}`)
		if _, err := NewClient(srv.URL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID); err == nil {
			t.Fatal("GetProjectResourceBindings succeeded on 503, want error")
		}
	})

	t.Run("server disconnected", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
		baseURL := srv.URL
		srv.Close()

		if _, err := NewClient(baseURL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID); err == nil {
			t.Fatal("GetProjectResourceBindings succeeded against disconnected server, want error")
		}
	})

	t.Run("redirect is not followed", func(t *testing.T) {
		snapshot := aifi45ClientSnapshot(t, []protocol.ProjectResourceBinding{bindingA, bindingB})
		var targetHits int32
		target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			atomic.AddInt32(&targetHits, 1)
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(snapshot))
		}))
		t.Cleanup(target.Close)
		entry := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			http.Redirect(w, r, target.URL, http.StatusFound)
		}))
		t.Cleanup(entry.Close)

		client := NewClient(entry.URL)
		client.SetToken("mdt_literal_test_only")
		if _, err := client.GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID); err == nil {
			t.Fatal("GetProjectResourceBindings succeeded through redirect, want error")
		}
		if hits := atomic.LoadInt32(&targetHits); hits != 0 {
			t.Fatalf("redirect target received %d request(s), want 0", hits)
		}
	})

	t.Run("oversized metadata response rejected", func(t *testing.T) {
		snapshot := aifi45ClientSnapshot(t, []protocol.ProjectResourceBinding{bindingA, bindingB})
		// 1 MiB is the transport safety ceiling for this metadata response,
		// not a product limit on project resources.
		body := snapshot + strings.Repeat(" ", (1<<20)+1)
		srv := aifi45ClientServe(t, http.StatusOK, body)

		if _, err := NewClient(srv.URL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID); err == nil {
			t.Fatal("GetProjectResourceBindings accepted an oversized response, want error")
		}
	})

	t.Run("trailing second json document rejected", func(t *testing.T) {
		base := aifi45ClientSnapshot(t, []protocol.ProjectResourceBinding{bindingA, bindingB})
		srv := aifi45ClientServe(t, http.StatusOK, base+`{"second":true}`)

		if _, err := NewClient(srv.URL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID); err == nil {
			t.Fatal("GetProjectResourceBindings accepted a second JSON document, want error")
		}
	})

	t.Run("duplicate top-level key rejected", func(t *testing.T) {
		base := aifi45ClientSnapshot(t, []protocol.ProjectResourceBinding{bindingA, bindingB})
		from := `"project_id":"` + aifi45ClientProjectID + `"`
		to := from + `,"project_id":"` + aifi45ClientProjectID + `"`
		body := strings.Replace(base, from, to, 1)
		if body == base {
			t.Fatal("fixture does not contain project_id")
		}
		srv := aifi45ClientServe(t, http.StatusOK, body)

		if _, err := NewClient(srv.URL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID); err == nil {
			t.Fatal("GetProjectResourceBindings accepted a duplicate top-level key, want error")
		}
	})

	t.Run("duplicate descriptor key rejected", func(t *testing.T) {
		base := aifi45ClientSnapshot(t, []protocol.ProjectResourceBinding{bindingA, bindingB})
		from := `"resource_id":"` + aifi45ClientResourceA + `"`
		to := from + `,"resource_id":"` + aifi45ClientResourceA + `"`
		body := strings.Replace(base, from, to, 1)
		if body == base {
			t.Fatal("fixture does not contain resource_id")
		}
		srv := aifi45ClientServe(t, http.StatusOK, body)

		if _, err := NewClient(srv.URL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID); err == nil {
			t.Fatal("GetProjectResourceBindings accepted a duplicate descriptor key, want error")
		}
	})

	// json.Unmarshal matches field names case-insensitively. These aliases are
	// not exact duplicate keys for the scanner, but they must not replace the
	// canonical field after it has been validated.
	t.Run("case-folded aliases cannot override canonical fields", func(t *testing.T) {
		t.Run("alias cannot replace invalid canonical bindings", func(t *testing.T) {
			tampered := bindingA
			tampered.BindingDigest = strings.Repeat("0", 64)
			snapshot := aifi45ClientSnapshot(t, []protocol.ProjectResourceBinding{tampered})
			body := strings.TrimSuffix(snapshot, "}") + `,"PROJECT_RESOURCE_BINDINGS":[]}`
			srv := aifi45ClientServe(t, http.StatusOK, body)

			if _, err := NewClient(srv.URL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID); err == nil {
				t.Fatal("GetProjectResourceBindings accepted a case-folded bindings alias, want error")
			}
		})

		t.Run("alias cannot replace wrong canonical workspace", func(t *testing.T) {
			snapshot := aifi45ClientSnapshot(t, []protocol.ProjectResourceBinding{bindingA})
			from := `"workspace_id":"` + aifi45ClientWorkspaceID + `"`
			to := `"workspace_id":"` + aifi45ClientOtherWorkspaceID + `"`
			body := strings.Replace(snapshot, from, to, 1)
			if body == snapshot {
				t.Fatal("fixture does not contain top-level workspace_id")
			}
			body = strings.TrimSuffix(body, "}") + `,"WORKSPACE_ID":"` + aifi45ClientWorkspaceID + `"}`
			srv := aifi45ClientServe(t, http.StatusOK, body)

			if _, err := NewClient(srv.URL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID); err == nil {
				t.Fatal("GetProjectResourceBindings accepted a case-folded workspace alias, want error")
			}
		})

		t.Run("alias cannot replace tampered canonical descriptor digest", func(t *testing.T) {
			tampered := bindingA
			tampered.BindingDigest = strings.Repeat("0", 64)
			snapshot := aifi45ClientSnapshot(t, []protocol.ProjectResourceBinding{tampered})
			from := `"binding_digest":"` + strings.Repeat("0", 64) + `"`
			to := from + `,"BINDING_DIGEST":"` + bindingA.BindingDigest + `"`
			body := strings.Replace(snapshot, from, to, 1)
			if body == snapshot {
				t.Fatal("fixture does not contain descriptor binding_digest")
			}
			srv := aifi45ClientServe(t, http.StatusOK, body)

			if _, err := NewClient(srv.URL).GetProjectResourceBindings(ctx, aifi45ClientWorkspaceID, aifi45ClientProjectID); err == nil {
				t.Fatal("GetProjectResourceBindings accepted a case-folded descriptor digest alias, want error")
			}
		})
	})
}
