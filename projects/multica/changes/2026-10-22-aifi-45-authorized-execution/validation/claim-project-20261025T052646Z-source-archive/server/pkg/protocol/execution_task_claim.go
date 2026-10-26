package protocol

import (
	"errors"
	"strings"
	"time"
)

// ParseExecutionClaimTime rejects precision before time.Parse can truncate it.
// New claim metadata uses PostgreSQL's at-most-six fractional digits.
func ParseExecutionClaimTime(raw string) (time.Time, error) {
	if start := strings.IndexAny(raw, ".,"); start >= 0 {
		end := start + 1
		for end < len(raw) && raw[end] >= '0' && raw[end] <= '9' {
			end++
		}
		if raw[start] != '.' || end-start-1 > 6 {
			return time.Time{}, errors.New("invalid execution claim timestamp precision")
		}
	}
	parsed, err := time.Parse(time.RFC3339Nano, raw)
	if err != nil || parsed.Nanosecond()%1000 != 0 {
		return time.Time{}, errors.New("invalid execution claim timestamp")
	}
	return parsed, nil
}

// ExecutionTaskClaim is a platform DB snapshot, not an admission or a binding
// signature. It neither authenticates a local process nor reserves a claim.
type ExecutionTaskClaim struct {
	Schema       string `json:"schema"`
	WorkspaceID  string `json:"workspace_id"`
	ProjectID    string `json:"project_id"`
	DaemonID     string `json:"daemon_id"`
	RuntimeID    string `json:"runtime_id"`
	TaskID       string `json:"task_id"`
	DispatchedAt string `json:"dispatched_at"`
	Status       string `json:"status"`
}
