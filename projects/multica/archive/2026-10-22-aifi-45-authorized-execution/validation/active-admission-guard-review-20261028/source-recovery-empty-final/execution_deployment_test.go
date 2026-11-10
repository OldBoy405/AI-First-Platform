package deploymentaccess_test

import (
	"context"
	"fmt"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/multica-ai/multica/server/internal/governance"
)

const (
	scope     = "workspace:access-test"
	policy    = "policy-test"
	eventID   = "11111111-1111-4111-8111-111111111111"
	verdictID = "22222222-2222-4222-8222-222222222222"
	cutoff    = int64(4)
)

var now = time.Date(2026, 10, 27, 12, 0, 0, 0, time.UTC)

type queryStep struct {
	fragments []string
	args      []any
	values    []any
	err       error
}

type fakeTx struct {
	pgx.Tx
	t     *testing.T
	steps []queryStep
	next  int
}

var _ pgx.Tx = (*fakeTx)(nil)

func (tx *fakeTx) QueryRow(_ context.Context, sql string, args ...any) pgx.Row {
	tx.t.Helper()
	if tx.next >= len(tx.steps) {
		tx.t.Fatalf("unexpected query %d: %s", tx.next+1, sql)
	}
	step := tx.steps[tx.next]
	tx.next++
	for _, fragment := range step.fragments {
		if !strings.Contains(sql, fragment) {
			tx.t.Fatalf("query %d missing %q: %s", tx.next, fragment, sql)
		}
	}
	if !reflect.DeepEqual(args, step.args) {
		tx.t.Fatalf("query %d args = %#v, want %#v", tx.next, args, step.args)
	}
	return fakeRow{values: step.values, err: step.err}
}

type fakeRow struct {
	values []any
	err    error
}

func (r fakeRow) Scan(dest ...any) error {
	if r.err != nil {
		return r.err
	}
	if len(dest) != len(r.values) {
		return fmt.Errorf("scan got %d destinations, want %d", len(dest), len(r.values))
	}
	for i, value := range r.values {
		d := reflect.ValueOf(dest[i])
		v := reflect.ValueOf(value)
		if d.Kind() != reflect.Pointer || d.IsNil() || !v.IsValid() || !v.Type().AssignableTo(d.Elem().Type()) {
			return fmt.Errorf("scan destination %d: cannot assign %T to %T", i, value, dest[i])
		}
		d.Elem().Set(v)
	}
	return nil
}

func accessTx(t *testing.T, mode string, expiry time.Time, missingHead bool) *fakeTx {
	t.Helper()
	head := queryStep{
		fragments: []string{"SELECT revision, event_id::text, last_issued_admission_seq", "FROM cr_execution_policy_activation_head", "WHERE scope = $1 AND target_policy = $2"},
		args:      []any{scope, policy},
		values:    []any{int64(2), eventID, cutoff},
	}
	if missingHead {
		head.err = pgx.ErrNoRows
	}
	steps := []queryStep{head}
	if !missingHead {
		var verdictRef *string
		if mode == governance.ActivationModeActive {
			id := verdictID
			verdictRef = &id
		}
		steps = append(steps, queryStep{
			fragments: []string{"SELECT mode, verdict_ref::text", "FROM cr_execution_policy_activation_event", "WHERE id = $1::uuid"},
			args:      []any{eventID},
			values:    []any{mode, verdictRef},
		})
		if verdictRef != nil {
			steps = append(steps, queryStep{
				fragments: []string{"SELECT verdict_bytes, expiry", "FROM cr_execution_policy_readiness", "WHERE request_id = $1::uuid FOR UPDATE"},
				args:      []any{verdictID},
				values:    []any{[]byte(fmt.Sprintf(`{"schema":"execution-policy-readiness/v1","action":"enable-policy","profile_purpose":"strict-production","deployment_generation":1,"ready":true,"code":"READY_STRICT","expires_at":%d}`, expiry.Unix())), expiry},
			})
		}
	}
	tx := &fakeTx{t: t, steps: steps}
	t.Cleanup(func() {
		if tx.next != len(tx.steps) {
			t.Errorf("queries called = %d, want %d", tx.next, len(tx.steps))
		}
	})
	return tx
}

func input(op string) governance.DeploymentAccessInput {
	return governance.DeploymentAccessInput{
		Scope: scope, TargetPolicy: policy, Op: op, RequestID: "request-test", Now: now,
		AdmissionSeq: cutoff, IssuedAt: now.Add(-2 * time.Minute),
		PersistedOriginRef: "origin-1", OriginRef: "origin-1",
		PersistedDigest: "digest-1", Digest: "digest-1", PersistedGeneration: 1, Generation: 1,
	}
}

func check(t *testing.T, tx *fakeTx, in governance.DeploymentAccessInput, want string) {
	t.Helper()
	got, err := governance.CheckDeploymentAccessTx(context.Background(), tx, in)
	if err != nil {
		t.Fatalf("CheckDeploymentAccessTx(%s) error: %v", in.Op, err)
	}
	if got != want {
		t.Errorf("CheckDeploymentAccessTx(%s) = %s, want %s", in.Op, got, want)
	}
}

func TestNewOperationsByActivationState(t *testing.T) {
	ops := []string{"new_admission", "new_selection", "command_issue", "new_candidate", "new_effect"}
	states := []struct {
		name        string
		mode        string
		expiry      time.Time
		missingHead bool
		want        string
	}{
		{"active_unexpired", governance.ActivationModeActive, now.Add(time.Minute), false, governance.AccessNewAdmission},
		{"stop_new", governance.ActivationModeStopNew, time.Time{}, false, governance.AccessDenied},
		{"active_expired", governance.ActivationModeActive, now.Add(-time.Minute), false, governance.AccessDenied},
		{"missing_head", "", time.Time{}, true, governance.AccessDenied},
	}
	for _, state := range states {
		for _, op := range ops {
			t.Run(state.name+"/"+op, func(t *testing.T) {
				check(t, accessTx(t, state.mode, state.expiry, state.missingHead), input(op), state.want)
			})
		}
	}
}

func TestAuditOperationsRemainAuditOnly(t *testing.T) {
	ops := []string{"checkpoint_ingest", "verdict_ingest", "original_bytes_query", "no_effect_settlement", "resume_intent"}
	states := []struct {
		name        string
		mode        string
		expiry      time.Time
		missingHead bool
	}{
		{"active_unexpired", governance.ActivationModeActive, now.Add(time.Minute), false},
		{"stop_new", governance.ActivationModeStopNew, time.Time{}, false},
		{"active_expired", governance.ActivationModeActive, now.Add(-time.Minute), false},
		{"missing_head", "", time.Time{}, true},
	}
	for _, state := range states {
		for _, op := range ops {
			t.Run(state.name+"/"+op, func(t *testing.T) {
				check(t, accessTx(t, state.mode, state.expiry, state.missingHead), input(op), governance.AccessAuditOnly)
			})
		}
	}
}

func TestExactRecoveryAfterStopOrExpiry(t *testing.T) {
	states := []struct {
		name   string
		mode   string
		expiry time.Time
	}{
		{"stop_new", governance.ActivationModeStopNew, time.Time{}},
		{"active_expired", governance.ActivationModeActive, now.Add(-time.Minute)},
	}
	cases := []struct {
		name   string
		op     string
		change func(*governance.DeploymentAccessInput)
		want   string
	}{
		{"complete_original", "complete_unsettled_request", nil, governance.AccessExactRecovery},
		{"bind_original", "bind_existing_mapping", nil, governance.AccessExactRecovery},
		{"not_issued", "complete_unsettled_request", func(in *governance.DeploymentAccessInput) { in.AdmissionSeq = 0 }, governance.AccessDenied},
		{"after_cutoff", "complete_unsettled_request", func(in *governance.DeploymentAccessInput) { in.AdmissionSeq = cutoff + 1 }, governance.AccessDenied},
		{"changed_origin", "complete_unsettled_request", func(in *governance.DeploymentAccessInput) { in.OriginRef = "other" }, governance.AccessDenied},
		{"changed_digest", "complete_unsettled_request", func(in *governance.DeploymentAccessInput) { in.Digest = "other" }, governance.AccessDenied},
		{"changed_generation", "bind_existing_mapping", func(in *governance.DeploymentAccessInput) { in.Generation = 2 }, governance.AccessDenied},
	}
	for _, state := range states {
		for _, tc := range cases {
			t.Run(state.name+"/"+tc.name, func(t *testing.T) {
				in := input(tc.op)
				if tc.change != nil {
					tc.change(&in)
				}
				check(t, accessTx(t, state.mode, state.expiry, false), in, tc.want)
			})
		}
	}
	t.Run("expired_issued_after_expiry", func(t *testing.T) {
		in := input("complete_unsettled_request")
		in.IssuedAt = now
		check(t, accessTx(t, governance.ActivationModeActive, now.Add(-time.Minute), false), in, governance.AccessDenied)
	})
}

func TestRecoveryRejectsMissingOrInvalidIdentityFacts(t *testing.T) {
	states := []struct {
		name   string
		mode   string
		expiry time.Time
	}{
		{"stop_new", governance.ActivationModeStopNew, time.Time{}},
		{"active_expired", governance.ActivationModeActive, now.Add(-time.Minute)},
	}
	cases := []struct {
		name   string
		change func(*governance.DeploymentAccessInput)
	}{
		{"missing_issued_at", func(in *governance.DeploymentAccessInput) { in.IssuedAt = time.Time{} }},
		{"missing_generation", func(in *governance.DeploymentAccessInput) { in.Generation = 0 }},
		{"missing_persisted_generation", func(in *governance.DeploymentAccessInput) { in.PersistedGeneration = 0 }},
		{"both_generations_missing", func(in *governance.DeploymentAccessInput) { in.Generation, in.PersistedGeneration = 0, 0 }},
		{"both_generations_negative", func(in *governance.DeploymentAccessInput) { in.Generation, in.PersistedGeneration = -1, -1 }},
		{"both_origins_empty", func(in *governance.DeploymentAccessInput) { in.OriginRef, in.PersistedOriginRef = "", "" }},
		{"both_digests_empty", func(in *governance.DeploymentAccessInput) { in.Digest, in.PersistedDigest = "", "" }},
	}
	for _, state := range states {
		for _, tc := range cases {
			t.Run(state.name+"/"+tc.name, func(t *testing.T) {
				in := input("complete_unsettled_request")
				tc.change(&in)
				check(t, accessTx(t, state.mode, state.expiry, false), in, governance.AccessDenied)
			})
		}
	}
}

func TestKnownRecoveryOperationsOnActiveDeployment(t *testing.T) {
	for _, op := range []string{"complete_unsettled_request", "bind_existing_mapping"} {
		t.Run(op, func(t *testing.T) {
			check(t, accessTx(t, governance.ActivationModeActive, now.Add(time.Minute), false), input(op), governance.AccessNewAdmission)
		})
	}
}

func TestUnknownActivationModeIsDenied(t *testing.T) {
	for _, op := range []string{"complete_unsettled_request", "bind_existing_mapping", "checkpoint_ingest", "new_admission"} {
		t.Run(op, func(t *testing.T) {
			check(t, accessTx(t, "UNKNOWN_MODE", time.Time{}, false), input(op), governance.AccessDenied)
		})
	}
}

func TestUnknownOperationIsDenied(t *testing.T) {
	states := []struct {
		name        string
		mode        string
		expiry      time.Time
		missingHead bool
	}{
		{"active_unexpired", governance.ActivationModeActive, now.Add(time.Minute), false},
		{"stop_new", governance.ActivationModeStopNew, time.Time{}, false},
		{"active_expired", governance.ActivationModeActive, now.Add(-time.Minute), false},
		{"missing_head", "", time.Time{}, true},
	}
	for _, state := range states {
		t.Run(state.name, func(t *testing.T) {
			check(t, accessTx(t, state.mode, state.expiry, state.missingHead), input("future_operation"), governance.AccessDenied)
		})
	}
}
