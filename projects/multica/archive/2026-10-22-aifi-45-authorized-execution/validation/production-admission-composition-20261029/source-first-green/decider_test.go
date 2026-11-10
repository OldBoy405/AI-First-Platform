// AIFIRST: AIFI-45 production runner configuration must reject missing deciders.
package admissionguard_test

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/multica-ai/multica/server/internal/governance"
)

type pointerDecider struct{}
type valueDecider struct{}
type funcDecider func()
type mapDecider map[string]int
type sliceDecider []int
type chanDecider chan int

func (*pointerDecider) DecideAdmission(context.Context, pgx.Tx, governance.AdmissionRequest) (governance.AdmissionDecision, error) {
	return governance.AdmissionDecision{}, nil
}
func (valueDecider) DecideAdmission(context.Context, pgx.Tx, governance.AdmissionRequest) (governance.AdmissionDecision, error) {
	return governance.AdmissionDecision{}, nil
}
func (funcDecider) DecideAdmission(context.Context, pgx.Tx, governance.AdmissionRequest) (governance.AdmissionDecision, error) {
	return governance.AdmissionDecision{}, nil
}
func (mapDecider) DecideAdmission(context.Context, pgx.Tx, governance.AdmissionRequest) (governance.AdmissionDecision, error) {
	return governance.AdmissionDecision{}, nil
}
func (sliceDecider) DecideAdmission(context.Context, pgx.Tx, governance.AdmissionRequest) (governance.AdmissionDecision, error) {
	return governance.AdmissionDecision{}, nil
}
func (chanDecider) DecideAdmission(context.Context, pgx.Tx, governance.AdmissionRequest) (governance.AdmissionDecision, error) {
	return governance.AdmissionDecision{}, nil
}

func TestRequireAdmissionDecider(t *testing.T) {
	var p *pointerDecider
	var f funcDecider
	var m mapDecider
	var s sliceDecider
	var c chanDecider
	cases := []struct {
		name      string
		d         governance.AdmissionDecider
		wantError bool
	}{
		{"nil_interface", nil, true},
		{"nil_pointer", p, true},
		{"nil_function", f, true},
		{"nil_map", m, true},
		{"nil_slice", s, true},
		{"nil_channel", c, true},
		{"pointer", &pointerDecider{}, false},
		{"value", valueDecider{}, false},
		{"function", funcDecider(func() {}), false},
		{"map", mapDecider{}, false},
		{"slice", sliceDecider{}, false},
		{"channel", make(chanDecider), false},
		{"real_decider", governance.NewAdmissionDecider(), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := governance.RequireAdmissionDecider(tc.d)
			if tc.wantError {
				if !errors.Is(err, governance.ErrAdmissionDeciderRequired) {
					t.Fatalf("got %v, want ErrAdmissionDeciderRequired", err)
				}
			} else if err != nil {
				t.Fatalf("got unexpected error: %v", err)
			}
		})
	}
}
