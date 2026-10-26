package handler

import (
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/multica-ai/multica/server/internal/middleware"
	db "github.com/multica-ai/multica/server/pkg/db/generated"
	"github.com/multica-ai/multica/server/pkg/protocol"
)

// getTaskExecutionClaim serves only the explicit read mode of the status API.
// The frozen queue project and live issue must agree; a response is not a lease.
func (h *Handler) getTaskExecutionClaim(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	daemonID := middleware.DaemonIDFromContext(r.Context())
	workspace := middleware.DaemonWorkspaceIDFromContext(r.Context())
	if middleware.DaemonAuthPathFromContext(r.Context()) != middleware.DaemonAuthPathDaemonToken ||
		strings.TrimSpace(daemonID) == "" || strings.IndexFunc(daemonID, unicode.IsControl) >= 0 || workspace == "" {
		writeError(w, http.StatusForbidden, "EXECUTION_DAEMON_BINDING_REQUIRED")
		return
	}
	query := r.URL.Query()
	if len(query["execution_claim"]) != 1 || query.Get("execution_claim") != "1" ||
		len(query["runtime_id"]) != 1 || len(query["dispatched_at"]) != 1 {
		writeError(w, http.StatusBadRequest, "execution_claim, runtime_id and dispatched_at must occur once")
		return
	}
	taskID, ok := parseUUIDOrBadRequest(w, chi.URLParam(r, "taskId"), "task_id")
	if !ok {
		return
	}
	runtimeID, ok := parseUUIDOrBadRequest(w, query.Get("runtime_id"), "runtime_id")
	if !ok {
		return
	}
	if uuidToString(taskID) != chi.URLParam(r, "taskId") || uuidToString(runtimeID) != query.Get("runtime_id") {
		writeError(w, http.StatusBadRequest, "task_id and runtime_id must be canonical UUIDs")
		return
	}
	generation, err := protocol.ParseExecutionClaimTime(query.Get("dispatched_at"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "dispatched_at must be a PostgreSQL claim timestamp")
		return
	}
	workspaceID, ok := parseUUIDOrBadRequest(w, workspace, "workspace_id")
	if !ok {
		return
	}
	unavailable := func(err error) {
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusInternalServerError, "failed to load execution task claim")
			return
		}
		writeError(w, http.StatusConflict, "EXECUTION_TASK_CLAIM_UNAVAILABLE")
	}
	tx, err := h.TxStarter.Begin(r.Context())
	if err != nil {
		unavailable(err)
		return
	}
	defer tx.Rollback(r.Context())
	if _, err := tx.Exec(r.Context(), "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY"); err != nil {
		unavailable(err)
		return
	}
	q := h.Queries.WithTx(tx)
	task, err := q.GetAgentTaskInWorkspace(r.Context(), db.GetAgentTaskInWorkspaceParams{ID: taskID, WorkspaceID: workspaceID})
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "task not found")
		return
	}
	if err != nil {
		unavailable(err)
		return
	}
	if task.RuntimeID != runtimeID || !task.DispatchedAt.Valid || !task.DispatchedAt.Time.Equal(generation) ||
		!task.ProjectID.Valid || !task.IssueID.Valid ||
		(task.Status != "dispatched" && task.Status != "waiting_local_directory" && task.Status != "running") {
		unavailable(nil)
		return
	}
	runtime, err := q.GetAgentRuntime(r.Context(), runtimeID)
	if err != nil {
		unavailable(err)
		return
	}
	if runtime.WorkspaceID != workspaceID || !runtime.DaemonID.Valid || runtime.DaemonID.String != daemonID {
		unavailable(nil)
		return
	}
	issue, err := q.GetIssueInWorkspace(r.Context(), db.GetIssueInWorkspaceParams{ID: task.IssueID, WorkspaceID: workspaceID})
	if err != nil {
		unavailable(err)
		return
	}
	if issue.ProjectID != task.ProjectID {
		unavailable(nil)
		return
	}
	if _, err := q.GetProjectInWorkspace(r.Context(), db.GetProjectInWorkspaceParams{ID: task.ProjectID, WorkspaceID: workspaceID}); err != nil {
		unavailable(err)
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		unavailable(err)
		return
	}
	writeJSON(w, http.StatusOK, protocol.ExecutionTaskClaim{
		Schema: "execution-task-claim/v1", WorkspaceID: uuidToString(workspaceID),
		ProjectID: uuidToString(task.ProjectID), DaemonID: daemonID,
		RuntimeID: uuidToString(runtimeID), TaskID: uuidToString(task.ID),
		DispatchedAt: task.DispatchedAt.Time.UTC().Format(time.RFC3339Nano), Status: task.Status,
	})
}
