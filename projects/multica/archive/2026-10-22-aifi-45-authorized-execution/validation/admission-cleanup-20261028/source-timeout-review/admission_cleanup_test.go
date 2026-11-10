// AIFIRST: AIFI-45 admission transaction ownership is established before callbacks.
package runnerquery_test

import (
	"go/ast"
	"go/parser"
	"go/token"
	"testing"
)

func named(n ast.Expr, name string) bool {
	id, ok := n.(*ast.Ident)
	return ok && id.Name == name
}

func selectorCall(n ast.Expr, receiver, method string) (*ast.CallExpr, bool) {
	call, ok := n.(*ast.CallExpr)
	if !ok {
		return nil, false
	}
	sel, ok := call.Fun.(*ast.SelectorExpr)
	return call, ok && named(sel.X, receiver) && sel.Sel.Name == method
}

// This source-level regression does not execute a transaction or prove lock release.
func TestAdmissionRollbackGuardPrecedesLockAndDecider(t *testing.T) {
	file, err := parser.ParseFile(token.NewFileSet(), "../execution_admission_gate.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	var fn *ast.FuncDecl
	for _, d := range file.Decls {
		if f, ok := d.(*ast.FuncDecl); ok && f.Recv != nil && f.Name.Name == "decideUnderHeadLock" {
			fn = f
		}
	}
	if fn == nil || fn.Body == nil || len(fn.Body.List) < 6 {
		t.Fatal("decideUnderHeadLock body not found")
	}
	body := fn.Body.List
	begin, ok := body[0].(*ast.AssignStmt)
	if !ok || len(begin.Lhs) != 2 || !named(begin.Lhs[0], "tx") || !named(begin.Lhs[1], "err") || len(begin.Rhs) != 1 {
		t.Fatal("first statement must begin the transaction")
	}
	beginCall, ok := begin.Rhs[0].(*ast.CallExpr)
	if !ok {
		t.Fatal("BeginTx is not a call")
	}
	beginSel, ok := beginCall.Fun.(*ast.SelectorExpr)
	if !ok || beginSel.Sel.Name != "BeginTx" {
		t.Fatal("first statement must call BeginTx")
	}
	check, ok := body[1].(*ast.IfStmt)
	if !ok || check.Init != nil || check.Else != nil || len(check.Body.List) != 1 {
		t.Fatal("BeginTx error must be checked immediately")
	}
	comparison, ok := check.Cond.(*ast.BinaryExpr)
	if !ok || comparison.Op != token.NEQ || !named(comparison.X, "err") || !named(comparison.Y, "nil") {
		t.Fatal("BeginTx error guard must check err != nil")
	}
	ret, ok := check.Body.List[0].(*ast.ReturnStmt)
	if !ok || len(ret.Results) != 3 || !named(ret.Results[0], "nil") || !named(ret.Results[2], "err") {
		t.Fatal("BeginTx error must return without handing out a transaction")
	}
	init, ok := body[2].(*ast.AssignStmt)
	if !ok || init.Tok != token.DEFINE || len(init.Lhs) != 1 || !named(init.Lhs[0], "handed") || len(init.Rhs) != 1 || !named(init.Rhs[0], "false") {
		t.Fatal("ownership must initially be unhanded")
	}
	guard, ok := body[3].(*ast.DeferStmt)
	if !ok {
		t.Fatal("rollback guard must immediately follow ownership initialization")
	}
	lit, ok := guard.Call.Fun.(*ast.FuncLit)
	if !ok || len(guard.Call.Args) != 0 || len(lit.Body.List) != 1 {
		t.Fatal("rollback guard must defer a zero-argument closure")
	}
	conditional, ok := lit.Body.List[0].(*ast.IfStmt)
	if !ok || conditional.Init != nil || conditional.Else != nil || len(conditional.Body.List) != 1 {
		t.Fatal("rollback guard must have a single condition")
	}
	negation, ok := conditional.Cond.(*ast.UnaryExpr)
	if !ok || negation.Op != token.NOT || !named(negation.X, "handed") {
		t.Fatal("rollback guard must require !handed")
	}
	rollback, ok := conditional.Body.List[0].(*ast.AssignStmt)
	if !ok || rollback.Tok != token.ASSIGN || len(rollback.Lhs) != 1 || !named(rollback.Lhs[0], "_") || len(rollback.Rhs) != 1 {
		t.Fatal("rollback guard must call tx.Rollback")
	}
	rollbackCall, ok := selectorCall(rollback.Rhs[0], "tx", "Rollback")
	if !ok || len(rollbackCall.Args) != 1 {
		t.Fatal("rollback guard must call tx.Rollback with a context")
	}
	background, ok := selectorCall(rollbackCall.Args[0], "context", "Background")
	if !ok || len(background.Args) != 0 {
		t.Fatal("rollback must use context.Background")
	}
	assignments := 0
	var firstLock, firstDecide token.Pos
	ast.Inspect(fn.Body, func(n ast.Node) bool {
		if assign, ok := n.(*ast.AssignStmt); ok {
			for _, lhs := range assign.Lhs {
				if named(lhs, "handed") {
					assignments++
				}
			}
		}
		call, ok := n.(*ast.CallExpr)
		if !ok {
			return true
		}
		if named(call.Fun, "lockExecutionAuthorizationHead") && firstLock == token.NoPos {
			firstLock = call.Pos()
		}
		if sel, ok := call.Fun.(*ast.SelectorExpr); ok && sel.Sel.Name == "DecideAdmission" && firstDecide == token.NoPos {
			firstDecide = call.Pos()
		}
		return true
	})
	if firstLock == token.NoPos || firstDecide == token.NoPos || guard.Pos() >= firstLock || guard.Pos() >= firstDecide {
		t.Fatal("guard must precede the first lock and decider call")
	}
	handoff, ok := body[len(body)-2].(*ast.AssignStmt)
	if !ok || handoff.Tok != token.ASSIGN || len(handoff.Lhs) != 1 || !named(handoff.Lhs[0], "handed") || len(handoff.Rhs) != 1 || !named(handoff.Rhs[0], "true") || assignments != 2 {
		t.Fatal("ownership may transfer only once, at the final handoff")
	}
	final, ok := body[len(body)-1].(*ast.ReturnStmt)
	if !ok || len(final.Results) != 3 || !named(final.Results[0], "tx") || !named(final.Results[2], "nil") {
		t.Fatal("ownership handoff must immediately return the transaction")
	}
}
