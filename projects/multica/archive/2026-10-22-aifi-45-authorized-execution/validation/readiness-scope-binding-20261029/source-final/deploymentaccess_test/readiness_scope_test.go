package deploymentaccess_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/multica-ai/multica/server/internal/governance"
)

var readinessScopePredicate = regexp.MustCompile(`(?i)\bscope\s*=\s*\$2\b`)

type readinessScopeTx struct {
	pgx.Tx
	t           *testing.T
	storedScope string
	action      string
	expired     bool
	writes      int
}

func (tx *readinessScopeTx) QueryRow(_ context.Context, sql string, args ...any) pgx.Row {
	tx.t.Helper()
	switch {
	case strings.Contains(sql, "SELECT verdict_bytes, expiry FROM cr_execution_policy_readiness"):
		filtered := readinessScopePredicate.MatchString(sql)
		if len(args) != 1 && len(args) != 2 || args[0] != verdictID || filtered != (len(args) == 2) {
			return fakeRow{err: fmt.Errorf("unexpected readiness query parameters")}
		}
		if filtered && args[1] != tx.storedScope {
			return fakeRow{err: pgx.ErrNoRows}
		}
		code := "READY_STRICT"
		if tx.action == "retire-legacy-relay" {
			code = "READY_TO_RETIRE"
		}
		verdict, err := json.Marshal(map[string]any{
			"schema": "execution-policy-readiness/v1", "action": tx.action,
			"profile_purpose": "strict-production", "deployment_generation": 1,
			"ready": true, "code": code, "target_policy_digest": "policy-digest",
			"template_digest": "template-digest", "profile_digest": "profile-digest",
		})
		if err != nil {
			tx.t.Fatal(err)
		}
		expiry := now.Add(time.Hour)
		if tx.expired {
			expiry = now.Add(-time.Hour)
		}
		return fakeRow{values: []any{verdict, expiry}}
	case strings.Contains(sql, "SELECT generation, registry_revision, state"):
		return fakeRow{values: []any{int64(1), int64(1), "PENDING"}}
	case strings.Contains(sql, "SELECT count(*) FROM cr_execution_policy_activation_event"):
		return fakeRow{values: []any{0}}
	case strings.Contains(sql, "SELECT revision, event_id::text, last_issued_admission_seq"):
		return fakeRow{values: []any{int64(1), eventID, cutoff}}
	case strings.Contains(sql, "SELECT revision, event_id::text FROM cr_execution_policy_activation_head"):
		return fakeRow{err: pgx.ErrNoRows}
	case strings.Contains(sql, "SELECT mode, verdict_ref::text"):
		id := verdictID
		return fakeRow{values: []any{governance.ActivationModeActive, &id}}
	case strings.Contains(sql, "SELECT legacy_gate, legacy_work_revision, generation"):
		return fakeRow{values: []any{"DRAINING", int64(7), int64(1)}}
	case strings.Contains(sql, "INSERT INTO cr_execution_policy_activation_event"):
		tx.writes++
		return fakeRow{values: []any{eventID}}
	default:
		tx.t.Fatalf("unexpected query: %s", sql)
		return fakeRow{err: errors.New("unexpected query")}
	}
}

func (tx *readinessScopeTx) Exec(_ context.Context, _ string, _ ...any) (pgconn.CommandTag, error) {
	tx.writes++
	return pgconn.NewCommandTag("UPDATE 1"), nil
}

func TestReadinessRequestScopeBinding(t *testing.T) {
	const storedScope = "workspace:readiness-owner"
	const otherScope = "workspace:other"
	for _, path := range []string{"activate", "issue", "retire", "access", "access_recovery", "access_audit"} {
		for _, test := range []struct {
			name  string
			scope string
			allow bool
		}{
			{name: "same_scope", scope: storedScope, allow: true},
			{name: "other_scope", scope: otherScope},
		} {
			t.Run(path+"/"+test.name, func(t *testing.T) {
				action := "enable-policy"
				if path == "retire" {
					action = "retire-legacy-relay"
				}
				tx := &readinessScopeTx{t: t, storedScope: storedScope, action: action, expired: path == "access_recovery"}
				var outcome string
				var err error
				switch path {
				case "activate":
					var result governance.ActivationRef
					result, err = governance.ActivatePolicyTx(context.Background(), tx, governance.ActivateInput{
						Scope: test.scope, TargetPolicy: policy, RequestID: verdictID, ExpectedGeneration: 1,
						TargetPolicyDigest: "policy-digest", TemplateDigest: "template-digest", ProfileDigest: "profile-digest", Now: now,
					})
					outcome = result.Mode
				case "issue":
					var result governance.IssuedAdmission
					result, err = governance.IssueAdmissionTx(context.Background(), tx, test.scope, policy, now)
					if result.AdmissionSeq > 0 {
						outcome = "issued"
					}
				case "retire":
					var result governance.ActivationRef
					result, err = governance.FinalizeLegacyRetirementTx(context.Background(), tx, test.scope, verdictID, "workset", 7, 1, now)
					outcome = result.Mode
				case "access", "access_recovery", "access_audit":
					in := governance.DeploymentAccessInput{Scope: test.scope, TargetPolicy: policy, Op: "new_admission", Now: now}
					if path == "access_recovery" {
						in.Op = "complete_unsettled_request"
						in.AdmissionSeq, in.IssuedAt = cutoff, now.Add(-2*time.Hour)
						in.PersistedOriginRef, in.OriginRef = "origin", "origin"
						in.PersistedDigest, in.Digest = "digest", "digest"
						in.PersistedGeneration, in.Generation = 1, 1
					}
					if path == "access_audit" {
						in.Op = "checkpoint_ingest"
					}
					outcome, err = governance.CheckDeploymentAccessTx(context.Background(), tx, in)
				}
				if !test.allow {
					if !errors.Is(err, governance.ErrDeploymentNotReady) {
						t.Errorf("cross-scope readiness must be rejected: outcome=%q err=%v", outcome, err)
					}
					if tx.writes != 0 {
						t.Errorf("cross-scope readiness caused %d writes", tx.writes)
					}
					return
				}
				if err != nil {
					t.Fatalf("same-scope readiness: %v", err)
				}
				want := map[string]string{
					"activate": governance.ActivationModeActive, "issue": "issued", "retire": "RETIRED",
					"access": governance.AccessNewAdmission, "access_recovery": governance.AccessExactRecovery,
					"access_audit": governance.AccessAuditOnly,
				}[path]
				if outcome != want {
					t.Errorf("same-scope outcome=%q, want %q", outcome, want)
				}
				wantWrites := map[string]int{"activate": 3, "issue": 1, "retire": 1}[path]
				if tx.writes != wantWrites {
					t.Errorf("same-scope writes=%d, want %d", tx.writes, wantWrites)
				}
			})
		}
	}
	t.Run("stop_new_without_verdict", func(t *testing.T) {
		tx := accessTx(t, governance.ActivationModeStopNew, now.Add(time.Hour), false)
		check(t, tx, input("complete_unsettled_request"), governance.AccessExactRecovery)
	})
}
