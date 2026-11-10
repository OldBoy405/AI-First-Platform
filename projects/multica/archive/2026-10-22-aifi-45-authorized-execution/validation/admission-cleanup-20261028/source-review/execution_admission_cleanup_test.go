// AIFIRST: AIFI-45 admission decider panic must not strand the head lock.
package governance

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

type admissionPanicProbe struct {
	t        *testing.T
	crID     string
	tx       pgx.Tx
	probeErr error
}

func (d *admissionPanicProbe) DecideAdmission(_ context.Context, tx pgx.Tx, _ AdmissionRequest) (AdmissionDecision, error) {
	d.tx = tx
	d.probeErr = probeFromAnotherConnection(d.t,
		`UPDATE cr SET execution_authorization_head_id=NULL WHERE workspace_id=$1::uuid AND cr_id=$2`,
		testWorkspaceID, d.crID)
	panic("admission-panic-probe")
}

func TestAdmissionDeciderPanicReleasesHeadLock(t *testing.T) {
	if testPool == nil {
		t.Fatal("lock probe needs the disposable database")
	}
	fixture := newAdmissionLockFixture(t)
	decider := &admissionPanicProbe{t: t, crID: fixture.crID}
	// This cleanup runs before the fixture cleanup, including on the old broken
	// implementation. It prevents a failed probe from leaving a lock behind.
	t.Cleanup(func() {
		if decider.tx != nil {
			_ = decider.tx.Rollback(context.Background())
		}
	})
	runner := &Runner{pool: testPool, decider: decider}
	panicked := false
	func() {
		defer func() {
			value := recover()
			if value == "admission-panic-probe" {
				panicked = true
			} else if value != nil {
				panic(value)
			}
		}()
		_, _, _ = runner.decideUnderHeadLock(context.Background(), runnerID(testWorkspaceID), fixture.crID)
	}()
	if !panicked || decider.tx == nil {
		t.Fatal("decider did not panic after receiving the transaction")
	}
	if !lockNotAvailable(decider.probeErr) {
		t.Fatalf("pre-panic probe did not report SQLSTATE 55P03: %v", decider.probeErr)
	}

	// A successful, matching update is required after the panic. A timeout,
	// permission error, or zero rows must not count as lock-release evidence.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	conn, err := testPool.Acquire(ctx)
	if err != nil {
		t.Fatalf("acquire post-panic probe: %v", err)
	}
	defer conn.Release()
	if _, err = conn.Exec(ctx, `SET lock_timeout = '300ms'`); err != nil {
		t.Fatalf("set lock timeout: %v", err)
	}
	defer func() { _, _ = conn.Exec(context.Background(), `SET lock_timeout = DEFAULT`) }()
	tag, err := conn.Exec(ctx, `UPDATE cr SET execution_authorization_head_id=NULL WHERE workspace_id=$1::uuid AND cr_id=$2`, testWorkspaceID, fixture.crID)
	if err != nil {
		t.Fatalf("post-panic update was not released: %v", err)
	}
	if tag.RowsAffected() != 1 {
		t.Fatalf("post-panic update affected %d rows, want 1", tag.RowsAffected())
	}
}
