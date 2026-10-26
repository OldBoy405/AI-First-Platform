package daemon

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode"

	"github.com/google/uuid"
	"github.com/multica-ai/multica/server/internal/governance"
	"github.com/multica-ai/multica/server/pkg/protocol"
)

var errExecutionTaskClaimUnavailable = errors.New("EXECUTION_TASK_CLAIM_UNAVAILABLE")

// GetTaskExecutionClaim reads platform claim metadata, not admission evidence.
func (c *Client) GetTaskExecutionClaim(ctx context.Context, workspaceID, projectID, taskID, runtimeID, dispatchedAt string) (protocol.ExecutionTaskClaim, error) {
	var none protocol.ExecutionTaskClaim
	for _, value := range []string{workspaceID, projectID, taskID, runtimeID} {
		id, err := uuid.Parse(value)
		if err != nil || id.String() != value {
			return none, errExecutionTaskClaimUnavailable
		}
	}
	generation, err := protocol.ParseExecutionClaimTime(dispatchedAt)
	if err != nil {
		return none, errExecutionTaskClaimUnavailable
	}
	if err := validateTrustedServerURL(c.baseURL); err != nil {
		return none, errors.Join(errExecutionTaskClaimUnavailable, err)
	}
	query := url.Values{"execution_claim": {"1"}, "runtime_id": {runtimeID}, "dispatched_at": {dispatchedAt}}
	requestURL := c.baseURL + "/api/daemon/tasks/" + taskID + "/status?" + query.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, requestURL, nil)
	if err != nil {
		return none, errors.Join(errExecutionTaskClaimUnavailable, err)
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	c.setIdentityHeaders(req)
	c.setWorkspaceHeader(req, withWorkspaceHeader(ctx, workspaceID))
	httpClient := *c.client
	httpClient.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	response, err := httpClient.Do(req)
	if err != nil {
		return none, errors.Join(errExecutionTaskClaimUnavailable, err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		// Do not consume or echo an untrusted error body or follow a redirect.
		return none, fmt.Errorf("%w: HTTP %d", errExecutionTaskClaimUnavailable, response.StatusCode)
	}
	const maxBody = 1 << 20
	body, err := io.ReadAll(io.LimitReader(response.Body, maxBody+1))
	if err != nil || len(body) > maxBody || governance.ValidateExecutionJSON(body) != nil {
		return none, errExecutionTaskClaimUnavailable
	}
	var fields map[string]json.RawMessage
	if json.Unmarshal(body, &fields) != nil || len(fields) != 8 {
		return none, errExecutionTaskClaimUnavailable
	}
	for _, key := range []string{"schema", "workspace_id", "project_id", "daemon_id", "runtime_id", "task_id", "dispatched_at", "status"} {
		if _, ok := fields[key]; !ok {
			return none, errExecutionTaskClaimUnavailable
		}
	}
	var claim protocol.ExecutionTaskClaim
	if json.Unmarshal(body, &claim) != nil || claim.Schema != "execution-task-claim/v1" ||
		claim.WorkspaceID != workspaceID || claim.ProjectID != projectID || claim.TaskID != taskID || claim.RuntimeID != runtimeID ||
		strings.TrimSpace(claim.DaemonID) == "" || strings.IndexFunc(claim.DaemonID, unicode.IsControl) >= 0 ||
		(claim.Status != "dispatched" && claim.Status != "waiting_local_directory" && claim.Status != "running") {
		return none, errExecutionTaskClaimUnavailable
	}
	actualGeneration, err := protocol.ParseExecutionClaimTime(claim.DispatchedAt)
	if err != nil || !actualGeneration.Equal(generation) ||
		claim.DispatchedAt != actualGeneration.UTC().Format(time.RFC3339Nano) {
		return none, errExecutionTaskClaimUnavailable
	}
	return claim, nil
}
