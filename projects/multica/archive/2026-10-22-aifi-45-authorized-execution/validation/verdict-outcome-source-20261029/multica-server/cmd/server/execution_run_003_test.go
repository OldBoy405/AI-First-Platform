// AIFIRST: AIFI-45 (SC-RUN-003) — TC-RUN-003.
//
// A grant is delivered and acknowledged while the trusted T commit has not landed, and the
// wake must only wake: no node passes, nothing is dispatched, the run does not complete.
// Only when the whole trusted chain commits does the same wake dispatch exactly once.
//
// The three false greens this is built to avoid:
//
//  1. Never reaching a dispatchable path. The fixture seeds the real source task, the real
//     executor agents and their skills, and drives the real router-constructed TaskService,
//     so "no task" means the gate held rather than that the walk could never dispatch.
//  2. A barrier that is not the commit. The phases are committed database states, not
//     sleeps: ACK only, then the platform consumption, then the settlement, then a refused
//     verdict, then a signed verdict committed by the real writer with its cursor.
//     Each phase runs its own wake, and only the last one may dispatch.
//  3. Counting queue rows only. Every phase also asserts the node did not pass and the run
//     did not complete. After dispatch, the test checks any human gate has not passed.
package main

import (
	"context"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/multica-ai/multica/server/internal/analytics"
	"github.com/multica-ai/multica/server/internal/auth"
	"github.com/multica-ai/multica/server/internal/events"
	"github.com/multica-ai/multica/server/internal/governance"
	"github.com/multica-ai/multica/server/internal/realtime"
	"github.com/multica-ai/multica/server/pkg/protocol"
)

func TestTC_RUN_003(t *testing.T) {
	if testPool == nil {
		t.Fatal("TC-RUN-003 needs the dedicated database")
	}
	ctx := context.Background()
	workspaceID := testWorkspaceID
	seed := uuid.New()
	crID := fmt.Sprintf("CR-9030-%s", new(big.Int).SetBytes(seed[:]).String())

	// The fixture derives what the pipeline needs from the embedded contract body rather
	// than restating it: a test that hardcodes the actors drifts silently when the registry
	// changes, and then passes because nothing resolves at all.
	var core struct {
		Pipeline struct {
			Nodes []struct {
				ID       string `json:"id"`
				Kind     string `json:"kind"`
				Ref      string `json:"ref"`
				Executor string `json:"executor"`
			} `json:"nodes"`
		} `json:"pipeline"`
		PipelineOwner string `json:"pipelineOwner"`
		Digest        string `json:"digest"`
	}
	if err := json.Unmarshal([]byte(governance.ArchitectureCoreRegistryJSON), &core); err != nil {
		t.Fatalf("decode the pipeline registry: %v", err)
	}
	if core.PipelineOwner == "" || core.Digest == "" || len(core.Pipeline.Nodes) == 0 {
		t.Fatalf("the pipeline registry is not the shape this fixture understands: %+v", core)
	}

	mustExec := func(t *testing.T, query string, args ...any) {
		t.Helper()
		if _, err := testPool.Exec(ctx, query, args...); err != nil {
			t.Fatalf("%s: %v", query, err)
		}
	}

	// Registered before the first row exists and filled in as the fixture grows, so a failure
	// anywhere below still removes what was already created.
	ids := &run003IDs{workspaceID: workspaceID, crID: crID}
	t.Cleanup(func() { cleanupRun003(t, ids) })
	var projectID, issueID, resourceID string
	if err := testPool.QueryRow(ctx, `INSERT INTO project (workspace_id,title) VALUES ($1::uuid,'run003') RETURNING id::text`, workspaceID).Scan(&projectID); err != nil {
		t.Fatal(err)
	}
	ids.projectID = projectID
	var issueNumber int
	if err := testPool.QueryRow(ctx, `
		UPDATE workspace SET issue_counter = GREATEST(issue_counter,
			(SELECT COALESCE(MAX(number),0) FROM issue WHERE workspace_id=$1::uuid)) + 1
		WHERE id=$1::uuid RETURNING issue_counter`, workspaceID).Scan(&issueNumber); err != nil {
		t.Fatal(err)
	}
	if err := testPool.QueryRow(ctx, `INSERT INTO issue (workspace_id,project_id,title,creator_type,creator_id,number) VALUES ($1::uuid,$2::uuid,'run003 shell','member',$3::uuid,$4) RETURNING id::text`,
		workspaceID, projectID, testUserID, issueNumber).Scan(&issueID); err != nil {
		t.Fatal(err)
	}
	ids.issueID = issueID
	resourceRef := []byte(`{"url":"https://example.com/multica.git","ref":"main","default_branch_hint":"main"}`)
	if err := testPool.QueryRow(ctx, `INSERT INTO project_resource (workspace_id,project_id,resource_type,resource_ref,label) VALUES ($1::uuid,$2::uuid,'github_repo',$3::jsonb,'run003 fixture') RETURNING id::text`,
		workspaceID, projectID, resourceRef).Scan(&resourceID); err != nil {
		t.Fatal(err)
	}
	binding, err := protocol.NewProjectResourceBinding(resourceID, workspaceID, projectID, "github_repo", resourceRef)
	if err != nil {
		t.Fatal(err)
	}
	mustExec(t, `INSERT INTO cr (workspace_id,cr_id,title,status,shell_issue_id) VALUES ($1::uuid,$2,'run003','tech-designing',$3::uuid)`, workspaceID, crID, issueID)

	// Executor agents and their skills, exactly the ones the contract names.
	runtimeID := uuid.NewString()
	mustExec(t, `INSERT INTO agent_runtime (id,workspace_id,name,runtime_mode,provider) VALUES ($1::uuid,$2::uuid,'run003-runtime','local','multica_daemon')`, runtimeID, workspaceID)
	ids.runtimeID = runtimeID
	agentIDs := map[string]string{}
	seedAgent := func(name string) string {
		var id string
		if err := testPool.QueryRow(ctx, `INSERT INTO agent (workspace_id,name,runtime_mode,runtime_id) VALUES ($1::uuid,$2,'local',$3::uuid) RETURNING id::text`,
			workspaceID, name, runtimeID).Scan(&id); err != nil {
			t.Fatalf("seed agent %s: %v", name, err)
		}
		return id
	}
	for _, name := range []string{core.PipelineOwner, "quality-reviewer-agent"} {
		if _, ok := agentIDs[name]; ok {
			continue
		}
		agentIDs[name] = seedAgent(name)
	}
	for _, node := range core.Pipeline.Nodes {
		if node.Kind != "skill" || node.Ref == "" {
			continue
		}
		key := node.Executor
		if key == "" {
			key = core.PipelineOwner
		}
		agentID, ok := agentIDs[key]
		if !ok {
			t.Fatalf("node %s names executor %q, which this fixture does not seed", node.Ref, key)
		}
		mustExec(t, `INSERT INTO skill (workspace_id,name,content) VALUES ($1::uuid,$2,'run003 fixture') ON CONFLICT (workspace_id,name) DO NOTHING`, workspaceID, node.Ref)
		mustExec(t, `INSERT INTO agent_skill (agent_id,skill_id,enabled) SELECT $1::uuid,id,true FROM skill WHERE workspace_id=$2::uuid AND name=$3 ON CONFLICT (agent_id,skill_id) DO UPDATE SET enabled=true`,
			agentID, workspaceID, node.Ref)
	}

	// The source task's author is a distinct agent, not the pipeline owner. Without this the
	// executor attribution would be untestable: the source agent and the resolved executor are
	// the same row, so any "wrong agent" regression looks identical to the correct one.
	agentIDs["run003-author"] = seedAgent("run003-author")
	for _, node := range core.Pipeline.Nodes {
		if node.Kind != "skill" || node.Ref == "" {
			continue
		}
		mustExec(t, `INSERT INTO agent_skill (agent_id,skill_id,enabled) SELECT $1::uuid,id,true FROM skill WHERE workspace_id=$2::uuid AND name=$3 ON CONFLICT (agent_id,skill_id) DO UPDATE SET enabled=true`,
			agentIDs["run003-author"], workspaceID, node.Ref)
	}
	// The source task the dispatch derives its attribution from.
	sourceTaskID := uuid.NewString()
	mustExec(t, `INSERT INTO agent_task_queue (id,agent_id,runtime_id,status,priority,issue_id,originator_source,originator_user_id,accountable_user_id,trigger_evidence_kind,trigger_evidence_ref_id)
		VALUES ($1::uuid,$2::uuid,$3::uuid,'completed',0,$4::uuid,'task_token',$5::uuid,$5::uuid,'task',$1::uuid)`,
		sourceTaskID, agentIDs["run003-author"], runtimeID, issueID, testUserID)

	inputs, _ := json.Marshal(map[string]any{"cr_id": crID, "tech_context": "run003"})
	execCtx, _ := json.Marshal(map[string]any{
		"runner": "architecture-core/v1", "template_digest": core.Digest,
		"pipeline_owner": core.PipelineOwner, "executor_agent_id": agentIDs[core.PipelineOwner], "source_task_id": sourceTaskID,
	})
	var runID string
	if err := testPool.QueryRow(ctx, `
		INSERT INTO pipeline_run (workspace_id,pipeline_id,cr_id,status,inputs,execution_context,started_by)
		VALUES ($1::uuid,'architecture-design',$2,'running',$3::jsonb,$4::jsonb,$5::uuid) RETURNING id::text`,
		workspaceID, crID, inputs, execCtx, testUserID).Scan(&runID); err != nil {
		t.Fatal(err)
	}
	ids.runID = runID

	// The grant, issued and acknowledged through the real routes.
	_, privateKey, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(privateKey)
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("APPROVAL_SIGNING_KEY", base64.StdEncoding.EncodeToString(der))
	t.Setenv("APPROVAL_SIGNING_KEY_ID", "run003")
	contract := governance.ExecutionContract{
		PolicyVersion: governance.ExecutionPolicyVersion,
		PolicyDigest:  strings.Repeat("a", 64), TemplateDigest: strings.Repeat("b", 64),
	}
	router, handler := NewRouterWithOptions(testPool, realtime.NewHub(), events.New(), analytics.NoopClient{}, nil, RouterOptions{ExecutionContract: &contract})

	selection := map[string]string{"resource_id": resourceID, "binding_digest": binding.BindingDigest}
	grantBody, err := json.Marshal(map[string]any{
		"goal": "run003", "scope_revision": 1,
		"allowed_repositories": []string{"multica"}, "allowed_paths": map[string][]string{"multica": {"server"}},
		"delivery_targets": []string{"review branch"}, "acceptance": []string{"none"},
		"prohibitions": []string{"no deployment"}, "sensitive_actions": []any{},
		"policy_version": contract.PolicyVersion, "policy_digest": contract.PolicyDigest, "template_digest": contract.TemplateDigest,
		"target_version": "v1.2.3", "target_spec_id": "run003", "repair_limit": 0,
		"repository_selections": map[string]any{"multica": selection}, "coordinator_selection": selection,
	})
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/workspaces/"+workspaceID+"/crs/"+crID+"/execution-authorization", strings.NewReader(string(grantBody)))
	req.Header.Set("Authorization", "Bearer "+testToken)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("grant issuance = %d, want 201: %s", rec.Code, rec.Body.String())
	}

	daemonToken := "mdt_" + uuid.NewString()
	ids.daemonTokenHash = auth.HashToken(daemonToken)
	mustExec(t, `INSERT INTO daemon_token (token_hash,workspace_id,daemon_id,expires_at) VALUES ($1,$2::uuid,'run003-daemon',now()+interval '1 hour')`,
		ids.daemonTokenHash, workspaceID)
	var headID string
	if err := testPool.QueryRow(ctx, `SELECT id::text FROM approval_record WHERE workspace_id=$1::uuid AND cr_id=$2 AND stage='execution' AND decision='approve'`,
		workspaceID, crID).Scan(&headID); err != nil {
		t.Fatal(err)
	}

	// The real ACK route commits the delivery fact. It must not dispatch anything by itself:
	// execution authorizations are excluded from the legacy continuation wake on purpose.
	ackBody := `{"ids":["` + headID + `"]}`
	req = httptest.NewRequest(http.MethodPost, "/api/daemon/approvals/ack", strings.NewReader(ackBody))
	req.Header.Set("Authorization", "Bearer "+daemonToken)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code < 200 || rec.Code > 299 {
		t.Fatalf("ack = %d, want 2xx: %s", rec.Code, rec.Body.String())
	}
	var delivered bool
	if err := testPool.QueryRow(ctx, `SELECT delivered_at IS NOT NULL FROM approval_record WHERE id=$1::uuid`, headID).Scan(&delivered); err != nil || !delivered {
		t.Fatalf("the ack did not commit delivery: delivered=%v err=%v", delivered, err)
	}

	if handler == nil || handler.TaskService == nil {
		t.Fatal("the router returned no TaskService, so this test cannot drive real dispatch")
	}
	runner, err := governance.NewRunnerWithOptions(testPool, events.New(), handler.TaskService,
		governance.RunnerOptions{AdmissionDecider: governance.NewAdmissionDecider()})
	if err != nil {
		t.Fatal(err)
	}
	tasks := func(t *testing.T) int {
		t.Helper()
		var n int
		if err := testPool.QueryRow(ctx, `SELECT count(*) FROM agent_task_queue WHERE cr_id=$1`, crID).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	// nodeStatus and waitReason are addressed by the node the gate is holding, with its
	// attempt, and a query failure is a failure: an empty string standing in for "no row" made
	// the assertions read as passing when the row they meant did not exist.
	nodeStatus := func(t *testing.T, nodeID string) string {
		t.Helper()
		var status string
		if err := testPool.QueryRow(ctx, `SELECT status FROM pipeline_node_run WHERE run_id=$1::uuid AND node_id=$2::uuid AND attempt=1`,
			runID, nodeID).Scan(&status); err != nil {
			t.Fatalf("read node %s status: %v", nodeID, err)
		}
		return status
	}
	waitReason := func(t *testing.T) string {
		t.Helper()
		var reason string
		var rows int
		if err := testPool.QueryRow(ctx, `
			SELECT COALESCE(detail->'runner'->>'admission',''), count(*) OVER ()
			FROM pipeline_node_run WHERE run_id=$1::uuid AND node_id=$2::uuid AND attempt=1`,
			runID, core.Pipeline.Nodes[0].ID).Scan(&reason, &rows); err != nil {
			t.Fatalf("read the held node's admission reason: %v", err)
		}
		if rows != 1 {
			t.Fatalf("the held node has %d rows at attempt 1, want exactly 1", rows)
		}
		return reason
	}
	runStatus := func(t *testing.T) string {
		t.Helper()
		var status string
		if err := testPool.QueryRow(ctx, `SELECT status FROM pipeline_run WHERE id=$1::uuid`, runID).Scan(&status); err != nil {
			t.Fatal(err)
		}
		return status
	}
	// wake is the periodic/Ack-callback entry: the same route the daemon's wake uses.
	wake := func(t *testing.T) {
		t.Helper()
		if err := runner.WakeGrant(ctx, governance.GrantAckEvent{
			WorkspaceID: workspaceID, CrID: crID, RecordID: headID, Stage: "execution", Decision: "approve",
		}); err != nil {
			t.Fatalf("wake: %v", err)
		}
	}
	// held asserts nothing advanced. Every phase uses it, so a gate that stops working shows
	// up on the business facts and not only on a queue count.
	held := func(t *testing.T, wantReason, phase string) {
		t.Helper()
		if got := tasks(t); got != 0 {
			t.Fatalf("%s: %d task(s) dispatched while the trusted commit had not landed", phase, got)
		}
		if got := nodeStatus(t, core.Pipeline.Nodes[0].ID); got == "passed" {
			t.Fatalf("%s: the write node passed while the trusted commit had not landed", phase)
		}
		if got := runStatus(t); got != "running" && got != "waiting_approval" {
			t.Fatalf("%s: the run left its active states (%q) while the trusted commit had not landed", phase, got)
		}
		if got := waitReason(t); got != wantReason {
			t.Fatalf("%s: admission reason = %q, want %q", phase, got, wantReason)
		}
	}

	// Phase 1: delivered and acknowledged, nothing consumed.
	wake(t)
	held(t, "WAIT_CONSUMPTION", "ack only")

	// Phase 2: the platform consumption commits, the trusted store has not.
	consumptionTask := uuid.NewString()
	mustExec(t, `INSERT INTO cr_execution_consumption (id,workspace_id,cr_id,project_id,daemon_id,runtime_id,task_id,dispatched_at,grant_digest,challenge)
		VALUES (gen_random_uuid(),$1::uuid,$2,$3::uuid,'run003-daemon',$4::uuid,$5::uuid,now(),$6,$7)`,
		workspaceID, crID, projectID, uuid.NewString(), consumptionTask,
		strings.Repeat("a", 64), strings.Repeat("b", 64))
	wake(t)
	held(t, "WAIT_TRUSTED_T_COMMIT", "platform consumption only")

	// Phase 3: the channel records a settlement for that request, still no verdict.
	verdictID := uuid.NewString()
	mustExec(t, `INSERT INTO cr_execution_control_settlement (request_id,verdict_id,kind,effect_kind,effect_ref,fixed_candidate_digest,head_ref)
		VALUES ($1::uuid,$2::uuid,'effect','dispatch','{}'::jsonb,$3,'root-run003')`, consumptionTask, verdictID, strings.Repeat("d", 64))
	wake(t)
	held(t, "WAIT_TRUSTED_T_COMMIT", "settlement without a verdict")

	// Phase 4: a forged verdict cannot be committed, so a subsequent wake still waits.
	lineageID := uuid.NewString()
	const storeID = "run003-store"
	mustExec(t, `INSERT INTO cr_execution_tool_cursor (scope,lineage_id,store_id,epoch,last_seq,owner_fence)
		VALUES ('execution',$1::uuid,$2,1,0,1)`, lineageID, storeID)
	public, verdictPrivate, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatal(err)
	}
	_, impostor, err := ed25519.GenerateKey(nil)
	if err != nil {
		t.Fatal(err)
	}
	const keyID = "run003-verdict"
	scope := governance.ControlScope{"store_id": storeID, "lineage_id": lineageID}
	manifest := &governance.ControlTrustManifest{ManifestID: "run003-test", Keys: map[string]governance.ControlKey{keyID: {
		KeyID: keyID, Purpose: "tool-attestation", Domains: []string{governance.VerdictDomain}, Scope: scope,
		ValidFrom: time.Now().Add(-time.Hour), ValidUntil: time.Now().Add(time.Hour), PublicKey: public,
	}}}
	payload, err := json.Marshal(map[string]any{
		"schema": "execution-control-verdict/v1", "purpose": "verdict", "domain": governance.VerdictDomain,
		"scope": scope, "request_id": consumptionTask, "epoch": 1, "sequence": 1, "previous_verdict_digest": "",
	})
	if err != nil {
		t.Fatal(err)
	}
	sign := func(key ed25519.PrivateKey) []byte {
		t.Helper()
		envelope, err := governance.SignControlPayloadBytes(payload, governance.SignControlRequest{
			KeyID: keyID, PrivateKey: key, Schema: "execution-control-verdict/v1", Domain: governance.VerdictDomain, Scope: scope,
		})
		if err != nil {
			t.Fatal(err)
		}
		return envelope
	}
	frame := governance.VerdictFrameInput{
		VerdictID: verdictID, Scope: "execution", LineageID: lineageID, RequestID: consumptionTask,
		StoreID: storeID, Epoch: 1, Seq: 1, PayloadBytes: payload, CommitRef: "refs/heads/run003",
		Manifest: manifest, AttestationScope: scope,
	}
	appendFrame := func(in governance.VerdictFrameInput) error {
		t.Helper()
		tx, err := testPool.Begin(ctx)
		if err != nil {
			return err
		}
		defer tx.Rollback(ctx)
		if _, err := governance.AppendVerdictFrameTx(ctx, tx, in); err != nil {
			return err
		}
		return tx.Commit(ctx)
	}
	frame.Envelope = sign(impostor)
	if err := appendFrame(frame); !errors.Is(err, governance.ErrControlSignatureInvalid) {
		t.Fatalf("forged verdict was not rejected as an invalid signature: %v", err)
	}
	var verdictRows int
	if err := testPool.QueryRow(ctx, `SELECT count(*) FROM cr_execution_tool_verdict WHERE request_id=$1::uuid`, consumptionTask).Scan(&verdictRows); err != nil || verdictRows != 0 {
		t.Fatalf("forged verdict persisted: rows=%d err=%v", verdictRows, err)
	}
	wake(t)
	held(t, "WAIT_TRUSTED_T_COMMIT", "forged verdict refused")

	// Phase 5: the writer atomically commits the verified verdict and advances its cursor.
	frame.Envelope = sign(verdictPrivate)
	if err := appendFrame(frame); err != nil {
		t.Fatalf("append the signed verdict through the real writer: %v", err)
	}
	wake(t)
	if got := tasks(t); got != 1 {
		t.Fatalf("after the trusted commit the wake dispatched %d task(s), want exactly 1", got)
	}
	if got := runStatus(t); got == "completed" {
		t.Fatal("the run completed on the dispatch wake")
	}
	// A count of one says something was dispatched, not that it was the node this walk is on,
	// by the agent that owns the pipeline, for the issue the run is on. The attribution is
	// read back from the real columns CreatePipelineTask writes: the node run it serves, the
	// executor, and the issue/project snapshot it copied from the source task.
	writeNodeID := core.Pipeline.Nodes[0].ID
	var writeNodeRunID string
	if err := testPool.QueryRow(ctx, `SELECT id::text FROM pipeline_node_run WHERE run_id=$1::uuid AND node_id=$2::uuid AND attempt=1`,
		runID, writeNodeID).Scan(&writeNodeRunID); err != nil {
		t.Fatalf("read the write node run: %v", err)
	}
	var taskID, taskAgent, taskIssue, taskNodeRun, taskContext string
	if err := testPool.QueryRow(ctx, `
		SELECT id::text, agent_id::text, issue_id::text, pipeline_node_run_id::text, context::text
		FROM agent_task_queue WHERE cr_id=$1 AND pipeline_node_run_id IS NOT NULL`, crID).
		Scan(&taskID, &taskAgent, &taskIssue, &taskNodeRun, &taskContext); err != nil {
		t.Fatalf("read the dispatched task: %v", err)
	}
	if taskNodeRun != writeNodeRunID {
		t.Fatalf("the dispatched task serves node run %s, want %s", taskNodeRun, writeNodeRunID)
	}
	if taskAgent != agentIDs[core.PipelineOwner] {
		t.Fatalf("the dispatched task went to agent %s, want %s", taskAgent, agentIDs[core.PipelineOwner])
	}
	if taskIssue != issueID {
		t.Fatalf("the dispatched task carries issue %s, want %s", taskIssue, issueID)
	}
	if !strings.Contains(taskContext, runID) || !strings.Contains(taskContext, writeNodeID) {
		t.Fatalf("the dispatched task is not bound to this run/node: %s", taskContext)
	}
	// The human gate is not passed by a dispatch: it belongs to a later phase of the walk.
	humanNodeID := ""
	for _, node := range core.Pipeline.Nodes {
		if node.Kind == "human_approval" {
			humanNodeID = node.ID
		}
	}
	if humanNodeID != "" {
		// A row that does not exist yet is the correct state here — the walk never reached the
		// human gate — but reading it as "passed" or as an error would both be wrong, so the
		// two cases are distinguished instead of collapsed into one status string.
		var status string
		err := testPool.QueryRow(ctx, `SELECT status FROM pipeline_node_run WHERE run_id=$1::uuid AND node_id=$2::uuid`,
			runID, humanNodeID).Scan(&status)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			t.Fatalf("read the human gate node: %v", err)
		}
		if err == nil && status == "passed" {
			t.Fatal("the human gate passed without a human decision")
		}
	}

	// A second wake must not dispatch a second task. Counting alone would pass if the first
	// task were replaced by a second one, so the row is identified, not counted.
	wake(t)
	if got := tasks(t); got != 1 {
		t.Fatalf("a repeated wake dispatched another task: %d in total", got)
	}
	var repeatID string
	if err := testPool.QueryRow(ctx, `SELECT id::text FROM agent_task_queue WHERE cr_id=$1 AND pipeline_node_run_id IS NOT NULL`,
		crID).Scan(&repeatID); err != nil {
		t.Fatalf("read the task after the repeated wake: %v", err)
	}
	if repeatID != taskID {
		t.Fatalf("a repeated wake re-dispatched the node: %s -> %s", taskID, repeatID)
	}
}

// run003IDs is filled in as the fixture is seeded so the cleanup registered at the start can
// remove whatever exists, even when seeding failed half-way.
type run003IDs struct {
	workspaceID, crID, projectID, issueID, runtimeID, runID, daemonTokenHash string
}

// cleanupRun003 removes the fixture, statement by statement. Each delete runs independently and
// reports through t.Logf: one failing delete must not abort the rest and leave the workspace
// dirtier than it found it.
func cleanupRun003(t *testing.T, ids *run003IDs) {
	t.Helper()
	ctx := context.Background()
	statements := []struct {
		sql  string
		args []any
	}{
		{`DELETE FROM daemon_token WHERE token_hash=$1`, []any{ids.daemonTokenHash}},
		{`DELETE FROM pipeline_run WHERE id=$1::uuid`, []any{ids.runID}},
		{`DELETE FROM agent_task_queue WHERE issue_id=$1::uuid`, []any{ids.issueID}},
		{`DELETE FROM approval_record WHERE workspace_id=$1::uuid AND cr_id=$2`, []any{ids.workspaceID, ids.crID}},
		{`DELETE FROM cr WHERE workspace_id=$1::uuid AND cr_id=$2`, []any{ids.workspaceID, ids.crID}},
		{`DELETE FROM skill WHERE workspace_id=$1::uuid AND content='run003 fixture'`, []any{ids.workspaceID}},
		{`DELETE FROM agent WHERE workspace_id=$1::uuid AND runtime_id=$2::uuid`, []any{ids.workspaceID, ids.runtimeID}},
		{`DELETE FROM agent_runtime WHERE id=$1::uuid`, []any{ids.runtimeID}},
		{`DELETE FROM issue WHERE workspace_id=$1::uuid AND id=$2::uuid`, []any{ids.workspaceID, ids.issueID}},
		{`DELETE FROM project WHERE workspace_id=$1::uuid AND id=$2::uuid`, []any{ids.workspaceID, ids.projectID}},
	}
	for _, st := range statements {
		// An id that was never assigned would turn "$1::uuid" into a syntax error; skipping is
		// how "this part of the fixture was never created" is expressed here.
		if len(st.args) > 0 {
			if v, ok := st.args[0].(string); ok && v == "" {
				continue
			}
		}
		if _, err := testPool.Exec(ctx, st.sql, st.args...); err != nil {
			t.Logf("cleanup: %s: %v", st.sql, err)
		}
	}
	// The consumption, settlement, verdict and cursor rows are intentionally left in place:
	// they are append-only facts, and this fixture depends on the per-run disposable database
	// rather than pretending they can be deleted.
}
