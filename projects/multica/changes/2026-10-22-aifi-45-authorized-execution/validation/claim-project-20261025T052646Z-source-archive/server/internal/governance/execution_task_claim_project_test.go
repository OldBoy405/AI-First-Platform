// AIFIRST: AIFI-45 execution task-claim project binding through the real
// daemon auth and public status handler. This is a current-row snapshot, not a
// claim receipt or permission to consume.
package governance_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/golang-jwt/jwt/v5"
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

type taskClaimHarness struct {
	pool        *pgxpool.Pool
	fx          *testutil.Fixture
	workspaceID string
	daemonID    string
	token       string
	routes      http.Handler
}

type taskClaimFixture struct {
	projectID    string
	issueID      string
	runtimeID    string
	agentID      string
	taskID       string
	status       string
	generation   time.Time
	dispatchedAt string
}

func newTaskClaimHarness(t *testing.T) *taskClaimHarness {
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
	fx.UserID = fx.User(t, "AIFI-45 task claim owner", "aifi45-task-claim-"+uuid.NewString()+"@example.test")
	fx.Member(t, workspaceID, fx.UserID, "owner")

	queries := db.New(pool)
	h := &taskClaimHarness{
		pool:        pool,
		fx:          fx,
		workspaceID: workspaceID,
		daemonID:    "aifi45-claim-daemon-" + uuid.NewString(),
	}
	h.token = h.mintToken(t, h.daemonID)

	hapi := &handler.Handler{Queries: queries, DB: pool, TxStarter: pool}
	routes := chi.NewRouter()
	routes.Route("/api/daemon", func(r chi.Router) {
		r.Use(middleware.DaemonAuth(queries, nil, nil, nil))
		r.Get("/tasks/{taskId}/status", hapi.GetTaskStatus)
	})
	h.routes = routes
	return h
}

func (h *taskClaimHarness) mintToken(t *testing.T, daemonID string) string {
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

func (h *taskClaimHarness) newTask(t *testing.T, workspaceID, daemonID, status string) *taskClaimFixture {
	t.Helper()
	suffix := uuid.NewString()
	projectID := h.fx.Project(t, "AIFI-45 claim project "+suffix, testutil.Cols{"workspace_id": workspaceID})
	issueID := h.fx.Issue(t, "AIFI-45 claim issue "+suffix, testutil.Cols{
		"workspace_id": workspaceID,
		"project_id":   projectID,
	})
	runtimeID := h.fx.Runtime(t, "AIFI-45 claim runtime "+suffix, testutil.Cols{
		"workspace_id": workspaceID,
		"daemon_id":    daemonID,
	})
	agentID := h.fx.Agent(t, "AIFI-45 claim agent "+suffix, runtimeID, testutil.Cols{
		"workspace_id": workspaceID,
	})
	generation := time.Date(2026, 10, 25, 5, 30, 0, 123456000, time.UTC)
	taskID := h.fx.Task(t, agentID, testutil.Cols{
		"issue_id":      issueID,
		"project_id":    projectID,
		"runtime_id":    runtimeID,
		"status":        status,
		"dispatched_at": generation,
	})
	var dispatchedAt string
	if err := h.pool.QueryRow(context.Background(), `
		SELECT to_char(dispatched_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
		FROM agent_task_queue WHERE id=$1::uuid`, taskID).Scan(&dispatchedAt); err != nil {
		t.Fatal(err)
	}
	return &taskClaimFixture{
		projectID: projectID, issueID: issueID, runtimeID: runtimeID,
		agentID: agentID, taskID: taskID, status: status,
		generation: generation, dispatchedAt: dispatchedAt,
	}
}

func (h *taskClaimHarness) claimValues(task *taskClaimFixture) url.Values {
	values := url.Values{}
	values.Set("execution_claim", "1")
	values.Set("runtime_id", task.runtimeID)
	values.Set("dispatched_at", task.dispatchedAt)
	return values
}

func (h *taskClaimHarness) getClaim(t *testing.T, taskID, token string, values url.Values, extraHeaders map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	path := "/api/daemon/tasks/" + taskID + "/status"
	if values != nil {
		path += "?" + values.Encode()
	}
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

func (h *taskClaimHarness) sessionJWT(t *testing.T) string {
	t.Helper()
	claims := jwt.MapClaims{
		"sub":   h.fx.UserID,
		"email": "aifi45-claim-" + uuid.NewString() + "@example.test",
		"exp":   time.Now().Add(time.Hour).Unix(),
		"iat":   time.Now().Add(-time.Minute).Unix(),
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(auth.JWTSecret())
	if err != nil {
		t.Fatal(err)
	}
	return signed
}

func (h *taskClaimHarness) execOne(t *testing.T, query string, args ...any) {
	t.Helper()
	tag, err := h.pool.Exec(context.Background(), query, args...)
	if err != nil {
		t.Fatalf("fixture mutation: %v", err)
	}
	if tag.RowsAffected() != 1 {
		t.Fatalf("fixture mutation affected %d rows, want 1", tag.RowsAffected())
	}
}

func (h *taskClaimHarness) execCleanup(t *testing.T, query string, args ...any) {
	if _, err := h.pool.Exec(context.Background(), query, args...); err != nil {
		t.Errorf("fixture restore: %v", err)
	}
}

func assertExecutionTaskClaim(t *testing.T, rec *httptest.ResponseRecorder, task *taskClaimFixture, workspaceID, daemonID string) {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("GET execution task claim = %d, want 200: %s", rec.Code, rec.Body.String())
	}
	var got map[string]json.RawMessage
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode task claim response: %v", err)
	}
	want := map[string]string{
		"schema":        "execution-task-claim/v1",
		"workspace_id":  workspaceID,
		"project_id":    task.projectID,
		"daemon_id":     daemonID,
		"runtime_id":    task.runtimeID,
		"task_id":       task.taskID,
		"dispatched_at": task.dispatchedAt,
		"status":        task.status,
	}
	if len(got) != len(want) {
		t.Fatalf("task claim response has %d fields %v, want exactly %d fields %v",
			len(got), got, len(want), want)
	}
	for field, wantValue := range want {
		raw, present := got[field]
		if !present {
			t.Fatalf("task claim response missing %q: %s", field, rec.Body.String())
		}
		var value string
		if err := json.Unmarshal(raw, &value); err != nil {
			t.Fatalf("task claim field %q is not a string: %v", field, err)
		}
		if value != wantValue {
			t.Errorf("task claim %s = %q, want %q", field, value, wantValue)
		}
	}
}

func assertTaskClaimError(t *testing.T, rec *httptest.ResponseRecorder, wantStatus int, wantCode string) {
	t.Helper()
	if rec.Code != wantStatus {
		t.Fatalf("execution task claim = %d, want %d: %s", rec.Code, wantStatus, rec.Body.String())
	}
	if wantCode == "" {
		return
	}
	var resp struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode task claim error: %v", err)
	}
	if resp.Error != wantCode {
		t.Fatalf("task claim error = %q, want %q", resp.Error, wantCode)
	}
}

func assertLegacyTaskStatus(t *testing.T, rec *httptest.ResponseRecorder, wantStatus string) {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("legacy task status = %d, want 200: %s", rec.Code, rec.Body.String())
	}
	var got map[string]json.RawMessage
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode legacy task status: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("legacy task status has %d fields %v, want exactly status: %s", len(got), got, rec.Body.String())
	}
	raw, present := got["status"]
	if !present {
		t.Fatalf("legacy task status missing status: %s", rec.Body.String())
	}
	var status string
	if err := json.Unmarshal(raw, &status); err != nil {
		t.Fatalf("legacy status is not a string: %v", err)
	}
	if status != wantStatus {
		t.Errorf("legacy status = %q, want %q", status, wantStatus)
	}
}

func TestExecutionTaskClaimProject(t *testing.T) {
	h := newTaskClaimHarness(t)

	t.Run("dispatched_claim", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		rec := h.getClaim(t, task.taskID, h.token, h.claimValues(task), nil)
		assertExecutionTaskClaim(t, rec, task, h.workspaceID, h.daemonID)
	})

	t.Run("live_issue_moved_to_other_project", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		otherProject := h.fx.Project(t, "AIFI-45 moved issue project "+uuid.NewString(), testutil.Cols{
			"workspace_id": h.workspaceID,
		})
		h.execOne(t, `UPDATE issue SET project_id=$1::uuid WHERE id=$2::uuid`, otherProject, task.issueID)
		t.Cleanup(func() {
			h.execCleanup(t, `UPDATE issue SET project_id=$1::uuid WHERE id=$2::uuid`, task.projectID, task.issueID)
		})
		rec := h.getClaim(t, task.taskID, h.token, h.claimValues(task), nil)
		assertTaskClaimError(t, rec, http.StatusConflict, "EXECUTION_TASK_CLAIM_UNAVAILABLE")
	})

	t.Run("frozen_project_null", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		h.execOne(t, `UPDATE agent_task_queue SET project_id=NULL WHERE id=$1::uuid`, task.taskID)
		t.Cleanup(func() {
			h.execCleanup(t, `UPDATE agent_task_queue SET project_id=$1::uuid WHERE id=$2::uuid`, task.projectID, task.taskID)
		})
		rec := h.getClaim(t, task.taskID, h.token, h.claimValues(task), nil)
		assertTaskClaimError(t, rec, http.StatusConflict, "EXECUTION_TASK_CLAIM_UNAVAILABLE")
	})

	t.Run("task_project_outside_tenant", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		otherWorkspace := h.fx.Workspace(t, "AIFI-45 other tenant "+uuid.NewString(), "aifi45-other-"+uuid.NewString())
		foreignProject := h.fx.Project(t, "AIFI-45 foreign project "+uuid.NewString(), testutil.Cols{
			"workspace_id": otherWorkspace,
		})
		h.execOne(t, `UPDATE agent_task_queue SET project_id=$1::uuid WHERE id=$2::uuid`, foreignProject, task.taskID)
		h.execOne(t, `UPDATE issue SET project_id=$1::uuid WHERE id=$2::uuid`, foreignProject, task.issueID)
		t.Cleanup(func() {
			h.execCleanup(t, `UPDATE agent_task_queue SET project_id=$1::uuid WHERE id=$2::uuid`, task.projectID, task.taskID)
			h.execCleanup(t, `UPDATE issue SET project_id=$1::uuid WHERE id=$2::uuid`, task.projectID, task.issueID)
		})
		rec := h.getClaim(t, task.taskID, h.token, h.claimValues(task), nil)
		assertTaskClaimError(t, rec, http.StatusConflict, "EXECUTION_TASK_CLAIM_UNAVAILABLE")
	})

	t.Run("runtime_changed_daemon", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		otherDaemon := "aifi45-other-daemon-" + uuid.NewString()
		h.execOne(t, `UPDATE agent_runtime SET daemon_id=$1 WHERE id=$2::uuid`, otherDaemon, task.runtimeID)
		t.Cleanup(func() {
			h.execCleanup(t, `UPDATE agent_runtime SET daemon_id=$1 WHERE id=$2::uuid`, h.daemonID, task.runtimeID)
		})
		rec := h.getClaim(t, task.taskID, h.token, h.claimValues(task), nil)
		assertTaskClaimError(t, rec, http.StatusConflict, "EXECUTION_TASK_CLAIM_UNAVAILABLE")
	})

	t.Run("wrong_generation", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		values := h.claimValues(task)
		values.Set("dispatched_at", task.generation.Add(time.Microsecond).Format(time.RFC3339Nano))
		rec := h.getClaim(t, task.taskID, h.token, values, nil)
		assertTaskClaimError(t, rec, http.StatusConflict, "EXECUTION_TASK_CLAIM_UNAVAILABLE")
	})

	t.Run("terminal_task", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "completed")
		rec := h.getClaim(t, task.taskID, h.token, h.claimValues(task), nil)
		assertTaskClaimError(t, rec, http.StatusConflict, "EXECUTION_TASK_CLAIM_UNAVAILABLE")
	})

	t.Run("cross_workspace_task_is_not_found", func(t *testing.T) {
		otherWorkspace := h.fx.Workspace(t, "AIFI-45 cross workspace "+uuid.NewString(), "aifi45-cross-"+uuid.NewString())
		otherDaemon := "aifi45-cross-daemon-" + uuid.NewString()
		task := h.newTask(t, otherWorkspace, otherDaemon, "dispatched")
		rec := h.getClaim(t, task.taskID, h.token, h.claimValues(task), map[string]string{
			"X-Workspace-ID": otherWorkspace,
		})
		assertTaskClaimError(t, rec, http.StatusNotFound, "task not found")
	})

	t.Run("no_mdt_is_forbidden", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		rec := h.getClaim(t, task.taskID, h.sessionJWT(t), h.claimValues(task), nil)
		assertTaskClaimError(t, rec, http.StatusForbidden, "EXECUTION_DAEMON_BINDING_REQUIRED")
	})

	t.Run("empty_daemon_id_is_forbidden", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		emptyDaemonToken := h.mintToken(t, "")
		rec := h.getClaim(t, task.taskID, emptyDaemonToken, h.claimValues(task), nil)
		assertTaskClaimError(t, rec, http.StatusForbidden, "EXECUTION_DAEMON_BINDING_REQUIRED")
	})

	t.Run("legacy_no_query_has_single_status_field", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		rec := h.getClaim(t, task.taskID, h.token, nil, nil)
		assertLegacyTaskStatus(t, rec, task.status)
	})

	t.Run("duplicate_execution_claim_is_bad_request", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		values := h.claimValues(task)
		values.Add("execution_claim", "1")
		rec := h.getClaim(t, task.taskID, h.token, values, nil)
		assertTaskClaimError(t, rec, http.StatusBadRequest, "")
	})

	t.Run("missing_runtime_id_is_bad_request", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		values := h.claimValues(task)
		values.Del("runtime_id")
		rec := h.getClaim(t, task.taskID, h.token, values, nil)
		assertTaskClaimError(t, rec, http.StatusBadRequest, "")
	})

	t.Run("submicrosecond_generation_is_bad_request", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		values := h.claimValues(task)
		values.Set("dispatched_at", task.generation.Add(789*time.Nanosecond).Format(time.RFC3339Nano))
		rec := h.getClaim(t, task.taskID, h.token, values, nil)
		assertTaskClaimError(t, rec, http.StatusBadRequest, "")
	})

	for _, status := range []string{"waiting_local_directory", "running"} {
		status := status
		t.Run("active_status_"+status, func(t *testing.T) {
			task := h.newTask(t, h.workspaceID, h.daemonID, status)
			rec := h.getClaim(t, task.taskID, h.token, h.claimValues(task), nil)
			assertExecutionTaskClaim(t, rec, task, h.workspaceID, h.daemonID)
		})
	}

	t.Run("sdk_dispatched_claim", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		server := httptest.NewServer(h.routes)
		defer server.Close()
		client := daemon.NewClient(server.URL)
		client.SetToken(h.token)

		claim, err := client.GetTaskExecutionClaim(context.Background(), h.workspaceID, task.projectID, task.taskID, task.runtimeID, task.dispatchedAt)
		if err != nil {
			t.Fatalf("GetTaskExecutionClaim: %v", err)
		}
		want := protocol.ExecutionTaskClaim{
			Schema:       "execution-task-claim/v1",
			WorkspaceID:  h.workspaceID,
			ProjectID:    task.projectID,
			DaemonID:     h.daemonID,
			RuntimeID:    task.runtimeID,
			TaskID:       task.taskID,
			DispatchedAt: task.dispatchedAt,
			Status:       task.status,
		}
		if claim != want {
			t.Fatalf("SDK execution task claim = %+v, want %+v", claim, want)
		}
	})

	t.Run("sdk_live_issue_drift_rejected", func(t *testing.T) {
		task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
		otherProject := h.fx.Project(t, "AIFI-45 SDK moved issue project "+uuid.NewString(), testutil.Cols{
			"workspace_id": h.workspaceID,
		})
		h.execOne(t, `UPDATE issue SET project_id=$1::uuid WHERE id=$2::uuid`, otherProject, task.issueID)
		t.Cleanup(func() {
			h.execCleanup(t, `UPDATE issue SET project_id=$1::uuid WHERE id=$2::uuid`, task.projectID, task.issueID)
		})
		server := httptest.NewServer(h.routes)
		defer server.Close()
		client := daemon.NewClient(server.URL)
		client.SetToken(h.token)

		if _, err := client.GetTaskExecutionClaim(context.Background(), h.workspaceID, task.projectID, task.taskID, task.runtimeID, task.dispatchedAt); err == nil {
			t.Fatal("SDK accepted live issue drift")
		}
	})
}

// TestExecutionTaskClaimProjectRejectsTruncatedGeneration isolates the parser
// precision negative: extra sub-microsecond input digits must not be silently
// truncated into the frozen DB generation. It asserts only input rejection, not
// cross-microsecond equality or any authorization behavior.
func TestExecutionTaskClaimProjectRejectsTruncatedGeneration(t *testing.T) {
	h := newTaskClaimHarness(t)
	task := h.newTask(t, h.workspaceID, h.daemonID, "dispatched")
	values := h.claimValues(task)
	values.Set("dispatched_at", task.dispatchedAt[:len(task.dispatchedAt)-1]+"0001Z")
	rec := h.getClaim(t, task.taskID, h.token, values, nil)
	assertTaskClaimError(t, rec, http.StatusBadRequest, "")
}

// TestExecutionTaskClaimProjectRejectsControlDaemon isolates the wire-identity
// negative: a daemon token and its runtime may carry the same non-NUL C0 or C1
// control character internally, and the current claim must not succeed.
func TestExecutionTaskClaimProjectRejectsControlDaemon(t *testing.T) {
	h := newTaskClaimHarness(t)
	for _, tc := range []struct {
		name    string
		control string
	}{
		{name: "c0", control: "\u0001"},
		{name: "c1", control: "\u0081"},
	} {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			daemonID := "aifi45-control-" + tc.control + "-daemon"
			token := h.mintToken(t, daemonID)
			task := h.newTask(t, h.workspaceID, daemonID, "dispatched")
			rec := h.getClaim(t, task.taskID, token, h.claimValues(task), nil)
			if rec.Code == http.StatusOK {
				t.Fatalf("control daemon identity was accepted: %s", rec.Body.String())
			}
			if rec.Code != http.StatusForbidden && rec.Code != http.StatusConflict {
				t.Fatalf("control daemon identity = %d, want fail-closed 403 or 409: %s", rec.Code, rec.Body.String())
			}
		})
	}
}
