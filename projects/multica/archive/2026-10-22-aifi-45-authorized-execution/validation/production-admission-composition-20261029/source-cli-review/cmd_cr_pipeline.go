package main

// AIFIRST: AIFI-55 鈥?thin relay for the Runner start entry
// (POST /api/workspaces/{workspaceID}/pipeline-runs). The endpoint, its
// authorization and its Runner already exist in server/internal/governance;
// what was missing is a discoverable client for them. This command adds no
// server route, no permission and no business judgment: it relays the
// task-scoped credential and the CR-ID, and passes {run_id, changed} through
// verbatim so the caller can tell an opened run from a resumed one.
//
// The Runner executes exactly two pipelines, and this file reaches exactly those
// two routes: `start` goes to the architecture-design route, `resume` goes to the
// requirement-authoring route. code-implementation and feature-writeback are
// projection-only and have no executor, so no subcommand here can stand in for
// them and none pretends to.

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/multica-ai/multica/server/internal/cli"
)

// architecturePipelineID is the pipeline the architecture slice executes. It is
// the default for --pipeline so the existing architecture call is unchanged, and
// it is sent as-is so the server stays the single authority on which pipelines it
// accepts (anything else fails closed).
const architecturePipelineID = "architecture-design"

// requirementPipelineID is the pipeline the recovery slice acts on.
const requirementPipelineID = "requirement-authoring"

var crPipelineCmd = &cobra.Command{
	Use:   "pipeline",
	Short: "Start or resume an AIFIRST pipeline run for a CR",
}

var crPipelineStartCmd = &cobra.Command{
	Use:   "start <cr-id>",
	Short: "Start or resume the architecture-design pipeline run for a CR",
	Long: `Start or resume the architecture-design pipeline run for a CR.

To recover a CR that is still in its requirement phase use
` + "`multica cr pipeline resume`" + ` instead 鈥?that entry cannot register a CR.

Requires a mat_ task token: workspace/agent/task/user identity is derived
server-side from the token, and the server rejects any other caller with
RUNNER_REQUIRES_AGENT_ROUTE. The CR must already be at requirement-approved 鈥?this starts or resumes the architecture pipeline only; it is not a CR
registration path, and it never rewrites a CR's registration inputs.

The call is idempotent. ACTION=opened means this call created the run;
ACTION=resumed means an active run already existed and was handed back, so
re-running against an in-flight CR does not create a second run. Prints the
structured result {run_id, changed}; a rejected call exits non-zero with the
server error code (RUNNER_UNSUPPORTED_PIPELINE / RUNNER_NO_EXECUTOR_FOR_STAGE /
RUNNER_CR_NOT_READY / RUNNER_AUTHORITY_MISMATCH / RUNNER_AGENT_NOT_READY /
RUNNER_SKILL_MISSING / RUNNER_ATTRIBUTION_INVALID).

--pipeline names the template to start. architecture-design is the default and
the only one with an executor today; asking for a stage the Runner does not
execute fails closed. RUNNER_NO_EXECUTOR_FOR_STAGE means the CR's current
projected status belongs to that other template 鈥?recover that stage through its
own Pipeline, not through this command.

Requires the deployment switch AIFIRST_ARCHITECTURE_RUNNER on the server; with
it off the route is not mounted and the call returns 404. Enabling it also
requires a configured admission decider; otherwise the server refuses to start.`,
	Args: exactArgs(1),
	RunE: runCrPipelineStart,
}

// crPipelineResumeCmd resumes the requirement-authoring phase of an
// already-registered CR. It is a separate verb rather than a --pipeline value on
// `start` because the two entry points are not interchangeable: `start` is the
// architecture slice's start, while this one can only ever act on a CR that is
// already registered and still in its requirement phase. There is no flag here
// that could turn it into a registration path.
var crPipelineResumeCmd = &cobra.Command{
	Use:   "resume <cr-id>",
	Short: "Resume the requirement phase of an already-registered CR",
	Long: `Resume the requirement-authoring phase of an already-registered CR.

This never registers a CR and never rewrites registration inputs: the CR must
already exist and be at drafting or requirement-reviewing. The Runner picks the
legal next node from the CR's own projected status, runs the author nodes on the
pipeline owner's agent and the review node on the review skill's own agent, and
parks at the human approval gate after a canonical PASS. A BLOCK review routes
back to the declared repair node.

Requires a mat_ task token, like every Runner route. The call is idempotent:
ACTION=resumed means an active run already existed and was handed back, so
running it twice does not create a second run or re-register the CR.

Requires the deployment switch AIFIRST_ARCHITECTURE_RUNNER on the server; with
it off the route is not mounted and the call returns 404. Enabling it also
requires a configured admission decider; otherwise the server refuses to start.`,
	Args: exactArgs(1),
	RunE: runCrPipelineResume,
}

func init() {
	crCmd.AddCommand(crPipelineCmd)
	crPipelineCmd.AddCommand(crPipelineStartCmd)
	crPipelineCmd.AddCommand(crPipelineResumeCmd)
	// --output goes on the leaf, matching cr bind-current-task /
	// bind-promotion-run: a parent persistent flag is not readable through
	// cmd.Flags() when the runner is invoked directly.
	crPipelineStartCmd.Flags().String("output", "json", "Output format: table or json")
	crPipelineStartCmd.Flags().String("tech-context", "", "Optional tech context (max 16 KiB) passed to the first node prompt")
	crPipelineStartCmd.Flags().String("pipeline", architecturePipelineID, "Pipeline template to start")
	crPipelineResumeCmd.Flags().String("output", "json", "Output format: table or json")
	// The writing node's prompt declares a source document. The CR projection does
	// not carry it and the ledger is in git, so it is passed here and recorded on
	// the run. Empty is the documented equivalent of "no document bound".
	crPipelineResumeCmd.Flags().String("source", "", "Source document path already recorded on this CR (empty when none was bound)")
	// A pipeline's node prompts are compiled into its registry, so a template change moves
	// the digest and every run recorded before it then fails the digest guard — resume
	// included. This names the digest the operator means to replace, so the hand-over is
	// about one known record instead of whatever the deployment happens to run. Omitted,
	// the guard refuses exactly as before.
	crPipelineResumeCmd.Flags().String("supersede-template-digest", "",
		"Registry digest the run is recorded under, to continue it under the templates now deployed (AIFI-60)")
}

// runCrPipelineResume relays to the requirement-phase recovery route. It shares
// the credential, workspace and task-token preconditions with start; only the
// path and the pipeline identity differ.
func runCrPipelineResume(cmd *cobra.Command, args []string) error {
	crID := args[0]
	client, err := newAPIClient(cmd)
	if err != nil {
		return err
	}
	if !strings.HasPrefix(client.Token, cli.TaskTokenPrefix) {
		return fmt.Errorf("resume pipeline for %s: %s task token required; run this inside a Multica agent task", crID, cli.TaskTokenPrefix)
	}
	workspaceID := client.WorkspaceID
	if strings.TrimSpace(workspaceID) == "" {
		return fmt.Errorf("resume pipeline for %s: workspace ID is required: MULTICA_WORKSPACE_ID must be set by the daemon in agent execution context", crID)
	}

	ctx, cancel := cli.APIContext(context.Background())
	defer cancel()

	source, err := cmd.Flags().GetString("source")
	if err != nil {
		return fmt.Errorf("resume pipeline for %s: %w", crID, err)
	}
	supersede, err := cmd.Flags().GetString("supersede-template-digest")
	if err != nil {
		return fmt.Errorf("resume pipeline for %s: %w", crID, err)
	}
	body := map[string]any{
		"pipeline_id": requirementPipelineID,
		"cr_id":       crID,
		"source":      source,
	}
	// Sent only when set: the route rejects unknown fields, so an unconditional key would
	// make every ordinary resume fail against a server that predates it.
	if strings.TrimSpace(supersede) != "" {
		body["supersede_template_digest"] = strings.TrimSpace(supersede)
	}
	var out map[string]any
	if err := client.PostJSON(ctx, "/api/workspaces/"+workspaceID+"/pipeline-runs/requirement", body, &out); err != nil {
		return fmt.Errorf("resume pipeline for %s: %w", crID, err)
	}

	output, _ := cmd.Flags().GetString("output")
	if output == "table" {
		action := "resumed"
		if b, ok := out["changed"].(bool); ok && b {
			action = "opened"
		}
		cli.PrintTable(os.Stdout, []string{"CR", "PIPELINE", "RUN", "ACTION"}, [][]string{{
			crID,
			requirementPipelineID,
			strVal(out, "run_id"),
			action,
		}})
		return nil
	}
	return cli.PrintJSON(os.Stdout, out)
}

func runCrPipelineStart(cmd *cobra.Command, args []string) error {
	crID := args[0]
	techContext, err := cmd.Flags().GetString("tech-context")
	if err != nil {
		return fmt.Errorf("start pipeline for %s: %w", crID, err)
	}
	pipelineID, err := cmd.Flags().GetString("pipeline")
	if err != nil {
		return fmt.Errorf("start pipeline for %s: %w", crID, err)
	}
	if strings.TrimSpace(pipelineID) == "" {
		return fmt.Errorf("start pipeline for %s: --pipeline must name a pipeline template", crID)
	}

	client, err := newAPIClient(cmd)
	if err != nil {
		return err
	}
	// The server authorizes this route from the task token alone and reports
	// the mismatch as a bare 403. Say which credential is required instead.
	if !strings.HasPrefix(client.Token, cli.TaskTokenPrefix) {
		return fmt.Errorf("start pipeline for %s: %s task token required; run this inside a Multica agent task", crID, cli.TaskTokenPrefix)
	}
	workspaceID := client.WorkspaceID
	if strings.TrimSpace(workspaceID) == "" {
		return fmt.Errorf("start pipeline for %s: workspace ID is required: MULTICA_WORKSPACE_ID must be set by the daemon in agent execution context", crID)
	}

	ctx, cancel := cli.APIContext(context.Background())
	defer cancel()

	var out map[string]any
	if err := client.PostJSON(ctx, "/api/workspaces/"+workspaceID+"/pipeline-runs", map[string]any{
		"pipeline_id": pipelineID,
		"cr_id":       crID,
		"inputs":      map[string]any{"tech_context": techContext},
	}, &out); err != nil {
		return fmt.Errorf("start pipeline for %s: %w", crID, err)
	}

	output, _ := cmd.Flags().GetString("output")
	if output == "table" {
		action := "resumed"
		if b, ok := out["changed"].(bool); ok && b {
			action = "opened"
		}
		cli.PrintTable(os.Stdout, []string{"CR", "PIPELINE", "RUN", "ACTION"}, [][]string{{
			crID,
			pipelineID,
			strVal(out, "run_id"),
			action,
		}})
		return nil
	}
	return cli.PrintJSON(os.Stdout, out)
}
