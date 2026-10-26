// AIFIRST: daemon-side static verifier invocation (AIFI-45). This runs the
// installed control tool, not an agent-supplied executable. --check remains
// read-only; a successful check is never a current-head or admission fact.
package daemon

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/multica-ai/multica/server/internal/governance"
)

// prepareClaimedPipelineTask keeps the existing path preparation as the first
// step. Execution-contract preflight is added here rather than to path lookup,
// so root selection alone never becomes execution admission.
func (d *Daemon) prepareClaimedPipelineTask(ctx context.Context, task *Task) error {
	if task == nil {
		return nil
	}
	strict, err := strictExecutionContract(task.TriggerCommentContent)
	if err != nil {
		return err
	}
	if strict {
		if d.client == nil {
			return fmt.Errorf("%w: EXECUTION_BINDING_UNAVAILABLE: authorization client unavailable", errExecutionTaskClaimUnavailable)
		}
		claim, err := d.client.GetTaskExecutionClaim(ctx, task.WorkspaceID, task.ProjectID, task.ID, task.RuntimeID, task.DispatchedAt)
		if err != nil {
			return err
		}
		if claim.DaemonID != d.cfg.DaemonID {
			return fmt.Errorf("%w: daemon identity mismatch", errExecutionTaskClaimUnavailable)
		}
	}
	if err := d.preparePipelineTask(ctx, task); err != nil {
		return err
	}
	if !strict {
		return nil
	}
	if task.PipelineWorkspace == "" {
		return errors.New("EXECUTION_BINDING_UNAVAILABLE: authorization client or resolved CR root unavailable")
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("EXECUTION_BINDING_UNAVAILABLE: daemon home: %w", err)
	}
	store, err := OpenExecutionTrustStore(home, task.WorkspaceID, task.PipelineWorkspace, task.PipelineLocalWorkDir)
	if err != nil {
		return err
	}
	if _, err := d.client.InstallExecutionAuthorization(ctx, store, task.PipelineCrID, task.PipelineWorkspace); err != nil {
		return err
	}
	// No receipt, activation or claimed identity is inferred from a static
	// check. Do not start the agent until current-head/revocation/claim and
	// the isolated control channel have been verified and consumed by T.
	return errors.New("EXECUTION_CONSUMPTION_REQUIRED: static contract checked; current head, revocation, claim and trusted consumption are not connected")
}

// executionCheckOutput limits each child output stream, including failure text.
// Separate writers are used because os/exec drains stdout/stderr concurrently.
type executionCheckOutput struct{ bytes.Buffer }

func (b *executionCheckOutput) Write(p []byte) (int, error) {
	if b.Len()+len(p) > 16<<10 {
		return 0, errors.New("execution verifier output exceeds 16 KiB")
	}
	return b.Buffer.Write(p)
}

func verifyInstalledExecutionGrant(ctx context.Context, workspace, crID, name, trustRoot string, envelope governance.ExecutionGrantEnvelope) error {
	node, crctl, err := resolvePipelineCrctl()
	if err != nil {
		return err
	}
	digest, err := governance.ExecutionGrantDigest(envelope.PayloadB64)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, node, crctl, "authorization-bind", crID,
		"--workspace", workspace, "--grant", name, "--trust-root", trustRoot, "--check")
	cmd.Dir = workspace
	cmd.WaitDelay = time.Second
	// Do not inherit NODE_OPTIONS/NODE_PATH, model credentials or GIT_* repo
	// redirection from a task. These are host runtime necessities only, not
	// evidence that the child is isolated from the daemon.
	for _, key := range []string{"PATH", "PATHEXT", "SystemRoot", "WINDIR", "HOME", "USERPROFILE", "TEMP", "TMP", "LANG"} {
		if value, ok := os.LookupEnv(key); ok {
			cmd.Env = append(cmd.Env, key+"="+value)
		}
	}
	var stdout, stderr executionCheckOutput
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("EXECUTION_CHECK_FAILED: %w: %s%s", err, stdout.String(), stderr.String())
	}
	return validateExecutionCheckOutput(stdout.Bytes(), crID, name, digest)
}

func validateExecutionCheckOutput(raw []byte, crID, name, digest string) error {
	if err := governance.ValidateExecutionJSON(raw); err != nil {
		return fmt.Errorf("EXECUTION_CHECK_FAILED: invalid verifier JSON: %w", err)
	}
	var check struct {
		Op                  string `json:"op"`
		CR                  string `json:"cr"`
		CheckOnly           bool   `json:"check_only"`
		Bound               *bool  `json:"bound"`
		CurrentHeadVerified *bool  `json:"current_head_verified"`
		SourceVerified      *bool  `json:"source_verified"`
		GrantDigest         string `json:"grant_digest"`
		GrantID             string `json:"grant_id"`
		ScopeHash           string `json:"scope_hash"`
	}
	if err := json.Unmarshal(raw, &check); err != nil {
		return fmt.Errorf("EXECUTION_CHECK_FAILED: verifier did not return one JSON object: %w", err)
	}
	if check.Op != "authorization-bind" || check.CR != crID || !check.CheckOnly ||
		check.Bound == nil || *check.Bound || check.CurrentHeadVerified == nil || *check.CurrentHeadVerified ||
		check.SourceVerified == nil || *check.SourceVerified || check.GrantDigest != digest ||
		!strings.HasSuffix(name, ".execution-grant.json") ||
		name != check.ScopeHash+"-"+check.GrantID+".execution-grant.json" {
		return errors.New("EXECUTION_CHECK_FAILED: verifier facts differ from the installed grant or claim admission")
	}
	return nil
}
