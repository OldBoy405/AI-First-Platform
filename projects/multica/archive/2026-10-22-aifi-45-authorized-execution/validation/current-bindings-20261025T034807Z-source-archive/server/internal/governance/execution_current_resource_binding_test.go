// AIFIRST: AIFI-45 current project-resource bindings through the real daemon
// auth path. This is a DB snapshot readback, not a head/claim attestation.
package governance_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/multica-ai/multica/server/internal/auth"
	"github.com/multica-ai/multica/server/internal/daemon"
	"github.com/multica-ai/multica/server/internal/governance"
	"github.com/multica-ai/multica/server/internal/handler"
	"github.com/multica-ai/multica/server/internal/middleware"
	"github.com/multica-ai/multica/server/internal/testutil"
	db "github.com/multica-ai/multica/server/pkg/db/generated"
	"github.com/multica-ai/multica/server/pkg/protocol"
)

type currentBindingResponse struct {
	WorkspaceID             string                             `json:"workspace_id"`
	ProjectID               *string                            `json:"project_id"`
	ProjectResourceBindings *[]protocol.ProjectResourceBinding `json:"project_resource_bindings"`
}

type currentBindingHarness struct {
	pool        *pgxpool.Pool
	fx          *testutil.Fixture
	workspaceID string
	daemonID    string
	token       string
	routes      http.Handler
}

func newCurrentBindingHarness(t *testing.T) *currentBindingHarness {
	t.Helper()
	ctx := context.Background()
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		t.Fatal("dedicated database required")
	}
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)

	workspaceID := governance.FixtureWorkspaceIDForTest()
	fx := testutil.New(pool, workspaceID, "")
	fx.UserID = fx.User(t, "Current binding owner", "current-binding-"+uuid.NewString()+"@example.test")
	fx.Member(t, workspaceID, fx.UserID, "owner")

	queries := db.New(pool)
	h := &currentBindingHarness{
		pool:        pool,
		fx:          fx,
		workspaceID: workspaceID,
		daemonID:    "current-binding-daemon-" + uuid.NewString(),
	}
	h.token = h.mintDaemonToken(t, h.daemonID)

	hapi := &handler.Handler{Queries: queries, DB: pool, TxStarter: pool}
	routes := chi.NewRouter()
	routes.Route("/api/daemon", func(r chi.Router) {
		r.Use(middleware.DaemonAuth(queries, nil, nil, nil))
		r.Get("/workspaces/{workspaceId}/repos", hapi.GetDaemonWorkspaceRepos)
	})
	h.routes = routes
	return h
}

func (h *currentBindingHarness) mintDaemonToken(t *testing.T, daemonID string) string {
	t.Helper()
	token := "mdt_" + uuid.NewString()
	tokenHash := auth.HashToken(token)
	if _, err := h.pool.Exec(context.Background(), `
		INSERT INTO daemon_token (token_hash, workspace_id, daemon_id, expires_at)
		VALUES ($1, $2::uuid, $3, now() + interval '1 hour')`,
		tokenHash, h.workspaceID, daemonID); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if _, err := h.pool.Exec(context.Background(), `DELETE FROM daemon_token WHERE token_hash=$1`, tokenHash); err != nil {
			t.Error(err)
		}
	})
	return token
}

func (h *currentBindingHarness) projectPath(projectID string) string {
	return "/api/daemon/workspaces/" + h.workspaceID + "/repos?project_id=" + url.QueryEscape(projectID)
}

func (h *currentBindingHarness) get(t *testing.T, path, token string, extraHeaders map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("X-Daemon-ID", h.daemonID)
	for name, value := range extraHeaders {
		req.Header.Set(name, value)
	}
	rec := httptest.NewRecorder()
	h.routes.ServeHTTP(rec, req)
	return rec
}

func (h *currentBindingHarness) getProject(t *testing.T, projectID string) *httptest.ResponseRecorder {
	t.Helper()
	return h.get(t, h.projectPath(projectID), h.token, nil)
}

func (h *currentBindingHarness) projectBindings(t *testing.T, projectID string) (*httptest.ResponseRecorder, []protocol.ProjectResourceBinding) {
	t.Helper()
	rec := h.getProject(t, projectID)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET current project bindings = %d, want 200: %s", rec.Code, rec.Body.String())
	}
	var resp currentBindingResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp.WorkspaceID != h.workspaceID {
		t.Fatalf("workspace_id = %q, want %q", resp.WorkspaceID, h.workspaceID)
	}
	if resp.ProjectID == nil || *resp.ProjectID != projectID {
		t.Fatalf("project_id = %v, want %q", resp.ProjectID, projectID)
	}
	if resp.ProjectResourceBindings == nil {
		t.Fatal("project_resource_bindings is missing; current bindings must not be inferred or omitted")
	}
	return rec, *resp.ProjectResourceBindings
}

func (h *currentBindingHarness) insertResource(t *testing.T, projectID, resourceType, resourceRef string, position int) string {
	t.Helper()
	return h.fx.Insert(t, "project_resource", testutil.Cols{
		"project_id":    projectID,
		"workspace_id":  h.workspaceID,
		"resource_type": resourceType,
		"resource_ref":  resourceRef,
		"position":      position,
	})
}

func (h *currentBindingHarness) replaceResourceRef(t *testing.T, resourceID, projectID, oldRef, newRef string) {
	t.Helper()
	h.execOne(t, `
		UPDATE project_resource SET resource_ref=$1::jsonb
		WHERE id=$2::uuid AND workspace_id=$3::uuid AND project_id=$4::uuid`,
		newRef, resourceID, h.workspaceID, projectID)
	t.Cleanup(func() {
		h.execCleanup(t, `
			UPDATE project_resource SET resource_ref=$1::jsonb
			WHERE id=$2::uuid AND workspace_id=$3::uuid AND project_id=$4::uuid`,
			oldRef, resourceID, h.workspaceID, projectID)
	})
}

func (h *currentBindingHarness) setLabelAndPosition(t *testing.T, resourceID, projectID, label string, position int) {
	t.Helper()
	h.execOne(t, `
		UPDATE project_resource SET label=$1, position=$2
		WHERE id=$3::uuid AND workspace_id=$4::uuid AND project_id=$5::uuid`,
		label, position, resourceID, h.workspaceID, projectID)
	t.Cleanup(func() {
		h.execCleanup(t, `
			UPDATE project_resource SET label=NULL, position=0
			WHERE id=$1::uuid AND workspace_id=$2::uuid AND project_id=$3::uuid`,
			resourceID, h.workspaceID, projectID)
	})
}

func (h *currentBindingHarness) moveResource(t *testing.T, resourceID, fromProjectID, toProjectID string) {
	t.Helper()
	h.execOne(t, `
		UPDATE project_resource SET project_id=$1::uuid
		WHERE id=$2::uuid AND workspace_id=$3::uuid AND project_id=$4::uuid`,
		toProjectID, resourceID, h.workspaceID, fromProjectID)
	t.Cleanup(func() {
		h.execCleanup(t, `
			UPDATE project_resource SET project_id=$1::uuid
			WHERE id=$2::uuid AND workspace_id=$3::uuid AND project_id=$4::uuid`,
			fromProjectID, resourceID, h.workspaceID, toProjectID)
	})
}

func (h *currentBindingHarness) deleteResource(t *testing.T, resourceID, projectID string) {
	t.Helper()
	h.execOne(t, `
		DELETE FROM project_resource
		WHERE id=$1::uuid AND workspace_id=$2::uuid AND project_id=$3::uuid`,
		resourceID, h.workspaceID, projectID)
}

func (h *currentBindingHarness) execOne(t *testing.T, query string, args ...any) {
	t.Helper()
	tag, err := h.pool.Exec(context.Background(), query, args...)
	if err != nil {
		t.Fatalf("fixture mutation: %v", err)
	}
	if tag.RowsAffected() != 1 {
		t.Fatalf("fixture mutation affected %d rows, want 1", tag.RowsAffected())
	}
}

func (h *currentBindingHarness) execCleanup(t *testing.T, query string, args ...any) {
	if _, err := h.pool.Exec(context.Background(), query, args...); err != nil {
		t.Errorf("fixture restore: %v", err)
	}
}

func currentBindingByID(t *testing.T, bindings []protocol.ProjectResourceBinding) map[string]protocol.ProjectResourceBinding {
	t.Helper()
	byID := make(map[string]protocol.ProjectResourceBinding, len(bindings))
	for _, binding := range bindings {
		if _, duplicate := byID[binding.ResourceID]; duplicate {
			t.Fatalf("duplicate resource binding for %s", binding.ResourceID)
		}
		byID[binding.ResourceID] = binding
	}
	return byID
}

func currentBindingIdentity(t *testing.T, binding protocol.ProjectResourceBinding) map[string]string {
	t.Helper()
	identityJSON, err := base64.StdEncoding.DecodeString(binding.IdentityB64)
	if err != nil {
		t.Fatalf("identity_b64 is not canonical base64: %v", err)
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(identityJSON, &raw); err != nil {
		t.Fatalf("identity is not a JSON object: %v", err)
	}
	if len(raw) != 3 {
		t.Fatalf("identity has %d fields, want exactly 3: %s", len(raw), identityJSON)
	}
	identity := make(map[string]string, len(raw))
	for field, value := range raw {
		var text string
		if err := json.Unmarshal(value, &text); err != nil {
			t.Fatalf("identity field %s is not a string: %v", field, err)
		}
		identity[field] = text
	}
	return identity
}

func assertCurrentBindingScope(t *testing.T, binding protocol.ProjectResourceBinding, workspaceID, projectID, resourceID, resourceType string) {
	t.Helper()
	if binding.ResourceID != resourceID {
		t.Errorf("resource_id = %q, want %q", binding.ResourceID, resourceID)
	}
	if binding.WorkspaceID != workspaceID {
		t.Errorf("%s workspace_id = %q, want %q", resourceType, binding.WorkspaceID, workspaceID)
	}
	if binding.ProjectID != projectID {
		t.Errorf("%s project_id = %q, want %q", resourceType, binding.ProjectID, projectID)
	}
	if binding.ResourceType != resourceType {
		t.Errorf("%s resource_type = %q", resourceType, binding.ResourceType)
	}
	if len(binding.BindingDigest) != 64 {
		t.Errorf("%s binding_digest = %q, want 64 hex characters", resourceType, binding.BindingDigest)
	}
}

func assertCurrentBindingIdentity(t *testing.T, binding protocol.ProjectResourceBinding, want map[string]string) {
	t.Helper()
	identity := currentBindingIdentity(t, binding)
	for field, value := range want {
		if identity[field] != value {
			t.Errorf("%s identity %s = %q, want %q", binding.ResourceType, field, identity[field], value)
		}
	}
	for _, forbidden := range []string{"resource_ref", "label", "token", "secret", "created_by"} {
		if _, present := identity[forbidden]; present {
			t.Errorf("%s identity leaked %q", binding.ResourceType, forbidden)
		}
	}
}

func TestExecutionCurrentProjectResourceBindings(t *testing.T) {
	h := newCurrentBindingHarness(t)
	projectID := h.fx.Project(t, "AIFI-45 current binding project")

	daemonID := h.daemonID
	localPath := "/srv/aifi45/current-binding"
	repoURL := "https://example.test/aifi45/current-binding.git"
	localRef := `{"daemon_id":"` + daemonID + `","local_path":"` + localPath + `","execution_mode":"in_place"}`
	githubRef := `{"url":"` + repoURL + `","ref":"main","default_branch_hint":"main"}`
	localResourceID := h.insertResource(t, projectID, "local_directory", localRef, 0)
	githubResourceID := h.insertResource(t, projectID, "github_repo", githubRef, 1)

	t.Run("fresh_bindings", func(t *testing.T) {
		rec, bindings := h.projectBindings(t, projectID)
		if len(bindings) != 2 {
			t.Fatalf("project_resource_bindings has %d entries, want 2: %s", len(bindings), rec.Body.String())
		}
		byID := currentBindingByID(t, bindings)
		local, ok := byID[localResourceID]
		if !ok {
			t.Fatalf("missing local_directory binding %s", localResourceID)
		}
		assertCurrentBindingScope(t, local, h.workspaceID, projectID, localResourceID, "local_directory")
		assertCurrentBindingIdentity(t, local, map[string]string{
			"daemon_id": daemonID, "local_path": localPath, "execution_mode": "in_place",
		})
		github, ok := byID[githubResourceID]
		if !ok {
			t.Fatalf("missing github_repo binding %s", githubResourceID)
		}
		assertCurrentBindingScope(t, github, h.workspaceID, projectID, githubResourceID, "github_repo")
		assertCurrentBindingIdentity(t, github, map[string]string{
			"url": repoURL, "ref": "main", "default_branch_hint": "main",
		})
	})

	t.Run("sdk_current_bindings", func(t *testing.T) {
		server := httptest.NewServer(h.routes)
		defer server.Close()
		client := daemon.NewClient(server.URL)
		client.SetToken(h.token)

		bindings, err := client.GetProjectResourceBindings(context.Background(), h.workspaceID, projectID)
		if err != nil {
			t.Fatalf("GetProjectResourceBindings: %v", err)
		}
		if len(bindings) != 2 {
			t.Fatalf("GetProjectResourceBindings returned %d bindings, want 2: %+v", len(bindings), bindings)
		}
		byID := currentBindingByID(t, bindings)
		for _, tc := range []struct {
			resourceID string
			resource   string
		}{
			{localResourceID, "local_directory"},
			{githubResourceID, "github_repo"},
		} {
			binding, ok := byID[tc.resourceID]
			if !ok {
				t.Fatalf("SDK bindings missing %s %s", tc.resource, tc.resourceID)
			}
			assertCurrentBindingScope(t, binding, h.workspaceID, projectID, tc.resourceID, tc.resource)
		}
	})

	t.Run("github_ref_change_and_label_position_stability", func(t *testing.T) {
		project := h.fx.Project(t, "AIFI-45 ref change project")
		projectLocalID := h.insertResource(t, project, "local_directory", localRef, 0)
		projectGitHubID := h.insertResource(t, project, "github_repo", githubRef, 1)

		_, before := h.projectBindings(t, project)
		beforeByID := currentBindingByID(t, before)
		beforeGitHub, ok := beforeByID[projectGitHubID]
		if !ok {
			t.Fatalf("missing github_repo binding %s before ref change", projectGitHubID)
		}
		beforeLocal, ok := beforeByID[projectLocalID]
		if !ok {
			t.Fatalf("missing local_directory binding %s before metadata change", projectLocalID)
		}

		h.replaceResourceRef(t, projectGitHubID, project,
			githubRef, `{"url":"`+repoURL+`","ref":"release/v2","default_branch_hint":"main"}`)
		_, afterRef := h.projectBindings(t, project)
		afterGitHub, ok := currentBindingByID(t, afterRef)[projectGitHubID]
		if !ok {
			t.Fatalf("missing github_repo binding %s after ref change", projectGitHubID)
		}
		if afterGitHub.IdentityB64 == beforeGitHub.IdentityB64 {
			t.Error("github_repo identity did not change after ref change")
		}
		if afterGitHub.BindingDigest == beforeGitHub.BindingDigest {
			t.Error("github_repo digest did not change after ref change")
		}
		if got := currentBindingIdentity(t, afterGitHub)["ref"]; got != "release/v2" {
			t.Errorf("github_repo ref = %q, want release/v2", got)
		}

		h.setLabelAndPosition(t, projectLocalID, project, "relabeled", 99)
		_, afterMeta := h.projectBindings(t, project)
		afterLocal, ok := currentBindingByID(t, afterMeta)[projectLocalID]
		if !ok {
			t.Fatalf("missing local_directory binding %s after metadata change", projectLocalID)
		}
		if afterLocal.BindingDigest != beforeLocal.BindingDigest {
			t.Errorf("label/position changed local_directory digest: before=%s after=%s",
				beforeLocal.BindingDigest, afterLocal.BindingDigest)
		}
		if afterLocal.IdentityB64 != beforeLocal.IdentityB64 {
			t.Error("label/position changed local_directory identity")
		}
	})

	t.Run("reparent_visibility", func(t *testing.T) {
		sourceProject := h.fx.Project(t, "AIFI-45 reparent source")
		destinationProject := h.fx.Project(t, "AIFI-45 reparent destination")
		resourceID := h.insertResource(t, sourceProject, "github_repo", githubRef, 0)

		_, sourceBefore := h.projectBindings(t, sourceProject)
		if _, ok := currentBindingByID(t, sourceBefore)[resourceID]; !ok {
			t.Fatal("source project does not contain its resource before reparent")
		}
		h.moveResource(t, resourceID, sourceProject, destinationProject)

		_, sourceAfter := h.projectBindings(t, sourceProject)
		if _, ok := currentBindingByID(t, sourceAfter)[resourceID]; ok {
			t.Error("source project still contains reparented resource")
		}
		_, destinationAfter := h.projectBindings(t, destinationProject)
		moved, ok := currentBindingByID(t, destinationAfter)[resourceID]
		if !ok {
			t.Fatal("destination project does not contain reparented resource")
		}
		assertCurrentBindingScope(t, moved, h.workspaceID, destinationProject, resourceID, "github_repo")
		assertCurrentBindingIdentity(t, moved, map[string]string{
			"url": repoURL, "ref": "main", "default_branch_hint": "main",
		})
	})

	t.Run("delete_removes_only_owned_resource", func(t *testing.T) {
		project := h.fx.Project(t, "AIFI-45 delete project")
		resourceID := h.insertResource(t, project, "github_repo", githubRef, 0)
		_, before := h.projectBindings(t, project)
		if _, ok := currentBindingByID(t, before)[resourceID]; !ok {
			t.Fatal("project does not contain its resource before delete")
		}
		h.deleteResource(t, resourceID, project)
		_, after := h.projectBindings(t, project)
		if _, ok := currentBindingByID(t, after)[resourceID]; ok {
			t.Error("project still contains deleted resource")
		}
		if len(after) != 0 {
			t.Errorf("deleted project has %d bindings, want 0", len(after))
		}
	})

	t.Run("foreign_workspace_and_forged_headers", func(t *testing.T) {
		otherWorkspaceID := h.fx.Workspace(t, "AIFI-45 other workspace", "aifi45-other-"+uuid.NewString())
		otherProjectID := h.fx.Project(t, "AIFI-45 foreign project", testutil.Cols{"workspace_id": otherWorkspaceID})
		realProjectID := h.fx.Project(t, "AIFI-45 header binding project")
		forged := map[string]string{
			"X-Workspace-ID": otherWorkspaceID,
			"X-Daemon-ID":    "forged-owner",
		}

		foreign := h.get(t, h.projectPath(otherProjectID), h.token, forged)
		if foreign.Code != http.StatusNotFound {
			t.Fatalf("foreign workspace project = %d, want 404: %s", foreign.Code, foreign.Body.String())
		}

		real := h.get(t, h.projectPath(realProjectID), h.token, forged)
		if real.Code != http.StatusOK {
			t.Fatalf("real workspace project with forged headers = %d, want 200: %s", real.Code, real.Body.String())
		}
		var resp currentBindingResponse
		if err := json.Unmarshal(real.Body.Bytes(), &resp); err != nil {
			t.Fatal(err)
		}
		if resp.ProjectID == nil || *resp.ProjectID != realProjectID {
			t.Fatalf("forged headers changed project binding: project_id=%v, want %q", resp.ProjectID, realProjectID)
		}
	})

	t.Run("empty_project_has_explicit_empty_bindings", func(t *testing.T) {
		project := h.fx.Project(t, "AIFI-45 empty project")
		rec, bindings := h.projectBindings(t, project)
		if len(bindings) != 0 {
			t.Fatalf("empty project has %d bindings, want 0", len(bindings))
		}
		var raw map[string]json.RawMessage
		if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
			t.Fatal(err)
		}
		value, present := raw["project_resource_bindings"]
		if !present {
			t.Fatal("empty project response omitted project_resource_bindings")
		}
		if !bytes.Equal(bytes.TrimSpace(value), []byte("[]")) {
			t.Fatalf("empty project bindings = %s, want []", value)
		}
	})

	t.Run("empty_daemon_id_is_forbidden_even_with_owner_header", func(t *testing.T) {
		project := h.fx.Project(t, "AIFI-45 empty daemon project")
		emptyDaemonToken := h.mintDaemonToken(t, "")
		rec := h.get(t, h.projectPath(project), emptyDaemonToken, map[string]string{
			"X-Daemon-ID": "forged-owner",
		})
		if rec.Code != http.StatusForbidden {
			t.Fatalf("empty daemon_id = %d, want 403: %s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "EXECUTION_DAEMON_BINDING_REQUIRED") {
			t.Fatalf("empty daemon_id response = %s, want binding-required error", rec.Body.String())
		}
	})

	t.Run("legacy_no_project_query_has_no_current_fields", func(t *testing.T) {
		rec := h.get(t, "/api/daemon/workspaces/"+h.workspaceID+"/repos", h.token, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("legacy repos read = %d, want 200: %s", rec.Code, rec.Body.String())
		}
		var resp currentBindingResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatal(err)
		}
		if resp.ProjectID != nil {
			t.Errorf("legacy response added project_id=%q", *resp.ProjectID)
		}
		if resp.ProjectResourceBindings != nil {
			t.Errorf("legacy response added project_resource_bindings")
		}
	})

	t.Run("invalid_github_identity_fails_closed_without_secret", func(t *testing.T) {
		project := h.fx.Project(t, "AIFI-45 invalid identity project")
		resourceID := h.insertResource(t, project, "github_repo", githubRef, 0)
		secret := "aifi45-secret-" + uuid.NewString()
		badRef := `{"url":"https://user:` + secret + `@example.test/current-binding.git","ref":"main","default_branch_hint":"main"}`
		h.replaceResourceRef(t, resourceID, project, githubRef, badRef)

		rec := h.getProject(t, project)
		if rec.Code != http.StatusConflict {
			t.Fatalf("invalid github identity = %d, want 409: %s", rec.Code, rec.Body.String())
		}
		if strings.Contains(rec.Body.String(), secret) {
			t.Fatal("409 response echoed the rejected secret")
		}
		if !strings.Contains(rec.Body.String(), "EXECUTION_RESOURCE_BINDINGS_UNAVAILABLE") {
			t.Fatalf("invalid identity response = %s, want bindings-unavailable error", rec.Body.String())
		}
	})
}
