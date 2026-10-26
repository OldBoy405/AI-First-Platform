package daemon

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/multica-ai/multica/server/pkg/protocol"
)

func TestExecutionTaskClaimClient(t *testing.T) {
	const (
		workspaceID  = "01234567-89ab-4cde-8f01-23456789abcd"
		projectID    = "fedcba98-7654-4321-8abc-def012345678"
		taskID       = "a1b2c3d4-e5f6-4789-8abc-def012345678"
		runtimeID    = "b2c3d4e5-f6a7-4890-9bcd-ef0123456789"
		daemonID     = "daemon-opaque-literal-01"
		dispatchedAt = "2026-10-25T03:48:07.123456Z"
		token        = "mdt_literal_test_only"
	)

	want := protocol.ExecutionTaskClaim{
		Schema:       "execution-task-claim/v1",
		WorkspaceID:  workspaceID,
		ProjectID:    projectID,
		DaemonID:     daemonID,
		RuntimeID:    runtimeID,
		TaskID:       taskID,
		DispatchedAt: dispatchedAt,
		Status:       "dispatched",
	}
	responseBody := `{"schema":"execution-task-claim/v1","workspace_id":"` + workspaceID +
		`","project_id":"` + projectID +
		`","daemon_id":"` + daemonID +
		`","runtime_id":"` + runtimeID +
		`","task_id":"` + taskID +
		`","dispatched_at":"` + dispatchedAt +
		`","status":"dispatched"}`

	var requestCount int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&requestCount, 1)
		if r.Method != http.MethodGet {
			t.Errorf("method = %q, want GET", r.Method)
		}
		wantPath := "/api/daemon/tasks/" + taskID + "/status"
		if r.URL.Path != wantPath {
			t.Errorf("path = %q, want %q", r.URL.Path, wantPath)
		}
		query := r.URL.Query()
		if len(query) != 3 {
			t.Errorf("query keys = %v, want exactly execution_claim, runtime_id, dispatched_at", query)
		}
		wantQuery := map[string]string{
			"execution_claim": "1",
			"runtime_id":      runtimeID,
			"dispatched_at":   dispatchedAt,
		}
		for key, wantValue := range wantQuery {
			values, ok := query[key]
			if !ok || len(values) != 1 || values[0] != wantValue {
				t.Errorf("query[%q] = %v, want exactly [%q]", key, values, wantValue)
			}
		}
		if r.Header.Get("Authorization") != "Bearer "+token {
			t.Error("Authorization header is not the literal test bearer")
		}
		w.Header().Set("Content-Type", "application/json")
		if _, err := w.Write([]byte(responseBody)); err != nil {
			t.Errorf("write response: %v", err)
		}
	}))
	t.Cleanup(srv.Close)

	client := NewClient(srv.URL)
	client.SetToken(token)
	got, err := client.GetTaskExecutionClaim(context.Background(), workspaceID, projectID, taskID, runtimeID, dispatchedAt)
	if err != nil {
		t.Fatalf("GetTaskExecutionClaim: %v", err)
	}
	if got != want {
		t.Fatalf("claim = %#v, want %#v", got, want)
	}
	if hits := atomic.LoadInt32(&requestCount); hits != 1 {
		t.Fatalf("request count = %d, want 1", hits)
	}
}

const (
	executionTaskClaimMatrixWorkspaceID  = "01234567-89ab-4cde-8f01-23456789abcd"
	executionTaskClaimMatrixProjectID    = "fedcba98-7654-4321-8abc-def012345678"
	executionTaskClaimMatrixTaskID       = "a1b2c3d4-e5f6-4789-8abc-def012345678"
	executionTaskClaimMatrixRuntimeID    = "b2c3d4e5-f6a7-4890-9bcd-ef0123456789"
	executionTaskClaimMatrixOtherWSID    = "11234567-89ab-4cde-8f01-23456789abcd"
	executionTaskClaimMatrixOtherProject = "fedcba98-7654-4321-8abc-def012345679"
	executionTaskClaimMatrixOtherTask    = "a1b2c3d4-e5f6-4789-8abc-def012345679"
	executionTaskClaimMatrixOtherRuntime = "b2c3d4e5-f6a7-4890-9bcd-ef012345678a"
	executionTaskClaimMatrixDaemonID     = "daemon-opaque-literal-01"
	executionTaskClaimMatrixDispatchedAt = "2026-10-25T03:48:07.123456Z"
	executionTaskClaimMatrixWrongTime    = "2026-10-25T03:48:08.123456Z"
	executionTaskClaimMatrixNanoTime     = "2026-10-25T03:48:07.1234567Z"
	executionTaskClaimMatrixToken        = "mdt_literal_test_only"
)

func executionTaskClaimMatrixBody(t *testing.T, mutate func(map[string]any)) string {
	t.Helper()
	fields := map[string]any{
		"schema":        "execution-task-claim/v1",
		"workspace_id":  executionTaskClaimMatrixWorkspaceID,
		"project_id":    executionTaskClaimMatrixProjectID,
		"daemon_id":     executionTaskClaimMatrixDaemonID,
		"runtime_id":    executionTaskClaimMatrixRuntimeID,
		"task_id":       executionTaskClaimMatrixTaskID,
		"dispatched_at": executionTaskClaimMatrixDispatchedAt,
		"status":        "dispatched",
	}
	if mutate != nil {
		mutate(fields)
	}
	raw, err := json.Marshal(fields)
	if err != nil {
		t.Fatalf("marshal claim response: %v", err)
	}
	return string(raw)
}

func executionTaskClaimMatrixAppend(t *testing.T, body, key string, value any) string {
	t.Helper()
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("marshal appended field: %v", err)
	}
	if !strings.HasSuffix(body, "}") {
		t.Fatalf("claim response does not end with an object")
	}
	return strings.TrimSuffix(body, "}") + `,"` + key + `":` + string(raw) + `}`
}

func executionTaskClaimMatrixServer(t *testing.T, status int, body string) (*httptest.Server, *int32) {
	t.Helper()
	var hits int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&hits, 1)
		if r.Method != http.MethodGet {
			t.Errorf("method = %q, want GET", r.Method)
		}
		wantPath := "/api/daemon/tasks/" + executionTaskClaimMatrixTaskID + "/status"
		if r.URL.Path != wantPath {
			t.Errorf("path = %q, want %q", r.URL.Path, wantPath)
		}
		query := r.URL.Query()
		if len(query) != 3 {
			t.Errorf("query keys = %v, want exactly execution_claim, runtime_id, dispatched_at", query)
		}
		wantQuery := map[string]string{
			"execution_claim": "1",
			"runtime_id":      executionTaskClaimMatrixRuntimeID,
			"dispatched_at":   executionTaskClaimMatrixDispatchedAt,
		}
		for key, wantValue := range wantQuery {
			values, ok := query[key]
			if !ok || len(values) != 1 || values[0] != wantValue {
				t.Errorf("query[%q] = %v, want exactly [%q]", key, values, wantValue)
			}
		}
		if r.Header.Get("Authorization") != "Bearer "+executionTaskClaimMatrixToken {
			t.Error("Authorization header is not the literal test bearer")
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)
	return srv, &hits
}

func executionTaskClaimMatrixClient(baseURL string) *Client {
	client := NewClient(baseURL)
	client.SetToken(executionTaskClaimMatrixToken)
	return client
}

func TestExecutionTaskClaimClientMatrix(t *testing.T) {
	ctx := context.Background()

	for _, status := range []string{"waiting_local_directory", "running"} {
		status := status
		t.Run("positive "+status, func(t *testing.T) {
			body := executionTaskClaimMatrixBody(t, func(fields map[string]any) {
				fields["status"] = status
			})
			srv, hits := executionTaskClaimMatrixServer(t, http.StatusOK, body)
			got, err := executionTaskClaimMatrixClient(srv.URL).GetTaskExecutionClaim(ctx,
				executionTaskClaimMatrixWorkspaceID,
				executionTaskClaimMatrixProjectID,
				executionTaskClaimMatrixTaskID,
				executionTaskClaimMatrixRuntimeID,
				executionTaskClaimMatrixDispatchedAt,
			)
			if err != nil {
				t.Fatalf("GetTaskExecutionClaim(%s): %v", status, err)
			}
			want := protocol.ExecutionTaskClaim{
				Schema:       "execution-task-claim/v1",
				WorkspaceID:  executionTaskClaimMatrixWorkspaceID,
				ProjectID:    executionTaskClaimMatrixProjectID,
				DaemonID:     executionTaskClaimMatrixDaemonID,
				RuntimeID:    executionTaskClaimMatrixRuntimeID,
				TaskID:       executionTaskClaimMatrixTaskID,
				DispatchedAt: executionTaskClaimMatrixDispatchedAt,
				Status:       status,
			}
			if got != want {
				t.Fatalf("claim = %#v, want %#v", got, want)
			}
			if got := atomic.LoadInt32(hits); got != 1 {
				t.Fatalf("server hits = %d, want 1", got)
			}
		})
	}

	validBody := executionTaskClaimMatrixBody(t, nil)
	duplicateBody := executionTaskClaimMatrixAppend(t, executionTaskClaimMatrixBody(t, nil), "project_id", executionTaskClaimMatrixProjectID)
	trailingBody := executionTaskClaimMatrixBody(t, nil) + `{"second":true}`
	aliasBody := executionTaskClaimMatrixAppend(t,
		executionTaskClaimMatrixBody(t, func(fields map[string]any) {
			fields["workspace_id"] = executionTaskClaimMatrixOtherWSID
		}),
		"WORKSPACE_ID", executionTaskClaimMatrixWorkspaceID,
	)
	oversizeBody := executionTaskClaimMatrixBody(t, nil) + strings.Repeat(" ", (1<<20)+1)

	negativeCases := []struct {
		name string
		body string
	}{
		{"old status-only missing schema", `{"status":"dispatched"}`},
		{"wrong schema", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["schema"] = "execution-task-claim/v2" })},
		{"wrong workspace", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["workspace_id"] = executionTaskClaimMatrixOtherWSID })},
		{"wrong project", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["project_id"] = executionTaskClaimMatrixOtherProject })},
		{"wrong task", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["task_id"] = executionTaskClaimMatrixOtherTask })},
		{"wrong runtime", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["runtime_id"] = executionTaskClaimMatrixOtherRuntime })},
		{"wrong generation", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["dispatched_at"] = executionTaskClaimMatrixWrongTime })},
		{"nanosecond precision", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["dispatched_at"] = executionTaskClaimMatrixNanoTime })},
		{"terminal completed", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["status"] = "completed" })},
		{"terminal failed", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["status"] = "failed" })},
		{"terminal cancelled", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["status"] = "cancelled" })},
		{"empty daemon", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["daemon_id"] = "" })},
		{"daemon c0 control", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["daemon_id"] = "\x00" })},
		{"daemon c1 control", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["daemon_id"] = "\u0080" })},
		{"missing project_id", executionTaskClaimMatrixBody(t, func(fields map[string]any) { delete(fields, "project_id") })},
		{"null project_id", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["project_id"] = nil })},
		{"null daemon_id", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["daemon_id"] = nil })},
		{"missing dispatched_at", executionTaskClaimMatrixBody(t, func(fields map[string]any) { delete(fields, "dispatched_at") })},
		{"null dispatched_at", executionTaskClaimMatrixBody(t, func(fields map[string]any) { fields["dispatched_at"] = nil })},
		{"duplicate project_id key", duplicateBody},
		{"trailing second json document", trailingBody},
		{"case-folded alias override", aliasBody},
		{"oversize metadata body", oversizeBody},
	}

	for _, tc := range negativeCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			srv, hits := executionTaskClaimMatrixServer(t, http.StatusOK, tc.body)
			_, err := executionTaskClaimMatrixClient(srv.URL).GetTaskExecutionClaim(ctx,
				executionTaskClaimMatrixWorkspaceID,
				executionTaskClaimMatrixProjectID,
				executionTaskClaimMatrixTaskID,
				executionTaskClaimMatrixRuntimeID,
				executionTaskClaimMatrixDispatchedAt,
			)
			if err == nil {
				t.Fatal("GetTaskExecutionClaim succeeded, want error")
			}
			if got := atomic.LoadInt32(hits); got != 1 {
				t.Fatalf("server hits = %d, want 1", got)
			}
		})
	}

	badInputs := []struct {
		name         string
		workspaceID  string
		projectID    string
		taskID       string
		runtimeID    string
		dispatchedAt string
	}{
		{"empty workspace", "", executionTaskClaimMatrixProjectID, executionTaskClaimMatrixTaskID, executionTaskClaimMatrixRuntimeID, executionTaskClaimMatrixDispatchedAt},
		{"noncanonical workspace", strings.ToUpper(executionTaskClaimMatrixWorkspaceID), executionTaskClaimMatrixProjectID, executionTaskClaimMatrixTaskID, executionTaskClaimMatrixRuntimeID, executionTaskClaimMatrixDispatchedAt},
		{"malformed project", executionTaskClaimMatrixWorkspaceID, "not-a-uuid", executionTaskClaimMatrixTaskID, executionTaskClaimMatrixRuntimeID, executionTaskClaimMatrixDispatchedAt},
		{"noncanonical task", executionTaskClaimMatrixWorkspaceID, executionTaskClaimMatrixProjectID, strings.ReplaceAll(executionTaskClaimMatrixTaskID, "-", ""), executionTaskClaimMatrixRuntimeID, executionTaskClaimMatrixDispatchedAt},
		{"malformed runtime", executionTaskClaimMatrixWorkspaceID, executionTaskClaimMatrixProjectID, executionTaskClaimMatrixTaskID, "runtime-not-a-uuid", executionTaskClaimMatrixDispatchedAt},
		{"bad timestamp", executionTaskClaimMatrixWorkspaceID, executionTaskClaimMatrixProjectID, executionTaskClaimMatrixTaskID, executionTaskClaimMatrixRuntimeID, "not-a-timestamp"},
		{"nanosecond input timestamp", executionTaskClaimMatrixWorkspaceID, executionTaskClaimMatrixProjectID, executionTaskClaimMatrixTaskID, executionTaskClaimMatrixRuntimeID, executionTaskClaimMatrixNanoTime},
		{"truncated tenth fractional digit", executionTaskClaimMatrixWorkspaceID, executionTaskClaimMatrixProjectID, executionTaskClaimMatrixTaskID, executionTaskClaimMatrixRuntimeID, strings.TrimSuffix(executionTaskClaimMatrixDispatchedAt, "Z") + "0001Z"},
	}

	for _, tc := range badInputs {
		tc := tc
		t.Run("input rejected before server: "+tc.name, func(t *testing.T) {
			srv, hits := executionTaskClaimMatrixServer(t, http.StatusOK, validBody)
			_, err := executionTaskClaimMatrixClient(srv.URL).GetTaskExecutionClaim(ctx, tc.workspaceID, tc.projectID, tc.taskID, tc.runtimeID, tc.dispatchedAt)
			if err == nil {
				t.Fatal("GetTaskExecutionClaim succeeded on invalid input, want error")
			}
			if got := atomic.LoadInt32(hits); got != 0 {
				t.Fatalf("server hits = %d, want 0", got)
			}
		})
	}

	t.Run("non-200 response does not echo body", func(t *testing.T) {
		const sentinel = "LEAK_SENTINEL"
		srv, hits := executionTaskClaimMatrixServer(t, http.StatusServiceUnavailable, sentinel)
		_, err := executionTaskClaimMatrixClient(srv.URL).GetTaskExecutionClaim(ctx,
			executionTaskClaimMatrixWorkspaceID,
			executionTaskClaimMatrixProjectID,
			executionTaskClaimMatrixTaskID,
			executionTaskClaimMatrixRuntimeID,
			executionTaskClaimMatrixDispatchedAt,
		)
		if err == nil {
			t.Fatal("GetTaskExecutionClaim succeeded on 503, want error")
		}
		if strings.Contains(err.Error(), sentinel) {
			t.Fatal("error echoed the untrusted response body")
		}
		if got := atomic.LoadInt32(hits); got != 1 {
			t.Fatalf("server hits = %d, want 1", got)
		}
	})

	t.Run("disconnected server", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
		baseURL := srv.URL
		srv.Close()

		_, err := executionTaskClaimMatrixClient(baseURL).GetTaskExecutionClaim(ctx,
			executionTaskClaimMatrixWorkspaceID,
			executionTaskClaimMatrixProjectID,
			executionTaskClaimMatrixTaskID,
			executionTaskClaimMatrixRuntimeID,
			executionTaskClaimMatrixDispatchedAt,
		)
		if err == nil {
			t.Fatal("GetTaskExecutionClaim succeeded against disconnected server, want error")
		}
	})

	t.Run("redirect target receives no request", func(t *testing.T) {
		var targetHits int32
		target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			atomic.AddInt32(&targetHits, 1)
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(validBody))
		}))
		t.Cleanup(target.Close)

		var entryHits int32
		entry := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			atomic.AddInt32(&entryHits, 1)
			http.Redirect(w, r, target.URL, http.StatusFound)
		}))
		t.Cleanup(entry.Close)

		_, err := executionTaskClaimMatrixClient(entry.URL).GetTaskExecutionClaim(ctx,
			executionTaskClaimMatrixWorkspaceID,
			executionTaskClaimMatrixProjectID,
			executionTaskClaimMatrixTaskID,
			executionTaskClaimMatrixRuntimeID,
			executionTaskClaimMatrixDispatchedAt,
		)
		if err == nil {
			t.Fatal("GetTaskExecutionClaim succeeded through redirect, want error")
		}
		if got := atomic.LoadInt32(&targetHits); got != 0 {
			t.Fatalf("redirect target hits = %d, want 0", got)
		}
		if got := atomic.LoadInt32(&entryHits); got != 1 {
			t.Fatalf("entry hits = %d, want 1", got)
		}
	})
}
