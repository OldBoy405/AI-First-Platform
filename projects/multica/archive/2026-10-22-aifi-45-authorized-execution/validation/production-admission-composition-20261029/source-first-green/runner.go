// AIFIRST: Runner Core (CR-2026-045, SDD §3.4/§5).
//
// This is intentionally not a generic workflow engine. It drives the fixed
// architecture-design slice with one idempotent Reconcile entry point and
// leaves CR state, approval validation, and Git effects to Skills + crctl.
package governance

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/multica-ai/multica/server/internal/events"
	"github.com/multica-ai/multica/server/internal/service"
	db "github.com/multica-ai/multica/server/pkg/db/generated"
	"github.com/multica-ai/multica/server/pkg/protocol"
)

const (
	RunnerErrUnsupportedPipeline    = "RUNNER_UNSUPPORTED_PIPELINE"
	RunnerErrNoExecutorForStage     = "RUNNER_NO_EXECUTOR_FOR_STAGE"
	RunnerErrRequiresAgentRoute     = "RUNNER_REQUIRES_AGENT_ROUTE"
	RunnerErrCRNotReady             = "RUNNER_CR_NOT_READY"
	RunnerErrAgentNotReady          = "RUNNER_AGENT_NOT_READY"
	RunnerErrSkillMissing           = "RUNNER_SKILL_MISSING"
	RunnerErrContractInvalid        = "RUNNER_CONTRACT_INVALID"
	RunnerErrTemplateDigestMismatch = "TEMPLATE_DIGEST_MISMATCH"
	RunnerErrAuthorityMismatch      = "RUNNER_AUTHORITY_MISMATCH"
	RunnerErrAttributionInvalid     = "RUNNER_ATTRIBUTION_INVALID"
	RunnerErrReviewEvidenceIncomp   = "RUNNER_REVIEW_EVIDENCE_INCOMPLETE"
	RunnerErrReviewDeliveryMissing  = "RUNNER_REVIEW_DELIVERY_MISSING"
	RunnerErrPipelineCrctlUnavail   = "PIPELINE_CRCTL_UNAVAILABLE"
	RunnerErrTaskFailed             = "RUNNER_TASK_FAILED"
	RunnerErrApprovalRejected       = "RUNNER_APPROVAL_REJECTED"
	RunnerErrLoopExhausted          = "RUNNER_LOOP_EXHAUSTED"
	// RunnerErrResumeUnsafe refuses a manual resume of a failed run whose own
	// facts do not make continuing it safe (AIFI-59). The run keeps its failure.
	RunnerErrResumeUnsafe = "RUNNER_RESUME_UNSAFE"
)

const (
	runnerSchema        = "architecture-core/v1"
	maxTechContextBytes = 16 * 1024
)

// AIFIRST: crIDPattern replaced by the shared dual-format CRIDPattern (AIFI-68 §3.1).

// ArchitectureRunnerEnabled is the deployment switch. Default-off preserves
// the existing manual Skill + crctl route; enabling only mounts/wires Core.
func ArchitectureRunnerEnabled() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("AIFIRST_ARCHITECTURE_RUNNER"))) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

type coreRegistry struct {
	Schema   string `json:"schema"`
	Pipeline struct {
		ID     string      `json:"id"`
		Name   string      `json:"name"`
		Inputs []coreInput `json:"inputs"`
		Nodes  []coreNode  `json:"nodes"`
	} `json:"pipeline"`
	PipelineOwner   string               `json:"pipelineOwner"`
	NodePermissions []coreNodePermission `json:"nodePermissions"`
	// Inputs is the derived key list the emitter writes beside the canonical
	// body. It is accepted only when it is exactly the keys pipeline.inputs
	// declares, in the same order.
	Inputs []string `json:"inputs"`
	Digest string   `json:"digest"`
	// Raw is the normalized wire envelope exactly as read. Typed fields above
	// are derived views; unknown execution fields stay available here so a
	// consumer never has to reconstruct them from a lossy struct.
	Raw json.RawMessage `json:"-"`
}

type coreInput struct {
	Key         string `json:"key"`
	Type        string `json:"type"`
	Required    *bool  `json:"required"`
	Label       string `json:"label"`
	Description string `json:"description"`
	Placeholder string `json:"placeholder"`
}

type coreNodePermission struct {
	NodeID               string `json:"nodeId"`
	Ref                  string `json:"ref"`
	Owner                string `json:"owner"`
	PipelineOwnerCanCall bool   `json:"pipelineOwnerCanCall"`
	Executor             string `json:"executor"`
}

type coreReplayNode struct {
	NodeID  string `json:"nodeId"`
	Ref     string `json:"ref"`
	Purpose string `json:"purpose"`
}

type coreReviewLoop struct {
	RepairNodeID  string           `json:"repairNodeId"`
	RepairRef     string           `json:"repairRef"`
	FeedbackInput string           `json:"feedbackInput"`
	AttemptInput  string           `json:"attemptInput"`
	OnBlock       string           `json:"onBlock"`
	ReplayPolicy  string           `json:"replayPolicy"`
	ReplayNodes   []coreReplayNode `json:"replayNodes"`
	MaxAttempts   int              `json:"maxAttempts"`
	PassCondition json.RawMessage  `json:"passCondition"`

	// These presence flags are derived from the same raw envelope as the typed
	// fields above. They distinguish an absent property from an explicitly empty
	// or null one, which the compiler's Object.hasOwn checks distinguish too.
	RepairNodeIDPresent bool `json:"-"`
	ReplayPolicyPresent bool `json:"-"`
	ReplayNodesPresent  bool `json:"-"`
}

type coreNode struct {
	ID             string          `json:"id"`
	Kind           string          `json:"kind"`
	Label          string          `json:"label"`
	Ref            string          `json:"ref"`
	Prompt         string          `json:"prompt"`
	OnFail         string          `json:"onFail"`
	Executor       string          `json:"executor"`
	ApprovalPrompt string          `json:"approvalPrompt"`
	TimeoutMinutes int             `json:"timeoutMinutes"`
	ReviewLoop     *coreReviewLoop `json:"reviewLoop"`

	// ReviewLoopPresent distinguishes an absent reviewLoop property from a
	// present null/object value; a pointer alone cannot express that difference.
	ReviewLoopPresent bool `json:"-"`
}

func (n *coreNode) UnmarshalJSON(data []byte) error {
	type nodeAlias coreNode
	var decoded nodeAlias
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	*n = coreNode(decoded)
	_, n.ReviewLoopPresent = fields["reviewLoop"]
	return nil
}

func (l *coreReviewLoop) UnmarshalJSON(data []byte) error {
	type loopAlias coreReviewLoop
	var decoded loopAlias
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	*l = coreReviewLoop(decoded)
	_, l.RepairNodeIDPresent = fields["repairNodeId"]
	_, l.ReplayPolicyPresent = fields["replayPolicy"]
	_, l.ReplayNodesPresent = fields["replayNodes"]
	return nil
}

type coreRegistryContract struct {
	schema, pipelineID, digest string
}

// coreRegistryContracts is the complete set of compiled registry pairs this
// deployment accepts. A body may name only one of these schemas and pipeline
// ids, and the caller's expected digest must be the compiled one for that
// pair; the body's own digest field is never the authority.
var coreRegistryContracts = []coreRegistryContract{
	{"ai-first.pipeline-registry/requirement-core-v1", PipelineIDs.RequirementAuthoring, RequirementCoreRegistryDigest},
	{"ai-first.pipeline-registry/architecture-core-v1", PipelineIDs.ArchitectureDesign, ArchitectureCoreRegistryDigest},
	{"ai-first.pipeline-registry/code-core-v1", PipelineIDs.CodeImplementation, CodeCoreRegistryDigest},
	{"ai-first.pipeline-registry/writeback-core-v1", PipelineIDs.FeatureWriteback, WritebackCoreRegistryDigest},
}

func coreRegistryContractFor(schema, pipelineID string) (coreRegistryContract, bool) {
	for _, contract := range coreRegistryContracts {
		if contract.schema == schema && contract.pipelineID == pipelineID {
			return contract, true
		}
	}
	return coreRegistryContract{}, false
}

// parseCoreRegistry validates the compiled architecture registry against the
// shared compiled-registry contract. parseCoreRegistryFrom is the same validation
// over an explicitly supplied snapshot, so a caller that is not reading the
// compiled one — a test, an offline checker — runs the parser rather than a
// restatement of it.
func parseCoreRegistry() (*coreRegistry, error) {
	return parseCoreRegistryFrom(ArchitectureCoreRegistryJSON, ArchitectureCoreRegistryDigest)
}

// parseCoreRegistryFrom accepts exactly the four compiled schemas. The digest
// parameter is an independently supplied expectation, not a value copied from
// the body; it must be the compiled digest for the pipeline the body names.
func parseCoreRegistryFrom(body, digest string) (*coreRegistry, error) {
	wire := strings.ReplaceAll(body, "\r\n", "\n")
	var r coreRegistry
	if err := json.Unmarshal([]byte(wire), &r); err != nil {
		return nil, errCode(RunnerErrContractInvalid, "malformed embedded registry")
	}
	r.Raw = json.RawMessage(append([]byte(nil), wire...))
	contract, ok := coreRegistryContractFor(r.Schema, r.Pipeline.ID)
	if !ok {
		return nil, errCode(RunnerErrContractInvalid, "registry schema or pipeline identity is not a compiled contract")
	}
	if digest != contract.digest || r.Digest != contract.digest {
		return nil, errCode(RunnerErrContractInvalid, "registry identity or digest mismatch")
	}
	if err := validateCoreRegistry(&r); err != nil {
		return nil, err
	}
	return &r, nil
}

// validateCoreRegistry checks one normalized envelope. It deliberately does
// not fix node counts, ref uniqueness, or loop placement: the templates declare
// those, and duplicate refs are legal when a nodeId identifies the exact node.
func validateCoreRegistry(r *coreRegistry) error {
	if r.PipelineOwner == "" {
		return errCode(RunnerErrContractInvalid, "registry pipeline owner missing")
	}
	if len(r.Pipeline.Nodes) == 0 || len(r.Pipeline.Inputs) == 0 {
		return errCode(RunnerErrContractInvalid, "registry pipeline is incomplete")
	}
	inputKeys := make([]string, 0, len(r.Pipeline.Inputs))
	seenInputs := map[string]bool{}
	for i := range r.Pipeline.Inputs {
		input := &r.Pipeline.Inputs[i]
		if input.Key == "" || input.Type == "" || input.Required == nil {
			return errCode(RunnerErrContractInvalid, fmt.Sprintf("input declaration %d is incomplete", i+1))
		}
		if seenInputs[input.Key] {
			return errCode(RunnerErrContractInvalid, "duplicate input key: "+input.Key)
		}
		seenInputs[input.Key] = true
		inputKeys = append(inputKeys, input.Key)
	}
	if len(r.Inputs) != len(inputKeys) {
		return errCode(RunnerErrContractInvalid, "top-level inputs are not the exact derived key list")
	}
	for i := range inputKeys {
		if r.Inputs[i] != inputKeys[i] {
			return errCode(RunnerErrContractInvalid, "top-level inputs are not the exact derived key list")
		}
	}

	nodes := map[string]*coreNode{}
	refs := map[string]int{}
	for i := range r.Pipeline.Nodes {
		node := &r.Pipeline.Nodes[i]
		if node.ID == "" || node.Kind == "" || node.OnFail == "" || node.TimeoutMinutes < 1 {
			return errCode(RunnerErrContractInvalid, fmt.Sprintf("node %d is incomplete", i+1))
		}
		if _, err := parseUUID(node.ID); err != nil {
			return errCode(RunnerErrContractInvalid, "node id is not UUID")
		}
		if nodes[node.ID] != nil {
			return errCode(RunnerErrContractInvalid, "duplicate node id: "+node.ID)
		}
		switch node.Kind {
		case "human_approval":
			if node.ApprovalPrompt == "" {
				return errCode(RunnerErrContractInvalid, "human node "+node.ID+" has no approval prompt")
			}
		case "skill", "code_generation":
			if node.Ref == "" || node.Prompt == "" {
				return errCode(RunnerErrContractInvalid, "nonhuman node "+node.ID+" is incomplete")
			}
		default:
			return errCode(RunnerErrContractInvalid, "unknown node kind: "+node.Kind)
		}
		nodes[node.ID] = node
		if node.Ref != "" {
			refs[node.Ref]++
		}
	}

	permissions := map[string]*coreNodePermission{}
	for i := range r.NodePermissions {
		permission := &r.NodePermissions[i]
		if permission.NodeID == "" || permission.Ref == "" || permission.Owner == "" || permission.Executor == "" || !permission.PipelineOwnerCanCall {
			return errCode(RunnerErrContractInvalid, "node permission invalid")
		}
		if _, duplicate := permissions[permission.NodeID]; duplicate {
			return errCode(RunnerErrContractInvalid, "duplicate node permission: "+permission.NodeID)
		}
		node := nodes[permission.NodeID]
		if node == nil {
			return errCode(RunnerErrContractInvalid, "node permission points at an unknown node: "+permission.NodeID)
		}
		if node.Kind == "human_approval" {
			return errCode(RunnerErrContractInvalid, "human node "+node.ID+" must not carry an execution permission")
		}
		executor := node.Executor
		if executor == "" {
			executor = r.PipelineOwner
		}
		if node.Ref != permission.Ref || executor != permission.Executor {
			return errCode(RunnerErrContractInvalid, "node permission is not sourced from node "+node.ID)
		}
		permissions[permission.NodeID] = permission
	}
	for id, node := range nodes {
		if node.Kind != "human_approval" && permissions[id] == nil {
			return errCode(RunnerErrContractInvalid, "node permission missing for "+id)
		}
	}

	for i := range r.Pipeline.Nodes {
		node := &r.Pipeline.Nodes[i]
		if strings.HasPrefix(node.Ref, "review-") && !node.ReviewLoopPresent {
			return errCode(RunnerErrContractInvalid, "independent review node "+node.ID+" has no reviewLoop")
		}
		if !node.ReviewLoopPresent {
			continue
		}
		if node.ReviewLoop == nil {
			return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" must be an object")
		}
		if err := validateCoreReviewLoop(r, node, nodes, refs); err != nil {
			return err
		}
	}
	return nil
}

func validateCoreReviewLoop(r *coreRegistry, node *coreNode, nodes map[string]*coreNode, refs map[string]int) error {
	loop := node.ReviewLoop
	if loop.MaxAttempts < 1 || strings.TrimSpace(loop.FeedbackInput) == "" || strings.TrimSpace(loop.AttemptInput) == "" || strings.TrimSpace(loop.OnBlock) == "" {
		return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" is incomplete")
	}
	var passCondition map[string]json.RawMessage
	if err := json.Unmarshal(loop.PassCondition, &passCondition); err != nil || len(passCondition) == 0 {
		return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" has no non-empty object passCondition")
	}

	if loop.RepairNodeIDPresent && strings.TrimSpace(loop.RepairNodeID) == "" {
		return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" has an empty repair id")
	}
	if strings.TrimSpace(loop.RepairRef) == "" {
		return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" has no repair ref")
	}
	var repair *coreNode
	if loop.RepairNodeID != "" {
		repair = nodes[loop.RepairNodeID]
		if repair == nil {
			return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" names an unknown repair node")
		}
		if repair.Ref != loop.RepairRef {
			return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" repair id and ref disagree")
		}
	} else {
		if refs[loop.RepairRef] != 1 {
			return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" has no unambiguous repair ref")
		}
		repair = nodeByRef(r, loop.RepairRef)
	}
	if repair == nil || repair.Kind == "human_approval" {
		return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" has an invalid repair target")
	}

	if loop.ReplayPolicyPresent && strings.TrimSpace(loop.ReplayPolicy) == "" {
		return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" has an empty replay policy")
	}
	if loop.ReplayNodesPresent {
		if len(loop.ReplayNodes) == 0 {
			return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" has an empty replayNodes")
		}
		if strings.TrimSpace(loop.ReplayPolicy) == "" {
			return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" declares replay nodes without a policy")
		}
		for _, replay := range loop.ReplayNodes {
			target := nodes[replay.NodeID]
			if target == nil || target.Ref != replay.Ref || target.Kind == "human_approval" {
				return errCode(RunnerErrContractInvalid, "reviewLoop on "+node.Ref+" has an invalid replay target")
			}
		}
	}
	return nil
}

func nodeByRef(r *coreRegistry, ref string) *coreNode {
	var found *coreNode
	for i := range r.Pipeline.Nodes {
		if r.Pipeline.Nodes[i].Ref != ref {
			continue
		}
		if found != nil {
			return nil
		}
		found = &r.Pipeline.Nodes[i]
	}
	return found
}

// PipelineReviewMaxAttempts reports the reviewLoop round bound the COMPILED registry
// for pipelineID declares (AIFI-58): the number of review rounds that pipeline may
// run, which is also the highest legal attempt. The daemon claim carrier consumes
// it, so a template that declares more rounds needs no second number kept in step
// by hand.
//
// An unknown pipeline, a registry that will not parse and a declaration that is not
// a positive integer all return an error; no fallback bound is invented, and no
// round limit is assumed.
func PipelineReviewMaxAttempts(pipelineID string) (int, error) {
	switch pipelineID {
	case PipelineIDs.RequirementAuthoring:
		return ReviewMaxAttemptsFromSnapshot(RequirementCoreRegistryJSON, RequirementCoreRegistryDigest, pipelineID)
	case PipelineIDs.ArchitectureDesign:
		return ReviewMaxAttemptsFromSnapshot(ArchitectureCoreRegistryJSON, ArchitectureCoreRegistryDigest, pipelineID)
	}
	return 0, errCode(RunnerErrContractInvalid, "no compiled registry declares pipeline "+pipelineID)
}

// ReviewMaxAttemptsFromSnapshot reads the bound one compiled snapshot declares for
// one pipeline, through the same parsers production uses. The snapshot is a
// parameter rather than the compiled constant so a test can read a body that is not
// the one this binary carries without a second reader: the validation under test is
// then the parser's, not a restatement of it.
func ReviewMaxAttemptsFromSnapshot(body, digest, pipelineID string) (int, error) {
	switch pipelineID {
	case PipelineIDs.RequirementAuthoring:
		registry, err := parseRequirementRegistryFrom(body, digest)
		if err != nil {
			return 0, err
		}
		review := registry.nodeByRef(refReviewRequirement)
		if review == nil || review.ReviewLoop == nil {
			return 0, errCode(RunnerErrContractInvalid, "requirement registry declares no review round")
		}
		return review.ReviewLoop.MaxAttempts, nil
	case PipelineIDs.ArchitectureDesign, PipelineIDs.CodeImplementation, PipelineIDs.FeatureWriteback:
		registry, err := parseCoreRegistryFrom(body, digest)
		if err != nil {
			return 0, err
		}
		if registry.Pipeline.ID != pipelineID {
			return 0, errCode(RunnerErrContractInvalid, "snapshot does not declare the requested pipeline")
		}
		bound := 0
		for i := range registry.Pipeline.Nodes {
			if loop := registry.Pipeline.Nodes[i].ReviewLoop; loop != nil && loop.MaxAttempts > bound {
				bound = loop.MaxAttempts
			}
		}
		if bound == 0 && pipelineID == PipelineIDs.FeatureWriteback {
			return 1, nil
		}
		if bound == 0 {
			return 0, errCode(RunnerErrContractInvalid, "pipeline registry declares no review round")
		}
		return bound, nil
	}
	return 0, errCode(RunnerErrContractInvalid, "pipeline is not one this deployment compiles a registry for: "+pipelineID)
}

// CompiledPipelineNode is the read-only contract one node of a compiled
// pipeline declares. It is derived from the same four expected windows the
// parser consumes; it is not an arbitrary-body validator or a second registry.
type CompiledPipelineNode struct {
	PipelineID  string
	Digest      string
	NodeID      string
	Kind        string
	Ref         string
	MaxAttempts int
}

func CompiledPipelineNodeFor(pipelineID, nodeID string) (CompiledPipelineNode, error) {
	var body, digest string
	switch pipelineID {
	case PipelineIDs.ArchitectureDesign:
		body, digest = ArchitectureCoreRegistryJSON, ArchitectureCoreRegistryDigest
	case PipelineIDs.RequirementAuthoring:
		body, digest = RequirementCoreRegistryJSON, RequirementCoreRegistryDigest
	case PipelineIDs.CodeImplementation:
		body, digest = CodeCoreRegistryJSON, CodeCoreRegistryDigest
	case PipelineIDs.FeatureWriteback:
		body, digest = WritebackCoreRegistryJSON, WritebackCoreRegistryDigest
	default:
		return CompiledPipelineNode{}, errCode(RunnerErrContractInvalid, "unknown compiled pipeline "+pipelineID)
	}
	registry, err := parseCoreRegistryFrom(body, digest)
	if err != nil {
		return CompiledPipelineNode{}, err
	}
	if registry.Pipeline.ID != pipelineID {
		return CompiledPipelineNode{}, errCode(RunnerErrContractInvalid, "compiled pipeline identity mismatch")
	}
	for i := range registry.Pipeline.Nodes {
		node := &registry.Pipeline.Nodes[i]
		if node.ID != nodeID {
			continue
		}
		if node.Kind == "human_approval" || node.Ref == "" {
			return CompiledPipelineNode{}, errCode(RunnerErrContractInvalid, "human or incomplete node is not a pipeline execution member")
		}
		maxAttempts := 0
		for j := range registry.Pipeline.Nodes {
			if loop := registry.Pipeline.Nodes[j].ReviewLoop; loop != nil && loop.MaxAttempts > maxAttempts {
				maxAttempts = loop.MaxAttempts
			}
		}
		if maxAttempts == 0 {
			maxAttempts = 1
		}
		return CompiledPipelineNode{PipelineID: pipelineID, Digest: digest, NodeID: node.ID, Kind: node.Kind, Ref: node.Ref, MaxAttempts: maxAttempts}, nil
	}
	return CompiledPipelineNode{}, errCode(RunnerErrContractInvalid, "node is not a member of pipeline "+pipelineID)
}

type pipelineTaskEnqueuer interface {
	EnqueuePipelineTask(context.Context, service.PipelineTaskSpec) (db.AgentTaskQueue, error)
}

type Runner struct {
	pool     *pgxpool.Pool
	tasks    pipelineTaskEnqueuer
	registry *coreRegistry
	// decider is the admission decision point consulted before the runner mutates a
	// CR's state. Nil is the legacy path: no decision, no extra read, no behaviour
	// change. Production leaves it nil until Gate3 approves the wiring, so the nil
	// and non-nil runs can be compared instead of claiming identical machine code.
	decider AdmissionDecider
	// afterCommit is a test seam: it runs after the write transaction commits
	// and releases its connection, before any coordination/dispatch. Production
	// leaves it nil.
	afterCommit func()
}

// RunnerOptions carries the seams that stay nil in production.
type RunnerOptions struct {
	// AdmissionDecider, when set, gates the runner's state mutations. See Runner.decider.
	AdmissionDecider AdmissionDecider
}

func NewRunner(pool *pgxpool.Pool, bus *events.Bus, tasks pipelineTaskEnqueuer) (*Runner, error) {
	return NewRunnerWithOptions(pool, bus, tasks, RunnerOptions{})
}

func NewRunnerWithOptions(pool *pgxpool.Pool, _ *events.Bus, tasks pipelineTaskEnqueuer, opts RunnerOptions) (*Runner, error) {
	registry, err := parseCoreRegistry()
	if err != nil {
		return nil, err
	}
	return &Runner{pool: pool, tasks: tasks, registry: registry, decider: opts.AdmissionDecider}, nil
}

type StartArchitectureInput struct {
	WorkspaceID pgtype.UUID
	AgentID     pgtype.UUID
	TaskID      pgtype.UUID
	UserID      pgtype.UUID
	CrID        string
	TechContext string
}

type activeRun struct {
	ID               pgtype.UUID
	WorkspaceID      pgtype.UUID
	CRID             string
	ExecutionContext json.RawMessage
	Inputs           json.RawMessage
}

func (r *Runner) StartArchitecture(ctx context.Context, in StartArchitectureInput) (pgtype.UUID, bool, error) {
	if !in.WorkspaceID.Valid || !in.AgentID.Valid || !in.TaskID.Valid || !in.UserID.Valid || !CRIDPattern.MatchString(in.CrID) {
		return pgtype.UUID{}, false, errCode(RunnerErrAuthorityMismatch, "invalid bound IDs or CR ID")
	}
	if len([]byte(in.TechContext)) > maxTechContextBytes {
		return pgtype.UUID{}, false, errCode(RunnerErrContractInvalid, "tech_context exceeds 16 KiB")
	}
	var crStatus string
	var needsReconcile bool
	err := r.pool.QueryRow(ctx, `SELECT status, needs_reconcile FROM cr WHERE workspace_id = $1 AND cr_id = $2`, in.WorkspaceID, in.CrID).Scan(&crStatus, &needsReconcile)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && (crStatus != "requirement-approved" || needsReconcile)) {
		return pgtype.UUID{}, false, errCode(RunnerErrCRNotReady, "CR projection not ready")
	}
	if err != nil {
		return pgtype.UUID{}, false, err
	}
	if err := r.checkSourceTask(ctx, in.WorkspaceID, in.AgentID, in.TaskID, in.CrID); err != nil {
		return pgtype.UUID{}, false, err
	}
	execCtx, err := json.Marshal(map[string]any{
		"runner": runnerSchema, "template_digest": r.registry.Digest,
		"pipeline_owner": r.registry.PipelineOwner, "executor_agent_id": in.AgentID.String(), "source_task_id": in.TaskID.String(),
	})
	if err != nil {
		return pgtype.UUID{}, false, err
	}
	inputs, err := json.Marshal(map[string]any{"cr_id": in.CrID, "tech_context": in.TechContext})
	if err != nil {
		return pgtype.UUID{}, false, err
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return pgtype.UUID{}, false, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	runID, changed, err := r.upsertRunTx(ctx, tx, in.WorkspaceID, in.CrID, in.UserID, PipelineIDs.ArchitectureDesign, inputs, execCtx)
	if err != nil {
		return pgtype.UUID{}, false, err
	}
	if err := tx.Commit(ctx); err != nil {
		return pgtype.UUID{}, false, err
	}
	if r.afterCommit != nil {
		r.afterCommit()
	}
	if err := r.Reconcile(ctx, in.WorkspaceID, in.CrID); err != nil {
		return runID, changed, err
	}
	return runID, changed, nil
}

// ensureArchitectureRereviewRun is the controlled entry for the existing
// tech-design-review-pending status. It upgrades a projector-created run (or
// opens the missing one) with the same Runner context/digest StartArchitecture
// writes, so the first executable node is review-tech-design rather than a
// second PRD writer.
func (r *Runner) ensureArchitectureRereviewRun(ctx context.Context, workspaceID pgtype.UUID, crID string) (bool, error) {
	var status string
	if err := r.pool.QueryRow(ctx, `SELECT status FROM cr WHERE workspace_id=$1 AND cr_id=$2`, workspaceID, crID).Scan(&status); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	if status != "tech-design-review-pending" {
		return false, nil
	}
	var sourceTask, sourceAgent, userID pgtype.UUID
	err := r.pool.QueryRow(ctx, `
		SELECT t.id,t.agent_id,r.started_by
		FROM pipeline_run r
		JOIN LATERAL (SELECT id,agent_id FROM agent_task_queue WHERE cr_id=r.cr_id AND status='completed' ORDER BY created_at DESC LIMIT 1) t ON true
		WHERE r.workspace_id=$1 AND r.cr_id=$2 AND r.pipeline_id=$3
		ORDER BY r.created_at DESC LIMIT 1`, workspaceID, crID, PipelineIDs.CodeImplementation).Scan(&sourceTask, &sourceAgent, &userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, errCode(RunnerErrAuthorityMismatch, "tech-design re-review has no completed source task")
	}
	if err != nil {
		return false, err
	}
	execCtx, err := json.Marshal(map[string]any{
		"runner": runnerSchema, "template_digest": r.registry.Digest,
		"pipeline_owner": r.registry.PipelineOwner, "executor_agent_id": sourceAgent.String(),
		"source_task_id": sourceTask.String(), "architecture_rereview": true,
	})
	if err != nil {
		return false, err
	}
	inputs, err := json.Marshal(map[string]any{"cr_id": crID, "tech_context": ""})
	if err != nil {
		return false, err
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return false, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, _, err := r.upsertRunTx(ctx, tx, workspaceID, crID, userID, PipelineIDs.ArchitectureDesign, inputs, execCtx); err != nil {
		return false, err
	}
	if err := tx.Commit(ctx); err != nil {
		return false, err
	}
	return true, nil
}

// Reconcile serializes on a PostgreSQL advisory lock derived from the run ID.
// Every wake source uses this method; partial unique indexes remain the
// cross-process crash-window backstop for run and task creation.
func (r *Runner) Reconcile(ctx context.Context, workspaceID pgtype.UUID, crID string) error {
	// AIFIRST: AIFI-45 (SC-RUN-003) — "waiting for admission" is a completed wake, not a
	// failed one. Every internal stop is an error return, so the translation lives here.
	return admissionSettled(r.reconcile(ctx, workspaceID, crID))
}

func (r *Runner) reconcile(ctx context.Context, workspaceID pgtype.UUID, crID string) error {
	if _, err := r.findActiveWritebackRun(ctx, workspaceID, crID); err == nil {
		return r.reconcileWriteback(ctx, workspaceID, crID)
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	run, err := r.findActiveRun(ctx, workspaceID, crID)
	if errors.Is(err, pgx.ErrNoRows) {
		started, serr := r.ensureArchitectureRereviewRun(ctx, workspaceID, crID)
		if serr != nil || !started {
			return serr
		}
		run, err = r.findActiveRun(ctx, workspaceID, crID)
	}
	if err != nil {
		return err
	}
	lockConn, err := r.pool.Acquire(ctx)
	if err != nil {
		return err
	}
	defer lockConn.Release()
	if _, err := lockConn.Exec(ctx, `SELECT pg_advisory_lock(hashtextextended($1, 0))`, run.ID.String()); err != nil {
		return err
	}
	defer func() {
		_, _ = lockConn.Exec(context.Background(), `SELECT pg_advisory_unlock(hashtextextended($1, 0))`, run.ID.String())
	}()

	run, err = r.findActiveRun(ctx, workspaceID, crID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	if err := r.checkDigest(ctx, run); err != nil {
		return err
	}
	return r.reconcileLocked(ctx, run)
}

func architectureRereview(run activeRun) bool {
	var m map[string]any
	return json.Unmarshal(run.ExecutionContext, &m) == nil && m["architecture_rereview"] == true
}

func (r *Runner) reconcileLocked(ctx context.Context, run activeRun) error {
	writeNode, reviewNode, humanNode, approveNode := r.registry.Pipeline.Nodes[0], r.registry.Pipeline.Nodes[1], r.registry.Pipeline.Nodes[2], r.registry.Pipeline.Nodes[3]
	maxAttempts := reviewNode.ReviewLoop.MaxAttempts

	for attempt := 1; attempt <= maxAttempts; attempt++ {
		status, err := r.crStatus(ctx, run.WorkspaceID, run.CRID)
		if err != nil {
			return err
		}
		rereview := architectureRereview(run)
		var complete, stop bool
		if rereview && attempt == 1 {
			if err := r.markNode(ctx, run.ID, writeNode, 1, "passed"); err != nil {
				return err
			}
		} else {
			var err error
			complete, stop, err = r.reconcileSkillTaskFor(ctx, run, writeNode, 1, attempt, PipelineIDs.ArchitectureDesign, nodeNeedsArchitectureFeedback(writeNode), r.registry)
			if err != nil || stop {
				return err
			}
			if !complete {
				return r.waitAuthority(ctx, run.ID, writeNode, attempt)
			}
		}
		writeReady := status == "tech-design-review-pending" || status == "tech-design-reviewed"
		approvalRejected := false
		if status == "tech-designing" {
			decision, _, delivered, approvalErr := r.deliveredTechApproval(ctx, run.WorkspaceID, run.CRID)
			if approvalErr != nil {
				return approvalErr
			}
			approvalRejected = delivered && decision == "reject"
		}
		if !writeReady && status == "tech-designing" {
			// After a canonical block the CR intentionally returns to designing;
			// allow the completed prior round to replay so later attempts remain
			// reachable on every wake, not only in the first reconcile call.
			if prior, evidenceErr := r.reviewEvidence(ctx, run.ID, reviewNode.ID, attempt); evidenceErr == nil {
				writeReady = prior.Verdict == "block" && prior.Attempt == attempt && len(prior.Blockers) > 0 && prior.SubjectSHA256 != "" && prior.ReviewedAt != ""
			}
			// approve-tech-design applies a signed reject by rolling the CR back
			// to designing. Preserve reachability of node 4 so that business
			// result can terminate this run explicitly.
			writeReady = writeReady || approvalRejected
		}
		if !writeReady {
			return r.waitAuthority(ctx, run.ID, writeNode, attempt)
		}
		if err := r.markNode(ctx, run.ID, writeNode, attempt, "passed"); err != nil {
			return err
		}

		complete, stop, err = r.reconcileSkillTaskFor(ctx, run, reviewNode, 2, attempt, PipelineIDs.ArchitectureDesign, nodeNeedsArchitectureFeedback(reviewNode), r.registry)
		if err != nil || stop {
			return err
		}
		if !complete {
			return nil
		}
		evidence, err := r.reviewEvidence(ctx, run.ID, reviewNode.ID, attempt)
		if err != nil {
			return err
		}
		status, err = r.crStatus(ctx, run.WorkspaceID, run.CRID)
		if err != nil {
			return err
		}
		switch evidence.Verdict {
		case "block":
			if !conclusiveReviewEvidence(evidence, attempt) {
				// AIFI-63 Package E2: an incomplete pass/block is a delivery gap, not a
				// pending well-formed record — same terminal as the default branch
				// once the projection is settled (RUNNER_REVIEW_DELIVERY_MISSING).
				return r.reviewDeliveryGap(ctx, run, reviewNode, attempt)
			}
			if status != "tech-designing" && !rereview {
				replayStarted, replayErr := r.nodeAttemptExists(ctx, run.ID, writeNode.ID, attempt+1)
				if replayErr != nil {
					return replayErr
				}
				if !replayStarted {
					return r.waitAuthority(ctx, run.ID, reviewNode, attempt)
				}
			}
			if err := r.markNode(ctx, run.ID, reviewNode, attempt, "blocked"); err != nil {
				return err
			}
			if attempt == maxAttempts {
				return r.failRun(ctx, run.ID, RunnerErrLoopExhausted)
			}
			continue
		case "pass":
			if !conclusiveReviewEvidence(evidence, attempt) {
				// AIFI-63 Package E2: an incomplete pass/block is a delivery gap, not a
				// pending well-formed record — same terminal as the default branch
				// once the projection is settled (RUNNER_REVIEW_DELIVERY_MISSING).
				return r.reviewDeliveryGap(ctx, run, reviewNode, attempt)
			}
			if status != "tech-design-review-pending" && status != "tech-design-reviewed" && !approvalRejected {
				return r.waitAuthority(ctx, run.ID, reviewNode, attempt)
			}
			if err := r.markNode(ctx, run.ID, reviewNode, attempt, "passed"); err != nil {
				return err
			}
			return r.reconcileApproval(ctx, run, humanNode, approveNode)
		default:
			return r.reviewDeliveryGap(ctx, run, reviewNode, attempt)
		}
	}
	return r.failRun(ctx, run.ID, RunnerErrLoopExhausted)
}

func (r *Runner) reconcileApproval(ctx context.Context, run activeRun, human, approve coreNode) error {
	humanID, err := r.ensureNodeRow(ctx, run.ID, human, 3, 1)
	if err != nil {
		return err
	}
	decision, approvalID, delivered, err := r.deliveredTechApproval(ctx, run.WorkspaceID, run.CRID)
	if err != nil {
		return err
	}
	if !delivered {
		_, err = r.pool.Exec(ctx, `UPDATE pipeline_run SET status='waiting_approval' WHERE id=$1 AND status='running'`, run.ID)
		return err
	}
	if _, err = r.passHumanApprovalNode(ctx, run.ID, humanID, approvalID); err != nil {
		return err
	}
	_, _ = r.pool.Exec(ctx, `UPDATE pipeline_run SET status='running' WHERE id=$1 AND status='waiting_approval'`, run.ID)

	complete, stop, err := r.reconcileSkillTaskFor(ctx, run, approve, 4, 1, PipelineIDs.ArchitectureDesign, nodeNeedsArchitectureFeedback(approve), r.registry)
	if err != nil || stop {
		// Waiting for admission outranks every other classification here. Without this the
		// reject-rollback branch below turns a pending authorization into a persisted
		// RUNNER_TASK_FAILED: the run is then wrong for good, and no entry point can settle
		// it back to a wait. A revoke landing between the human gate and the approve
		// dispatch is exactly the window that reaches this.
		if errors.Is(err, errAdmissionWaiting) {
			return err
		}
		if err != nil && strings.Contains(err.Error(), RunnerErrApprovalRejected) {
			return err
		}
		if decision == "reject" {
			status, serr := r.crStatus(ctx, run.WorkspaceID, run.CRID)
			if serr == nil && status == "tech-designing" {
				return r.failRun(ctx, run.ID, RunnerErrTaskFailed)
			}
		}
		return err
	}
	if !complete {
		return nil
	}
	status, err := r.crStatus(ctx, run.WorkspaceID, run.CRID)
	if err != nil {
		return err
	}
	if decision == "reject" {
		if status != "tech-designing" {
			return r.waitAuthority(ctx, run.ID, approve, 1)
		}
		return r.failRun(ctx, run.ID, RunnerErrApprovalRejected)
	}
	if decision != "approve" || status != "tech-design-reviewed" {
		return r.waitAuthority(ctx, run.ID, approve, 1)
	}
	if err := r.markNode(ctx, run.ID, approve, 1, "passed"); err != nil {
		return err
	}
	// CR-2026-066 retires the post-approval checkpoint node: the stage-terminal
	// publish now happens inside the review PASS branch of the reviewer's
	// review-tech-design task, so approve-tech-design is the last Core node.
	_, err = r.pool.Exec(ctx, `UPDATE pipeline_run SET status='completed', completed_at=now() WHERE id=$1 AND status IN ('running','waiting_approval')`, run.ID)
	return err
}

func approvalStageForNode(ref string) (stage, rolledBackTo string, ok bool) {
	switch ref {
	case "approve-tech-design":
		return "tech-design", "tech-designing", true
	case "approve-code":
		return "code", "developing", true
	case "approve-requirement":
		return "requirement", "drafting", true
	default:
		return "", "", false
	}
}

// approvalRejectRolledBack distinguishes a business decline from a technical
// task failure. The tool has already committed the rollback; the Runner must
// stop, not retry or rewrite the CR.
func (r *Runner) approvalRejectRolledBack(ctx context.Context, run activeRun, node coreNode) (bool, error) {
	stage, rolledBackTo, ok := approvalStageForNode(node.Ref)
	if !ok {
		return false, nil
	}
	var decision string
	err := r.pool.QueryRow(ctx, `
		SELECT decision FROM approval_record
		WHERE workspace_id=$1 AND cr_id=$2 AND stage=$3 AND delivered_at IS NOT NULL
		ORDER BY created_at DESC LIMIT 1`, run.WorkspaceID, run.CRID, stage).Scan(&decision)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	var status string
	if err := r.pool.QueryRow(ctx, `SELECT status FROM cr WHERE workspace_id=$1 AND cr_id=$2`, run.WorkspaceID, run.CRID).Scan(&status); err != nil {
		return false, err
	}
	return decision == "reject" && status == rolledBackTo, nil
}

// reconcileSkillTask returns complete=true only for a completed Agent task.
// stop=true means it enqueued/waits on an active task, so this wake is done.
func (r *Runner) reconcileSkillTask(ctx context.Context, run activeRun, node coreNode, seq, attempt int) (complete, stop bool, err error) {
	return r.reconcileSkillTaskFor(ctx, run, node, seq, attempt, PipelineIDs.ArchitectureDesign, nodeNeedsArchitectureFeedback(node), r.registry)
}

func nodeNeedsArchitectureFeedback(node coreNode) bool {
	return node.Ref == "write-tech-design" || node.Ref == "review-tech-design"
}

func (r *Runner) reconcileSkillTaskFor(ctx context.Context, run activeRun, node coreNode, seq, attempt int, pipelineID string, injectFeedback bool, registry *coreRegistry) (complete, stop bool, err error) {
	nodeRunID, err := r.ensureNodeRow(ctx, run.ID, node, seq, attempt)
	if err != nil {
		return false, false, err
	}
	state, exists, err := r.latestTaskState(ctx, nodeRunID)
	if err != nil {
		return false, false, err
	}
	if !exists {
		return false, true, r.enqueueNodeFor(ctx, run, node, nodeRunID, attempt, pipelineID, injectFeedback, registry)
	}
	switch state {
	case "queued", "deferred", "dispatched", "waiting_local_directory", "running":
		return false, true, nil
	case "completed":
		if err := r.checkConsumedReviewIndependence(ctx, run.ID, attempt, registry, node, nodeRunID); err != nil {
			return false, true, err
		}
		return true, false, nil
	case "failed", "cancelled":
		// AIFIRST: M41b (TC-MRECOVERY-001/007) — judgement order. A failed
		// attempt row is not yet a failed run:
		//  1. delivered business result: a signed rejection that already rolled
		//     the CR back is a business outcome, not RUNNER_TASK_FAILED;
		//  2. a conclusive canonical review record for this round (a verdict
		//     projected by the review event after the process died — the M28
		//     late-delivery shape) is authoritative, so the walk continues by
		//     that verdict instead of failing the run;
		//  3. another attempt of the SAME node-run already in flight (the
		//     service-created queued/deferred retry child) owns the outcome, so
		//     this wake waits instead of failing the run or enqueuing a second
		//     child;
		//  4. only then is the round's failure terminal for the run.
		rejected, err := r.approvalRejectRolledBack(ctx, run, node)
		if err != nil {
			return false, true, err
		}
		if rejected {
			return false, true, errCode(RunnerErrApprovalRejected, "approval was declined and the CR rolled back")
		}
		businessResult, err := r.conclusiveReviewResult(ctx, run.ID, node.ID, attempt)
		if err != nil {
			return false, true, err
		}
		if businessResult {
			return true, false, nil
		}
		inFlight, err := r.nodeTaskInFlight(ctx, nodeRunID)
		if err != nil {
			return false, true, err
		}
		if inFlight {
			return false, true, nil
		}
		return false, true, r.failRun(ctx, run.ID, RunnerErrTaskFailed)
	default:
		return false, true, r.failRun(ctx, run.ID, RunnerErrAuthorityMismatch)
	}
}

func (r *Runner) enqueueNode(ctx context.Context, run activeRun, node coreNode, nodeRunID pgtype.UUID, attempt int) error {
	return r.enqueueNodeFor(ctx, run, node, nodeRunID, attempt, PipelineIDs.ArchitectureDesign, nodeNeedsArchitectureFeedback(node), r.registry)
}

func (r *Runner) enqueueNodeFor(ctx context.Context, run activeRun, node coreNode, nodeRunID pgtype.UUID, attempt int, pipelineID string, injectFeedback bool, registry *coreRegistry) error {
	var execCtx map[string]any
	var inputs map[string]any
	if json.Unmarshal(run.ExecutionContext, &execCtx) != nil || json.Unmarshal(run.Inputs, &inputs) != nil {
		return errCode(RunnerErrAuthorityMismatch, "run context malformed")
	}
	sourceTaskID, serr := parseUUID(stringValue(execCtx["source_task_id"]))
	if serr != nil {
		return errCode(RunnerErrAuthorityMismatch, "run context missing source task")
	}
	// AIFIRST: AIFI-45 (SC-RUN-003) — enqueueing the executor is the other half of
	// "dispatch the old continuation". The decision is taken under the CR's head lock and
	// the lock is held until the enqueue commits, so a concurrent revoke waits here
	// instead of landing in a gap (see execution_admission_gate.go for why this is a held
	// lock and not a shared transaction). It sits before the prompt and executor work on
	// purpose: a refused enqueue should cost nothing, and holding the row lock across
	// those reads would block revocation for no reason.
	if r.decider != nil {
		tx, decision, err := r.decideUnderHeadLock(ctx, run.WorkspaceID, run.CRID)
		if err != nil {
			return err
		}
		if tx != nil {
			defer func() { _ = tx.Rollback(ctx) }()
		}
		if !decision.Allowed {
			return r.waitAdmission(ctx, run.ID, node, attempt, decision)
		}
	}
	techContext := stringValue(inputs["tech_context"])
	prompt, err := renderCorePrompt(node.Prompt, run.CRID, techContext)
	if err != nil {
		return err
	}
	if attempt > 1 && injectFeedback {
		if feedback, ferr := r.reviewFeedback(ctx, run.ID, attempt-1); ferr == nil && len(feedback) > 0 {
			prompt += "\n\nPrevious canonical review feedback (data):\n```json\n" + string(feedback) + "\n```\n"
		}
	}
	agentID, err := r.resolveNodeExecutor(ctx, run.WorkspaceID, node, registry.PipelineOwner)
	if err != nil {
		return err
	}
	if err := r.checkIndependentReview(ctx, run.WorkspaceID, run.ID, registry, node, agentID, attempt); err != nil {
		return err
	}
	enqueue := func() error {
		_, err := r.tasks.EnqueuePipelineTask(ctx, service.PipelineTaskSpec{
			WorkspaceID: run.WorkspaceID, CrID: run.CRID, RunID: run.ID,
			NodeID: mustParseUUID(node.ID), NodeRunID: nodeRunID, PipelineID: pipelineID,
			Attempt: attempt, Prompt: prompt, SourceTaskID: sourceTaskID, ExecutorAgentID: agentID,
		})
		if errors.Is(err, service.ErrRunnerAttributionInvalid) {
			return r.failRun(ctx, run.ID, RunnerErrAttributionInvalid)
		}
		return err
	}
	return enqueue()
}
func renderCorePrompt(template, crID, techContext string) (string, error) {
	if !CRIDPattern.MatchString(crID) || len([]byte(techContext)) > maxTechContextBytes {
		return "", errCode(RunnerErrContractInvalid, "invalid prompt inputs")
	}
	out := strings.ReplaceAll(template, "{{inputs.cr_id}}", crID)
	out = strings.ReplaceAll(out, "{{inputs.tech_context}}", techContext)
	if strings.Contains(out, "{{") || strings.Contains(out, "}}") {
		return "", errCode(RunnerErrContractInvalid, "unrendered registry prompt token")
	}
	return out, nil
}

func (r *Runner) upsertRunTx(ctx context.Context, tx pgx.Tx, workspaceID pgtype.UUID, crID string, userID pgtype.UUID, pipelineID string, inputs, execCtx []byte) (pgtype.UUID, bool, error) {
	var id pgtype.UUID
	err := tx.QueryRow(ctx, `
		INSERT INTO pipeline_run (workspace_id,pipeline_id,cr_id,status,started_by,inputs,execution_context)
		VALUES ($1,$2,$3,'running',$4,$5,$6) ON CONFLICT DO NOTHING RETURNING id`,
		workspaceID, pipelineID, crID, userID, inputs, execCtx).Scan(&id)
	if err == nil {
		return id, true, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return pgtype.UUID{}, false, err
	}
	run, err := r.findActiveRunTx(ctx, tx, workspaceID, crID, pipelineID)
	if err != nil {
		return pgtype.UUID{}, false, err
	}
	var changed bool
	err = tx.QueryRow(ctx, `
		UPDATE pipeline_run SET inputs=$2, execution_context=$3
		WHERE id=$1 AND COALESCE(execution_context->>'runner','')=''
		RETURNING true`, run.ID, inputs, execCtx).Scan(&changed)
	if errors.Is(err, pgx.ErrNoRows) {
		return run.ID, false, nil
	}
	return run.ID, changed, err
}

func (r *Runner) upsertRun(ctx context.Context, workspaceID pgtype.UUID, crID string, userID pgtype.UUID, inputs, execCtx []byte) (pgtype.UUID, bool, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return pgtype.UUID{}, false, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	id, changed, err := r.upsertRunTx(ctx, tx, workspaceID, crID, userID, PipelineIDs.ArchitectureDesign, inputs, execCtx)
	if err != nil {
		return pgtype.UUID{}, false, err
	}
	if err := tx.Commit(ctx); err != nil {
		return pgtype.UUID{}, false, err
	}
	return id, changed, nil
}

func (r *Runner) findActiveRun(ctx context.Context, workspaceID pgtype.UUID, crID string) (activeRun, error) {
	var run activeRun
	err := r.pool.QueryRow(ctx, `
		SELECT id,workspace_id,cr_id,execution_context,inputs FROM pipeline_run
		WHERE workspace_id=$1 AND cr_id=$2 AND pipeline_id=$3 AND status IN ('running','waiting_approval')
		ORDER BY created_at DESC LIMIT 1`, workspaceID, crID, PipelineIDs.ArchitectureDesign).
		Scan(&run.ID, &run.WorkspaceID, &run.CRID, &run.ExecutionContext, &run.Inputs)
	return run, err
}

func (r *Runner) findActiveRunTx(ctx context.Context, tx pgx.Tx, workspaceID pgtype.UUID, crID string, pipelineID string) (activeRun, error) {
	var run activeRun
	err := tx.QueryRow(ctx, `
		SELECT id,workspace_id,cr_id,execution_context,inputs FROM pipeline_run
		WHERE workspace_id=$1 AND cr_id=$2 AND pipeline_id=$3 AND status IN ('running','waiting_approval')
		ORDER BY created_at DESC LIMIT 1`, workspaceID, crID, pipelineID).
		Scan(&run.ID, &run.WorkspaceID, &run.CRID, &run.ExecutionContext, &run.Inputs)
	return run, err
}

func (r *Runner) checkDigest(_ context.Context, run activeRun) error {
	var m map[string]any
	if json.Unmarshal(run.ExecutionContext, &m) != nil || stringValue(m["runner"]) != runnerSchema || stringValue(m["template_digest"]) != r.registry.Digest {
		// Registry drift is a deployment mismatch, not a terminal business
		// result. Keep the run active so rolling back to its digest resumes it.
		return errCode(RunnerErrTemplateDigestMismatch, "active run registry digest does not match this deployment")
	}
	return nil
}

func (r *Runner) checkSourceTask(ctx context.Context, workspaceID, agentID, taskID pgtype.UUID, crID string) error {
	var sourceCr pgtype.Text
	var sourceIssueID, sourceProjectID pgtype.UUID
	var issueRowID, issueWorkspaceID, issueProjectID pgtype.UUID
	var issueProjectRowID, issueProjectWorkspaceID pgtype.UUID
	var projectRowID, projectWorkspaceID pgtype.UUID
	var targetCRID, crShellIssueID pgtype.UUID
	err := r.pool.QueryRow(ctx, `
		SELECT t.cr_id, t.issue_id, t.project_id,
		       i.id, i.workspace_id, i.project_id,
		       ip.id, ip.workspace_id,
		       p.id, p.workspace_id,
		       c.id, c.shell_issue_id
		FROM agent_task_queue t
		JOIN agent a ON a.id=t.agent_id
		LEFT JOIN issue i ON i.id=t.issue_id
		LEFT JOIN project ip ON ip.id=i.project_id
		LEFT JOIN project p ON p.id=t.project_id
		LEFT JOIN cr c ON c.workspace_id=a.workspace_id AND c.cr_id=$4
		WHERE t.id=$1 AND t.agent_id=$2 AND a.workspace_id=$3`, taskID, agentID, workspaceID, crID).
		Scan(&sourceCr, &sourceIssueID, &sourceProjectID, &issueRowID, &issueWorkspaceID, &issueProjectID, &issueProjectRowID, &issueProjectWorkspaceID, &projectRowID, &projectWorkspaceID, &targetCRID, &crShellIssueID)
	if errors.Is(err, pgx.ErrNoRows) {
		return errCode(RunnerErrAttributionInvalid, "source task/agent/workspace mismatch")
	}
	if err != nil {
		return err
	}
	if !targetCRID.Valid {
		return errCode(RunnerErrAttributionInvalid, "target CR not found in source workspace")
	}
	if sourceCr.Valid && sourceCr.String != crID {
		return errCode(RunnerErrAttributionInvalid, "source task belongs to a different CR")
	}
	if sourceIssueID.Valid {
		if !issueRowID.Valid || issueWorkspaceID != workspaceID {
			return errCode(RunnerErrAttributionInvalid, "source issue is missing or in another workspace")
		}
		if sourceProjectID.Valid {
			if !issueProjectID.Valid || sourceProjectID != issueProjectID {
				return errCode(RunnerErrAttributionInvalid, "source task project does not match its issue")
			}
		}
		if issueProjectID.Valid && (!issueProjectRowID.Valid || issueProjectWorkspaceID != workspaceID) {
			return errCode(RunnerErrAttributionInvalid, "issue project is missing or in another workspace")
		}
	} else if crShellIssueID.Valid {
		return errCode(RunnerErrAttributionInvalid, "source task has no issue for a bound CR")
	}
	if sourceProjectID.Valid {
		if !projectRowID.Valid || projectWorkspaceID != workspaceID {
			return errCode(RunnerErrAttributionInvalid, "source project is missing or in another workspace")
		}
	}
	if crShellIssueID.Valid && sourceIssueID.Valid && crShellIssueID != sourceIssueID {
		return errCode(RunnerErrAttributionInvalid, "source issue does not match the target CR")
	}
	return nil
}

func (r *Runner) checkExecutorAgent(ctx context.Context, workspaceID, agentID pgtype.UUID) error {
	var ready bool
	err := r.pool.QueryRow(ctx, `SELECT archived_at IS NULL AND runtime_id IS NOT NULL FROM agent WHERE id=$1 AND workspace_id=$2`, agentID, workspaceID).Scan(&ready)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && !ready) {
		return errCode(RunnerErrAgentNotReady, "executor agent missing, archived, or runtime-unbound")
	}
	return err
}

// resolveNodeExecutor turns one node's registry actor key into the real agent
// UUID that must run it. The node's own declaration is the only source: the
// caller, a previous execution_context.executor_agent_id, the node owner and a
// skill owner are never fallbacks. A human approval node has no executor and is
// rejected rather than looked up.
func (r *Runner) resolveNodeExecutor(ctx context.Context, workspaceID pgtype.UUID, node coreNode, pipelineOwner string) (pgtype.UUID, error) {
	if node.Kind == "human_approval" {
		return pgtype.UUID{}, errCode(RunnerErrNoExecutorForStage, "human approval node does not dispatch an executor")
	}
	key := node.Executor
	if key == "" {
		key = pipelineOwner
	}
	if key == "" {
		return pgtype.UUID{}, errCode(RunnerErrAgentNotReady, "node has no registry executor")
	}
	agentID, err := r.agentByName(ctx, workspaceID, key)
	if err != nil {
		return pgtype.UUID{}, err
	}
	if err := r.checkExecutorAgent(ctx, workspaceID, agentID); err != nil {
		return pgtype.UUID{}, err
	}
	if node.Ref != "" {
		if err := r.checkRequirementSkills(ctx, agentID, node.Ref); err != nil {
			return pgtype.UUID{}, err
		}
	}
	return agentID, nil
}

func reviewAuthorNode(registry *coreRegistry, reviewNode coreNode) (*coreNode, error) {
	if reviewNode.ReviewLoop == nil {
		return nil, errCode(RunnerErrContractInvalid, "independent review node has no reviewLoop")
	}
	var author *coreNode
	if reviewNode.ReviewLoop.RepairNodeID != "" {
		for i := range registry.Pipeline.Nodes {
			if registry.Pipeline.Nodes[i].ID == reviewNode.ReviewLoop.RepairNodeID {
				author = &registry.Pipeline.Nodes[i]
				break
			}
		}
	} else if reviewNode.ReviewLoop.RepairRef != "" {
		for i := range registry.Pipeline.Nodes {
			if registry.Pipeline.Nodes[i].Ref == reviewNode.ReviewLoop.RepairRef {
				if author != nil {
					return nil, errCode(RunnerErrContractInvalid, "independent review repair ref is ambiguous")
				}
				author = &registry.Pipeline.Nodes[i]
			}
		}
	}
	if author == nil || author.Kind == "human_approval" {
		return nil, errCode(RunnerErrContractInvalid, "independent review has no non-human author node")
	}
	return author, nil
}

// selectedAuthorTask reads the author node-run for the same run and business
// attempt, then the same newest queue record selectedTask already uses. It
// returns ok only when that record is completed, i.e. real execution evidence;
// an absent node-run/task is not evidence and stays allowed for existing
// adoption/resume paths.
func (r *Runner) selectedAuthorTask(ctx context.Context, runID pgtype.UUID, attempt int, registry *coreRegistry, reviewNode coreNode) (selectedPipelineTask, bool, error) {
	author, err := reviewAuthorNode(registry, reviewNode)
	if err != nil {
		return selectedPipelineTask{}, false, err
	}
	var nodeRunID pgtype.UUID
	err = r.pool.QueryRow(ctx, `SELECT id FROM pipeline_node_run WHERE run_id=$1 AND node_id=$2 AND attempt=$3`, runID, author.ID, attempt).Scan(&nodeRunID)
	if errors.Is(err, pgx.ErrNoRows) {
		return selectedPipelineTask{}, false, nil
	}
	if err != nil {
		return selectedPipelineTask{}, false, err
	}
	task, ok, err := r.selectedTask(ctx, nodeRunID)
	if err != nil || !ok || task.Status != "completed" {
		return selectedPipelineTask{}, false, err
	}
	return task, true, nil
}

// checkIndependentReview refuses an independent review node whose resolved
// executor is the same real agent as the author node the reviewLoop names. The
// author is located from the declared repairNodeId/repairRef only; a self-test
// loop on a non-review ref is not treated as independent review. Both sides are
// resolved through the one node-executor path above, so this compares UUIDs,
// not actor-key strings, and validates both nodes' runtime/skill first. In
// addition, if this run already has completed author-task evidence, the same
// selected record's AgentID is compared with the new reviewer.
func (r *Runner) checkIndependentReview(ctx context.Context, workspaceID, runID pgtype.UUID, registry *coreRegistry, reviewNode coreNode, reviewerID pgtype.UUID, attempt int) error {
	if !strings.HasPrefix(reviewNode.Ref, "review-") {
		return nil
	}
	author, err := reviewAuthorNode(registry, reviewNode)
	if err != nil {
		return err
	}
	authorID, err := r.resolveNodeExecutor(ctx, workspaceID, *author, registry.PipelineOwner)
	if err != nil {
		return err
	}
	if authorID.String() == reviewerID.String() {
		return errCode(RunnerErrAuthorityMismatch, "review node resolves to its author agent")
	}
	authorTask, ok, err := r.selectedAuthorTask(ctx, runID, attempt, registry, reviewNode)
	if err != nil {
		return err
	}
	if ok && authorTask.AgentID.Valid && authorTask.AgentID.String() == reviewerID.String() {
		return errCode(RunnerErrAuthorityMismatch, "review node matches the completed author execution")
	}
	return nil
}

// checkConsumedReviewIndependence stops consuming a completed review task when
// that exact selected review record and the same selected completed author
// record name the same executor. It reads stored task rows only; a current agent
// rename or re-resolution cannot reassign or reject an already independent task.
func (r *Runner) checkConsumedReviewIndependence(ctx context.Context, runID pgtype.UUID, attempt int, registry *coreRegistry, reviewNode coreNode, reviewNodeRunID pgtype.UUID) error {
	if !strings.HasPrefix(reviewNode.Ref, "review-") {
		return nil
	}
	reviewTask, ok, err := r.selectedTask(ctx, reviewNodeRunID)
	if err != nil || !ok || reviewTask.Status != "completed" {
		return err
	}
	authorTask, ok, err := r.selectedAuthorTask(ctx, runID, attempt, registry, reviewNode)
	if err != nil || !ok {
		return err
	}
	if reviewTask.AgentID.Valid && authorTask.AgentID.Valid && reviewTask.AgentID.String() == authorTask.AgentID.String() {
		return errCode(RunnerErrAuthorityMismatch, "review task was executed by its author agent")
	}
	return nil
}

func (r *Runner) ensureNodeRow(ctx context.Context, runID pgtype.UUID, node coreNode, seq, attempt int) (pgtype.UUID, error) {
	var id pgtype.UUID
	err := r.pool.QueryRow(ctx, `
		INSERT INTO pipeline_node_run (run_id,node_id,ref,kind,seq,status,attempt,started_at)
		VALUES ($1,$2,$3,$4,$5,'running',$6,now())
		ON CONFLICT (run_id,node_id,attempt) DO UPDATE SET started_at=COALESCE(pipeline_node_run.started_at,now())
		RETURNING id`, runID, node.ID, nullIfEmpty(node.Ref), node.Kind, seq, attempt).Scan(&id)
	return id, err
}

func (r *Runner) nodeAttemptExists(ctx context.Context, runID pgtype.UUID, nodeID string, attempt int) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pipeline_node_run WHERE run_id=$1 AND node_id=$2::uuid AND attempt=$3)`, runID, nodeID, attempt).Scan(&exists)
	return exists, err
}

// conclusiveReviewResult reports whether this round already carries a
// conclusive canonical review verdict, whichever task wrote it. Read through
// the same node detail + conclusiveReviewEvidence definition the walk uses, so
// the business result is judged once. A failed review task that had already
// delivered its record is a business outcome (M28 late delivery), not a
// technical failure of the round.
func (r *Runner) conclusiveReviewResult(ctx context.Context, runID pgtype.UUID, nodeID string, attempt int) (bool, error) {
	e, err := r.reviewEvidence(ctx, runID, nodeID, attempt)
	if err != nil {
		return false, err
	}
	return conclusiveReviewEvidence(e, attempt), nil
}

// nodeTaskInFlight reports whether another attempt of this node-run is still
// running or waiting to run. The service creates its retry child on the same
// node-run, so a failed newest row plus a queued/deferred child is a pending
// attempt, not a terminal failure; the runner must wait for that child rather
// than fail the run or create a duplicate.
func (r *Runner) nodeTaskInFlight(ctx context.Context, nodeRunID pgtype.UUID) (bool, error) {
	var inFlight bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM agent_task_queue
			WHERE pipeline_node_run_id=$1
			  AND status IN ('queued','deferred','dispatched','waiting_local_directory','running')
		)`, nodeRunID).Scan(&inFlight)
	return inFlight, err
}

type selectedPipelineTask struct {
	ID      pgtype.UUID
	AgentID pgtype.UUID
	Status  string
}

// selectedTask is the one task record the Runner already treats as current for a
// node-run: the newest row by created_at. Callers that also need the execution
// identity use this view; no second ordering or completed/latest selection is
// introduced.
func (r *Runner) selectedTask(ctx context.Context, nodeRunID pgtype.UUID) (selectedPipelineTask, bool, error) {
	var task selectedPipelineTask
	err := r.pool.QueryRow(ctx, `SELECT id,agent_id,status FROM agent_task_queue WHERE pipeline_node_run_id=$1 ORDER BY created_at DESC LIMIT 1`, nodeRunID).Scan(&task.ID, &task.AgentID, &task.Status)
	if errors.Is(err, pgx.ErrNoRows) {
		return selectedPipelineTask{}, false, nil
	}
	if err != nil {
		return selectedPipelineTask{}, false, err
	}
	return task, true, nil
}

func (r *Runner) latestTaskState(ctx context.Context, nodeRunID pgtype.UUID) (string, bool, error) {
	task, ok, err := r.selectedTask(ctx, nodeRunID)
	if err != nil || !ok {
		return "", ok, err
	}
	return task.Status, true, nil
}

type reviewEvidence struct {
	Verdict       string   `json:"verdict"`
	Blockers      []string `json:"blockers"`
	Attempt       int      `json:"attempt"`
	ReviewedAt    string   `json:"reviewed_at"`
	SubjectSHA256 string   `json:"subject_sha256"`
}

// conclusiveReviewEvidence is the one definition of a verdict the walk will act on:
// it belongs to the round being judged, names the object it reviewed, and carries a
// blocker list shaped the way that verdict requires. Every consumer — the
// architecture walk, the requirement walk, the walk-stop read the manual resume uses,
// and the late-delivery recovery — asks this same question, so a record too malformed
// to act on can never be conclusive in one place and inconclusive in another.
func conclusiveReviewEvidence(ev reviewEvidence, attempt int) bool {
	if ev.Attempt != attempt || ev.SubjectSHA256 == "" || ev.ReviewedAt == "" {
		return false
	}
	switch ev.Verdict {
	case "pass":
		return len(ev.Blockers) == 0
	case "block":
		return len(ev.Blockers) > 0
	default:
		return false
	}
}

func (r *Runner) reviewEvidence(ctx context.Context, runID pgtype.UUID, nodeID string, attempt int) (reviewEvidence, error) {
	var raw json.RawMessage
	err := r.pool.QueryRow(ctx, `SELECT detail FROM pipeline_node_run WHERE run_id=$1 AND node_id=$2 AND attempt=$3`, runID, nodeID, attempt).Scan(&raw)
	if err != nil {
		return reviewEvidence{}, err
	}
	var e reviewEvidence
	if err := json.Unmarshal(raw, &e); err != nil {
		return reviewEvidence{}, err
	}
	return e, nil
}

func (r *Runner) reviewFeedback(ctx context.Context, runID pgtype.UUID, attempt int) (json.RawMessage, error) {
	returnRaw := json.RawMessage{}
	err := r.pool.QueryRow(ctx, `SELECT jsonb_build_object('attempt',attempt,'verdict',detail->'verdict','blockers',detail->'blockers') FROM pipeline_node_run WHERE run_id=$1 AND node_id=$2 AND attempt=$3`, runID, r.registry.Pipeline.Nodes[1].ID, attempt).Scan(&returnRaw)
	return returnRaw, err
}

func (r *Runner) deliveredTechApproval(ctx context.Context, workspaceID pgtype.UUID, crID string) (string, pgtype.UUID, bool, error) {
	var decision string
	var id pgtype.UUID
	err := r.pool.QueryRow(ctx, `
		SELECT decision,id FROM approval_record WHERE workspace_id=$1 AND cr_id=$2 AND stage='tech-design' AND delivered_at IS NOT NULL
		ORDER BY created_at DESC LIMIT 1`, workspaceID, crID).Scan(&decision, &id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", pgtype.UUID{}, false, nil
	}
	return decision, id, err == nil, err
}

func (r *Runner) crStatus(ctx context.Context, workspaceID pgtype.UUID, crID string) (string, error) {
	var status string
	err := r.pool.QueryRow(ctx, `SELECT status FROM cr WHERE workspace_id=$1 AND cr_id=$2`, workspaceID, crID).Scan(&status)
	return status, err
}

func (r *Runner) markNode(ctx context.Context, runID pgtype.UUID, node coreNode, attempt int, status string) error {
	// AIFIRST: AIFI-45 (SC-RUN-003) — "passed" is the advance: it is what completes a
	// business gate. "blocked" is not, and stays ungated so a real block is still
	// recorded while an authorization is pending; refusing to write it would hide the
	// failure instead of the permission.
	if r.decider != nil && status == "passed" {
		return r.markNodeAdmitted(ctx, runID, node, attempt, status)
	}
	_, err := r.pool.Exec(ctx, `UPDATE pipeline_node_run SET status=$4,completed_at=now(),detail=jsonb_set(COALESCE(detail,'{}'),'{runner}',COALESCE(detail->'runner','{}') - 'wait_reason',true) WHERE run_id=$1 AND node_id=$2 AND attempt=$3 AND status NOT IN ('failed','skipped')`, runID, node.ID, attempt, status)
	return err
}

func (r *Runner) waitAuthority(ctx context.Context, runID pgtype.UUID, node coreNode, attempt int) error {
	return r.setRunnerDetail(ctx, runID, node.ID, attempt, map[string]any{"wait_reason": "authority_postcondition"})
}

func (r *Runner) waitEvidence(ctx context.Context, runID pgtype.UUID, node coreNode, attempt int, code string) error {
	return r.setRunnerDetail(ctx, runID, node.ID, attempt, map[string]any{"wait_reason": "review_evidence", "error": map[string]any{"code": code}})
}

// reviewRoundUndelivered is the single definition of "this review round ended with
// no formal delivery": no evidence conclusive for the attempt (AIFI-63 Package E2
// judges with conclusiveReviewEvidence — a present-but-incomplete pass/block is a
// failed delivery, not a pending well-formed one), and the sync layer no longer
// says its own projection is unsettled. Both halves of AIFI-60 read it — the walk's
// failure and the resume's re-dispatch — so the two can never disagree about what
// the round delivered.
func (r *Runner) reviewRoundUndelivered(ctx context.Context, run activeRun, node coreNode, attempt int) (bool, error) {
	evidence, err := r.reviewEvidence(ctx, run.ID, node.ID, attempt)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return false, err
	}
	// AIFI-63 Package E2: conclusive means the record belongs to this attempt,
	// names its subject, and is shaped the way its verdict requires. An
	// incomplete pass (blockers present) or block (blockers absent), a wrong
	// attempt, or a missing subject digest is NOT a delivery to wait on — once
	// the projection is settled the round lands on the visible failure.
	if conclusiveReviewEvidence(evidence, attempt) {
		return false, nil
	}
	behind, err := r.projectionIsBehind(ctx, run.WorkspaceID, run.CRID)
	if err != nil {
		return false, err
	}
	return !behind, nil
}

// reviewDeliveryGap is what a review round whose task ended without a usable
// verdict means, and it is the only place that question is answered.
//
// A task exiting 0 is not proof the review was delivered: the review record
// reaches this projection only through crctl's commit events, so a run can finish
// cleanly having written none. Equally, no verdict here is not proof it will not
// arrive, because that event channel is asynchronous and trails the run by up to
// one collector pass. Parking every such round kept pipelines running forever with
// the only trace inside a JSONB wait_reason nobody surfaces (AIFI-60); failing every
// such round would read an in-flight projection as a missing review. The sync layer
// already records which of the two it is facing, so that is what decides.
//
// The ordering this judgement depends on is enforced where the delivery is made: a
// pipeline task settles its CR root's pending events through the collector before its
// terminal report reaches this server (daemon.settleCREventsForTask), so "the projection
// holds no record" is asked only once the daemon has been emptied into it.
//
// ponytail: a daemon that could not settle — no watched root, unreachable server, a
// rejected ship whose cursor already moved — can still be read as a settled projection
// with nothing in it, and the round then fails visibly. `cr pipeline resume` continues it
// once the verdict arrives, which is why that branch accepts this shape. The permanent
// fix is to make the ship and the terminal report one ordered write, not to wait here.
func (r *Runner) reviewDeliveryGap(ctx context.Context, run activeRun, node coreNode, attempt int) error {
	undelivered, err := r.reviewRoundUndelivered(ctx, run, node, attempt)
	if err != nil {
		return err
	}
	if undelivered {
		return r.failRun(ctx, run.ID, RunnerErrReviewDeliveryMissing)
	}
	return r.waitEvidence(ctx, run.ID, node, attempt, RunnerErrReviewEvidenceIncomp)
}

// projectionIsBehind reads the sync layer's own verdict on this CR's projection: the
// flag it raises when it refuses to trust its own rows, and which a later snapshot
// clears. A CR with no projection row has never had its authority read here, so there
// is nothing to judge a delivery against: that is behind, not caught up.
//
// A leftover unprocessed ledger row is deliberately not a second signal (AIFI-60 AC-02).
// It was taken to mean "the daemon holds its cursor and re-ships, so the verdict may
// still land", and that premise fails twice over: the commit-scan channel advances its
// cursor as soon as the batch reports, whatever the server said about individual events,
// and a row already recorded is acked by the duplicate branch without ever being
// projected. So a row can sit unprocessed with nothing left on any daemon that would
// ever apply it — and a wait has no deadline and no wake of its own, which made the row
// an unbounded park recorded only as a JSONB wait_reason. A sync event that failed to
// project is a platform problem to surface, not a reason to stop judging the round: the
// answer for this case is the run's existing visible failure, and the resume entry
// continues it on the verdict if one arrives afterwards.
func (r *Runner) projectionIsBehind(ctx context.Context, workspaceID pgtype.UUID, crID string) (bool, error) {
	var behind bool
	err := r.pool.QueryRow(ctx, `
		SELECT COALESCE(c.needs_reconcile, TRUE)
		FROM cr c WHERE c.workspace_id=$1 AND c.cr_id=$2`, workspaceID, crID).Scan(&behind)
	if errors.Is(err, pgx.ErrNoRows) {
		return true, nil
	}
	return behind, err
}

func (r *Runner) setRunnerDetail(ctx context.Context, runID pgtype.UUID, nodeID string, attempt int, detail map[string]any) error {
	raw, err := json.Marshal(detail)
	if err != nil {
		return err
	}
	_, err = r.pool.Exec(ctx, `UPDATE pipeline_node_run SET detail=jsonb_set(COALESCE(detail,'{}'),'{runner}',$4::jsonb,true) WHERE run_id=$1 AND node_id=$2 AND attempt=$3`, runID, nodeID, attempt, raw)
	return err
}

// failRun marks the run failed and records the failure on the node rows that were
// still in flight when it stopped.
//
// Two things used to keep that record off the node rows. The statement's parameter
// had no type inside `jsonb_build_object` (42P18), its error was discarded, and the
// write never happened. Then `jsonb_set(...,'{runner,error}',...)` only creates the
// LAST path segment: a row whose `detail` is still the column default `{}` — the
// first writer or checkpoint task failing before any node record was written — got
// its original target back and the failure code was lost just as silently. The
// parameter is typed, the error is reported, and the error is merged into the
// `{runner}` object the same way the node-progress writes merge theirs, which
// creates that object when it is missing and keeps the root fields and the runner
// fields that were already there.
func (r *Runner) failRun(ctx context.Context, runID pgtype.UUID, code string) error {
	_, err := r.pool.Exec(ctx, `UPDATE pipeline_run SET status='failed',completed_at=now() WHERE id=$1 AND status IN ('running','waiting_approval')`, runID)
	if err != nil {
		return err
	}
	if _, err := r.pool.Exec(ctx, `UPDATE pipeline_node_run SET status=CASE WHEN status='running' THEN 'failed' ELSE status END,completed_at=CASE WHEN status='running' THEN now() ELSE completed_at END,detail=jsonb_set(COALESCE(detail,'{}'),'{runner}',COALESCE(detail->'runner','{}') || jsonb_build_object('error',jsonb_build_object('code',$2::text)),true) WHERE run_id=$1 AND status IN ('running','blocked')`, runID, code); err != nil {
		return errCode(code, fmt.Sprintf("run failed: recording it on the waiting node rows failed: %v", err))
	}
	return errCode(code, "run failed")
}

func (r *Runner) WireEvents(bus *events.Bus) {
	bus.Subscribe(EventCRUpdated, func(e events.Event) {
		payload, ok := e.Payload.(map[string]any)
		if !ok || e.WorkspaceID == "" {
			return
		}
		ws, err := parseUUID(e.WorkspaceID)
		crID := stringValue(payload["cr_id"])
		if err == nil && crID != "" {
			if err := r.Reconcile(context.Background(), ws, crID); err != nil {
				slog.Warn("runner CR wake failed", "cr_id", crID, "error", err)
			}
		}
	})
	for _, eventType := range []string{protocol.EventTaskCompleted, protocol.EventTaskFailed} {
		bus.Subscribe(eventType, func(e events.Event) {
			if e.TaskID != "" {
				if err := r.reconcileFromTaskEvent(context.Background(), e.TaskID); err != nil {
					slog.Warn("runner task wake failed", "task_id", e.TaskID, "error", err)
				}
			}
		})
	}
}

// WakeGrant is the POST-COMMIT wake installed into ApprovalService's
// SetGrantAckCommittedHandler. The ACK handler already scoped the IDs to this
// workspace and committed delivered_at; the callback only wakes, then
// Reconcile re-reads approval_record as authority. Its error is logged by the
// ACK handler and never turns a committed ACK into a 5xx (TD-BL-12 / SDD §3.2).
// AIFIRST: CR-2026-052 TASK-05 — signature extended to GrantAckEvent + error.
// AIFIRST: AIFI-55 — dispatch by stage. There is one post-commit wake slot, and
// the ACK covers every approval stage; the requirement slice owns the
// requirement stage and every other stage still goes to the architecture slice
// exactly as before.
func (r *Runner) WakeGrant(ctx context.Context, ev GrantAckEvent) error {
	ws, err := parseUUID(ev.WorkspaceID)
	if err != nil {
		return fmt.Errorf("invalid workspace id: %w", err)
	}
	// AIFIRST: M51 / M-SC-ACK-003 — route by the CR's ACTUAL stage, not by the
	// stage string captured when the grant was written (that may be stale by the
	// time the ACK arrives). Reconcile covers feature-writeback and
	// architecture-design (including the upstream re-review path; its
	// ensureArchitectureRereviewRun is gated on CR status, so a requirement-phase
	// CR cannot get an architecture run built for it). The requirement-authoring
	// phase has no architecture run to find, so it needs its own entry point.
	// Both are idempotent over active runs and a no-op when none exists, which is
	// exactly what an ACK wake should be: a wake, never a new execution grant.
	if err := r.Reconcile(ctx, ws, ev.CrID); err != nil {
		return err
	}
	return r.ReconcileRequirement(ctx, ws, ev.CrID)
}

// ValidateGrantAck is the PRE-COMMIT FR-10 callback installed into
// ApprovalService's SetGrantAckHandler. It is a pure validation with ZERO
// external side effects — it takes no advisory lock, writes no
// pipeline_run/pipeline_node_run, enqueues no task, and does not call
// Reconcile. An error here rolls back the whole ACK batch and yields HTTP 5xx
// (FR-10 canonical callback, TD-BL-12). It validates the event fields and
// confirms the CR exists in the authenticated workspace via a workspace-scoped
// read-only lookup (reuses GetCrShellIssueInWorkspaceForShare without a FOR SHARE
// lock — the delivery-only ACK path (M50) no longer resolves or locks the
// authority chain, so this lookup is the only authority check left and is
// deliberately defense-in-depth).
// AIFIRST: CR-2026-052 TASK-05.
func (r *Runner) ValidateGrantAck(ctx context.Context, ev GrantAckEvent) error {
	if ev.WorkspaceID == "" {
		return fmt.Errorf("grant ack event: empty workspace id")
	}
	if ev.CrID == "" {
		return fmt.Errorf("grant ack event: empty cr id")
	}
	if _, err := parseUUID(ev.WorkspaceID); err != nil {
		return fmt.Errorf("grant ack event: invalid workspace id: %w", err)
	}
	if _, err := parseUUID(ev.RecordID); err != nil {
		return fmt.Errorf("grant ack event: invalid record id: %w", err)
	}
	if !approvalStages[ev.Stage] {
		return fmt.Errorf("grant ack event: invalid stage %q", ev.Stage)
	}
	if ev.Decision != "approve" && ev.Decision != "reject" {
		return fmt.Errorf("grant ack event: invalid decision %q", ev.Decision)
	}
	// Read-only workspace-scoped CR existence check on a SEPARATE connection
	// with NO lock: resolveContinuationTarget in the ACK transaction already
	// holds the authoritative FOR SHARE; taking it again here would self-deadlock.
	// This is defense-in-depth against a malformed/foreign event reaching the
	// Runner — it reads the committed cr row only.
	ws, _ := parseUUID(ev.WorkspaceID)
	var exists bool
	if err := r.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM cr WHERE workspace_id=$1::uuid AND cr_id=$2)`, ws, ev.CrID).Scan(&exists); err != nil {
		return fmt.Errorf("grant ack event: cr %s lookup failed: %w", ev.CrID, err)
	}
	if !exists {
		return fmt.Errorf("grant ack event: cr %s not found in workspace", ev.CrID)
	}
	return nil
}

// ResumeActiveRuns is the one discovery + coordination entry every wake
// source shares: the boot-time scan and the runtime sweeper's 30s tick both call
// it, so a lost wake event or an undispatched handoff recovers through the same
// Runner Reconcile (and therefore the same advisory lock and active run/node/task
// deduplication) instead of a second orchestration. Per-run errors are logged
// with their machine-readable cause and skipped: a transient DB/network failure
// must not fail the run, and the next tick retries from durable node state.
//
// AIFIRST: M42/M43 (M-SC-TICK-001/004).
func (r *Runner) ResumeActiveRuns(ctx context.Context) error {
	if err := r.StartupScan(ctx); err != nil {
		return err
	}
	return r.StartupScanRequirement(ctx)
}

func (r *Runner) StartupScan(ctx context.Context) error {
	rows, err := r.pool.Query(ctx, `
		SELECT workspace_id,cr_id FROM pipeline_run
		WHERE pipeline_id=$1 AND status IN ('running','waiting_approval') AND execution_context->>'runner'=$2`, PipelineIDs.ArchitectureDesign, runnerSchema)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var ws pgtype.UUID
		var crID string
		if err := rows.Scan(&ws, &crID); err != nil {
			return err
		}
		if err := r.Reconcile(ctx, ws, crID); err != nil {
			slog.Warn("runner startup reconcile failed", "cr_id", crID, "error", err)
		}
	}
	return rows.Err()
}

// AIFIRST: AIFI-55 — refuse-with-diagnosis for a pipeline this Runner does not
// execute. The refusal itself is unchanged: no route is opened, no permission
// is widened, and no stage is entered. What changes is that a caller asking for
// the wrong template is told which template the CR's own status actually places
// it in, so "wrong pipeline asked for" and "this stage has no executor yet" stop
// being the same opaque string. currentStage is "" when it could not be
// established (unknown CR, wrong workspace, or a status with no active pipeline),
// which keeps the original error for every case we cannot attribute.
func unsupportedPipelineError(requested, currentStage string) string {
	if currentStage != "" && currentStage != requested {
		return RunnerErrNoExecutorForStage
	}
	return RunnerErrUnsupportedPipeline
}

// stageOfCR returns the pipeline template the CR's authoritative projected status
// belongs to, reusing the projector status→pipeline map so the Runner and the
// projector can never disagree about which template a status is in. Workspace
// fenced exactly like StartArchitecture's own cr read; "" on any miss.
func (r *Runner) stageOfCR(ctx context.Context, workspaceID pgtype.UUID, crID string) string {
	if r.pool == nil || !CRIDPattern.MatchString(crID) {
		return ""
	}
	var status string
	if err := r.pool.QueryRow(ctx, `SELECT status FROM cr WHERE workspace_id=$1 AND cr_id=$2`, workspaceID, crID).Scan(&status); err != nil {
		return ""
	}
	return pipelineForStatus(status)
}

func (r *Runner) HandleStartArchitecture(w http.ResponseWriter, req *http.Request) {
	if req.Header.Get("X-Actor-Source") != "task_token" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": RunnerErrRequiresAgentRoute})
		return
	}
	workspaceID, werr := parseUUID(req.Header.Get("X-Workspace-ID"))
	if pathWorkspace := chi.URLParam(req, "workspaceID"); pathWorkspace == "" || pathWorkspace != workspaceID.String() {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": RunnerErrAuthorityMismatch})
		return
	}
	agentID, aerr := parseUUID(req.Header.Get("X-Agent-ID"))
	taskID, terr := parseUUID(req.Header.Get("X-Task-ID"))
	userID, uerr := parseUUID(req.Header.Get("X-User-ID"))
	if werr != nil || aerr != nil || terr != nil || uerr != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid task-token binding"})
		return
	}
	var body struct {
		PipelineID string `json:"pipeline_id"`
		CrID       string `json:"cr_id"`
		Inputs     struct {
			TechContext string `json:"tech_context"`
		} `json:"inputs"`
	}
	dec := json.NewDecoder(http.MaxBytesReader(w, req.Body, maxTechContextBytes+4096))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid body"})
		return
	}
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid body"})
		return
	}
	if body.PipelineID != PipelineIDs.ArchitectureDesign {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": unsupportedPipelineError(body.PipelineID, r.stageOfCR(req.Context(), workspaceID, body.CrID))})
		return
	}
	runID, changed, err := r.StartArchitecture(req.Context(), StartArchitectureInput{WorkspaceID: workspaceID, AgentID: agentID, TaskID: taskID, UserID: userID, CrID: body.CrID, TechContext: body.Inputs.TechContext})
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"run_id": runID.String(), "changed": changed})
}

func (r *Runner) reconcileFromTaskEvent(ctx context.Context, taskID string) error {
	id, err := parseUUID(taskID)
	if err != nil {
		return nil
	}
	var ws pgtype.UUID
	var crID string
	err = r.pool.QueryRow(ctx, `
		SELECT r.workspace_id,r.cr_id FROM agent_task_queue t
		JOIN pipeline_node_run n ON n.id=t.pipeline_node_run_id JOIN pipeline_run r ON r.id=n.run_id
		WHERE t.id=$1 AND r.execution_context->>'runner'=$2`, id, runnerSchema).Scan(&ws, &crID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	return r.Reconcile(ctx, ws, crID)
}

func errCode(code, message string) error { return fmt.Errorf("%s: %s", code, message) }
func stringValue(v any) string           { s, _ := v.(string); return s }
func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func parseUUID(s string) (pgtype.UUID, error) {
	var id pgtype.UUID
	if strings.TrimSpace(s) == "" {
		return id, errors.New("UUID is empty")
	}
	if err := id.Scan(s); err != nil || !id.Valid {
		return pgtype.UUID{}, fmt.Errorf("invalid UUID %q", s)
	}
	return id, nil
}

func mustParseUUID(s string) pgtype.UUID {
	id, err := parseUUID(s)
	if err != nil {
		panic(err) // registry UUIDs were validated at startup
	}
	return id
}
