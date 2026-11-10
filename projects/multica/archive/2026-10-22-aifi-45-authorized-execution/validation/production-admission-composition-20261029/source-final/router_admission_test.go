// AIFIRST: AIFI-45 runner composition must reject missing admission before wiring.
package runnerquery_test

import (
	"go/ast"
	"go/parser"
	"go/token"
	"testing"
)

// This checks source structure only; it does not execute server startup.
func TestRouterRequiresAdmissionBeforeConstructingRunner(t *testing.T) {
	file, err := parser.ParseFile(token.NewFileSet(), "../../../cmd/server/router.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	imports := 0
	for _, item := range file.Imports {
		if item.Path.Value == `"github.com/multica-ai/multica/server/internal/governance"` {
			imports++
			if item.Name != nil && item.Name.Name != "governance" {
				t.Fatal("governance import must not use another alias or dot import")
			}
		}
	}
	if imports != 1 {
		t.Fatal("expected one governance import")
	}
	var router *ast.FuncDecl
	for _, decl := range file.Decls {
		if fn, ok := decl.(*ast.FuncDecl); ok && fn.Name.Name == "NewRouterWithOptions" {
			router = fn
		}
	}
	if router == nil || router.Body == nil {
		t.Fatal("router function not found")
	}
	var enabled *ast.IfStmt
	for _, stmt := range router.Body.List {
		if candidate, ok := stmt.(*ast.IfStmt); ok {
			if _, ok := selectorCall(candidate.Cond, "governance", "ArchitectureRunnerEnabled"); ok {
				if enabled != nil {
					t.Fatal("multiple runner-enabled blocks")
				}
				enabled = candidate
			}
		}
	}
	if enabled == nil || enabled.Else != nil || len(enabled.Body.List) < 2 {
		t.Fatal("runner-enabled block missing")
	}
	guard, ok := enabled.Body.List[0].(*ast.IfStmt)
	if !ok || guard.Else != nil {
		t.Fatal("runner-enabled block must start with admission guard")
	}
	assign, ok := guard.Init.(*ast.AssignStmt)
	if !ok || assign.Tok != token.DEFINE || len(assign.Lhs) != 1 || !named(assign.Lhs[0], "err") || len(assign.Rhs) != 1 {
		t.Fatal("admission guard must assign its error")
	}
	call, ok := selectorCall(assign.Rhs[0], "governance", "RequireAdmissionDecider")
	if !ok || len(call.Args) != 1 {
		t.Fatal("admission guard must validate the configured decider")
	}
	arg, ok := call.Args[0].(*ast.SelectorExpr)
	if !ok || !named(arg.X, "opts") || arg.Sel.Name != "AdmissionDecider" {
		t.Fatal("admission guard must validate opts.AdmissionDecider")
	}
	cond, ok := guard.Cond.(*ast.BinaryExpr)
	if !ok || cond.Op != token.NEQ || !named(cond.X, "err") || !named(cond.Y, "nil") {
		t.Fatal("admission guard must check err != nil")
	}
	if len(guard.Body.List) != 2 {
		t.Fatal("admission failure body must contain only log and exit")
	}
	logStmt, ok := guard.Body.List[0].(*ast.ExprStmt)
	if !ok {
		t.Fatal("admission failure must log first")
	}
	if _, ok := selectorCall(logStmt.X, "slog", "Error"); !ok {
		t.Fatal("admission failure must log first")
	}
	exitStmt, ok := guard.Body.List[1].(*ast.ExprStmt)
	if !ok {
		t.Fatal("admission failure must exit")
	}
	exitCall, ok := selectorCall(exitStmt.X, "os", "Exit")
	if !ok || len(exitCall.Args) != 1 {
		t.Fatal("admission failure must exit")
	}
	exitArg, ok := exitCall.Args[0].(*ast.BasicLit)
	if !ok || exitArg.Kind != token.INT || exitArg.Value != "1" {
		t.Fatal("admission failure must exit with status 1")
	}
	if len(enabled.Body.List) < 3 {
		t.Fatal("runner constructor missing")
	}
	decl, ok := enabled.Body.List[1].(*ast.DeclStmt)
	if !ok {
		t.Fatal("unexpected statement between guard and constructor")
	}
	gen, ok := decl.Decl.(*ast.GenDecl)
	if !ok || gen.Tok != token.VAR || len(gen.Specs) != 1 {
		t.Fatal("expected only runner error declaration")
	}
	spec, ok := gen.Specs[0].(*ast.ValueSpec)
	if !ok || len(spec.Names) != 1 || spec.Names[0].Name != "runnerErr" || !named(spec.Type, "error") || len(spec.Values) != 0 {
		t.Fatal("expected only uninitialized runnerErr")
	}
	construction, ok := enabled.Body.List[2].(*ast.AssignStmt)
	if !ok || construction.Tok != token.ASSIGN || len(construction.Lhs) != 2 ||
		!named(construction.Lhs[0], "architectureRunner") || !named(construction.Lhs[1], "runnerErr") || len(construction.Rhs) != 1 {
		t.Fatal("runner constructor must assign the outer runner and error directly after guard")
	}
	ctor, ok := selectorCall(construction.Rhs[0], "governance", "NewRunnerWithOptions")
	if !ok || len(ctor.Args) != 4 {
		t.Fatal("expected NewRunnerWithOptions with four arguments")
	}
	options, ok := ctor.Args[3].(*ast.CompositeLit)
	if !ok {
		t.Fatal("runner options must be a literal")
	}
	optionsType, ok := options.Type.(*ast.SelectorExpr)
	if !ok || !named(optionsType.X, "governance") || optionsType.Sel.Name != "RunnerOptions" {
		t.Fatal("runner options must be governance.RunnerOptions")
	}
	deciders := 0
	for _, element := range options.Elts {
		field, ok := element.(*ast.KeyValueExpr)
		if !ok || !named(field.Key, "AdmissionDecider") {
			continue
		}
		value, ok := field.Value.(*ast.SelectorExpr)
		if !ok || !named(value.X, "opts") || value.Sel.Name != "AdmissionDecider" {
			t.Fatal("runner must receive the validated decider")
		}
		deciders++
	}
	if deciders != 1 {
		t.Fatal("runner must receive exactly one AdmissionDecider")
	}
	constructors := 0
	ast.Inspect(file, func(node ast.Node) bool {
		if call, ok := node.(*ast.CallExpr); ok {
			if _, ok := selectorCall(call, "governance", "NewRunner"); ok {
				t.Error("router must not use the unguarded NewRunner constructor")
			}
			if _, ok := selectorCall(call, "governance", "NewRunnerWithOptions"); ok {
				constructors++
				if call.Pos() < guard.End() || call.Pos() >= enabled.Body.End() {
					t.Error("runner constructor must follow the guard in enabled block")
				}
			}
		}
		return true
	})
	if constructors != 1 {
		t.Fatalf("runner constructors = %d, want 1", constructors)
	}
}
