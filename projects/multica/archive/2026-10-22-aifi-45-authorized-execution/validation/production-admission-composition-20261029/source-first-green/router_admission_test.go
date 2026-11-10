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
	exits := 0
	for _, stmt := range guard.Body.List {
		expr, ok := stmt.(*ast.ExprStmt)
		if !ok {
			continue
		}
		call, ok := selectorCall(expr.X, "os", "Exit")
		if ok && len(call.Args) == 1 {
			arg, ok := call.Args[0].(*ast.BasicLit)
			if ok && arg.Kind == token.INT && arg.Value == "1" {
				exits++
			}
		}
	}
	if exits != 1 {
		t.Fatal("admission failure must exit")
	}
	constructors := 0
	ast.Inspect(file, func(node ast.Node) bool {
		if call, ok := node.(*ast.CallExpr); ok {
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
