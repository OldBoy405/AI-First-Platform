package daemon

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestExecutionTaskClaimReadPrecedesRootPreparation(t *testing.T) {
	const workspace = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	const project = "11111111-1111-4111-8111-111111111111"
	const crID = "CR-2026-903"
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("USERPROFILE", home)
	root := seedPipelineCRRoot(t, crID)
	executionRootBindingFixture(t, root)
	collector := newCREventCollector(nil, &fakeReporter{ack: acceptAll}, testLogger(t))
	if _, err := collector.applyLocalDirectorySnapshot(executionRootSnapshot(workspace, "daemon-exec-root",
		executionRootResource{ID: "33333333-3333-4333-8333-333333333331", Project: project, Root: root},
	)); err != nil {
		t.Fatal(err)
	}
	var claimReads, otherRequests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/daemon/tasks/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/status" && r.URL.Query().Get("execution_claim") == "1" {
			claimReads.Add(1)
		} else {
			otherRequests.Add(1)
		}
		http.Error(w, "claim was replaced", http.StatusConflict)
	}))
	defer server.Close()
	client := NewClient(server.URL)
	client.SetToken("mdt_literal_test_only")
	d := &Daemon{cfg: Config{DaemonID: "daemon-exec-root"}, client: client, crCollector: collector, logger: testLogger(t)}
	task := strictRootTask(crID, project, authorizedExecutionComment(""))
	task.ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
	task.RuntimeID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
	task.WorkspaceID = workspace
	task.DispatchedAt = "2026-10-25T05:30:00.123456Z"
	if err := d.prepareClaimedPipelineTask(context.Background(), &task); err == nil {
		t.Fatal("unverified claim must not prepare execution")
	}
	if claimReads.Load() != 1 || otherRequests.Load() != 0 {
		t.Fatalf("claim must be read before any other platform request: claim=%d other=%d", claimReads.Load(), otherRequests.Load())
	}
	if task.PipelineWorkspace != "" || task.PipelineLocalWorkDir != "" {
		t.Fatal("unverified claim must not resolve or prepare the CR root")
	}
}

func TestExecutionTaskClaimFailureDoesNotSendUnfencedTerminalCallback(t *testing.T) {
	var callbacks, reads atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reads.Add(1)
		http.Error(w, "claim was replaced", http.StatusConflict)
	}))
	defer server.Close()
	client := NewClient(server.URL)
	client.SetToken("mdt_literal_test_only")
	task := strictRootTask("CR-2026-904", "11111111-1111-4111-8111-111111111111", authorizedExecutionComment(""))
	task.ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
	task.RuntimeID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
	task.WorkspaceID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	task.DispatchedAt = "2026-10-25T05:30:00.123456Z"
	task.StartClaimSupported = true
	d := &Daemon{
		cfg: Config{DaemonID: "daemon-exec-root"}, client: client, logger: testLogger(t),
		runtimeIndex: map[string]Runtime{task.RuntimeID: {Provider: "codex"}},
		terminalReportSend: func(context.Context, terminalTaskReport, []time.Duration) error {
			callbacks.Add(1)
			return nil
		},
	}
	d.handleTask(context.Background(), task, 0)
	if reads.Load() != 1 {
		t.Fatalf("platform claim reads = %d, want 1", reads.Load())
	}
	if callbacks.Load() != 0 {
		t.Fatalf("unverified claim sent %d task-ID-only terminal callbacks", callbacks.Load())
	}
}
