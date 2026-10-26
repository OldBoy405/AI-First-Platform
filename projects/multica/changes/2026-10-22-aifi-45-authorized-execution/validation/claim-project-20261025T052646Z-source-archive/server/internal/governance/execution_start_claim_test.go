// AIFIRST: AIFI-45 authenticated task-claim ownership. A valid daemon token
// proves only its DB identity, not isolation, admission, or permission to consume.
package governance_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/multica-ai/multica/server/internal/auth"
	"github.com/multica-ai/multica/server/internal/events"
	"github.com/multica-ai/multica/server/internal/governance"
	"github.com/multica-ai/multica/server/internal/handler"
	"github.com/multica-ai/multica/server/internal/middleware"
	"github.com/multica-ai/multica/server/internal/realtime"
	"github.com/multica-ai/multica/server/internal/service"
	"github.com/multica-ai/multica/server/internal/testutil"
	db "github.com/multica-ai/multica/server/pkg/db/generated"
)

func TestExecutionStartClaimDaemonOwnership(t *testing.T) {
	ctx := context.Background()
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		t.Fatal("dedicated database required")
	}
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	workspaceID := governance.FixtureWorkspaceIDForTest()
	fx := testutil.New(pool, workspaceID, "")
	fx.UserID = fx.User(t, "Execution claim owner", "execution-claim-"+uuid.NewString()+"@example.test")
	fx.Member(t, workspaceID, fx.UserID, "owner")
	owner := "aifi45-owner-" + uuid.NewString()
	runtimeID := fx.Runtime(t, "execution claim owner", testutil.Cols{"daemon_id": owner})
	agentID := fx.Agent(t, "execution claim agent", runtimeID)
	issueID := fx.Issue(t, "execution claim issue")
	generation := time.Date(2026, 10, 24, 12, 0, 0, 123456000, time.UTC)
	taskID := fx.Task(t, agentID, testutil.Cols{
		"issue_id": issueID, "runtime_id": runtimeID,
		"status": "dispatched", "dispatched_at": generation,
	})
	queries := db.New(pool)
	h := &handler.Handler{
		Queries:     queries,
		TaskService: service.NewTaskService(queries, pool, realtime.NewHub(), events.New()),
	}
	routes := chi.NewRouter()
	routes.Route("/api/daemon", func(r chi.Router) {
		r.Use(middleware.DaemonAuth(queries, nil, nil, nil))
		r.Post("/tasks/{taskId}/start", h.StartTask)
	})
	request := func(daemonID string) *http.Request {
		t.Helper()
		token := "mdt_" + uuid.NewString()
		hash := auth.HashToken(token)
		if _, err := pool.Exec(ctx, `INSERT INTO daemon_token (token_hash,workspace_id,daemon_id,expires_at) VALUES ($1,$2::uuid,$3,now()+interval '1 hour')`, hash, workspaceID, daemonID); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() {
			if _, err := pool.Exec(ctx, `DELETE FROM daemon_token WHERE token_hash=$1`, hash); err != nil {
				t.Error(err)
			}
		})
		body, err := json.Marshal(map[string]string{
			"runtime_id": runtimeID, "dispatched_at": generation.Format(time.RFC3339Nano),
			"daemon_id": owner, "workspace_id": workspaceID,
		})
		if err != nil {
			t.Fatal(err)
		}
		req := httptest.NewRequest(http.MethodPost, "/api/daemon/tasks/"+taskID+"/start", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Daemon-ID", owner)
		return req
	}
	call := func(daemonID string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		routes.ServeHTTP(w, request(daemonID))
		return w
	}
	other := "aifi45-other-" + uuid.NewString()
	if w := call(other); w.Code != http.StatusConflict {
		t.Fatalf("foreign daemon with the exact claim started task: status=%d body=%s", w.Code, w.Body.String())
	}
	t.Run("empty_authenticated_daemon", func(t *testing.T) {
		if w := call(""); w.Code != http.StatusForbidden {
			t.Fatalf("empty authenticated daemon identity: status=%d body=%s", w.Code, w.Body.String())
		}
	})
	for range 2 {
		if w := call(owner); w.Code != http.StatusOK {
			t.Fatalf("owner start/replay: status=%d body=%s", w.Code, w.Body.String())
		}
	}
	if w := call(other); w.Code != http.StatusConflict {
		t.Fatalf("foreign daemon acknowledged owner run: status=%d body=%s", w.Code, w.Body.String())
	}
	t.Run("ownership_change_during_start", func(t *testing.T) {
		issueID := fx.Issue(t, "execution claim ownership race")
		taskID = fx.Task(t, agentID, testutil.Cols{
			"issue_id": issueID, "runtime_id": runtimeID,
			"status": "dispatched", "dispatched_at": generation,
		})
		req := request(owner)
		tx, err := pool.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		var blocker int
		if err := tx.QueryRow(ctx, `SELECT pg_backend_pid()`).Scan(&blocker); err != nil {
			t.Fatal(err)
		}
		if _, err := tx.Exec(ctx, `UPDATE agent_runtime SET daemon_id=$2 WHERE id=$1::uuid`, runtimeID, other); err != nil {
			t.Fatal(err)
		}
		result := make(chan *httptest.ResponseRecorder, 1)
		go func() {
			w := httptest.NewRecorder()
			routes.ServeHTTP(w, req)
			result <- w
		}()
		deadline := time.Now().Add(5 * time.Second)
		for {
			var blocked bool
			if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname=current_database() AND $1::int=ANY(pg_blocking_pids(pid)) AND query LIKE '-- name: LockAgentRuntime%')`, blocker).Scan(&blocked); err != nil {
				t.Fatal(err)
			}
			if blocked {
				break
			}
			select {
			case w := <-result:
				t.Fatalf("start did not lock runtime ownership: status=%d body=%s", w.Code, w.Body.String())
			default:
			}
			if time.Now().After(deadline) {
				t.Fatal("start did not wait for the owned runtime row")
			}
			time.Sleep(5 * time.Millisecond)
		}
		if err := tx.Commit(ctx); err != nil {
			t.Fatal(err)
		}
		select {
		case w := <-result:
			if w.Code != http.StatusConflict {
				t.Fatalf("stale daemon started after reassignment: status=%d body=%s", w.Code, w.Body.String())
			}
		case <-time.After(5 * time.Second):
			t.Fatal("start did not finish after runtime ownership committed")
		}
	})
}
