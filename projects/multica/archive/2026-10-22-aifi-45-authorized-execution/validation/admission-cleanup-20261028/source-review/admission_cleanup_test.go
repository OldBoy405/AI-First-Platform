// AIFIRST: AIFI-45 admission transaction ownership is established before callbacks.
package runnerquery_test

import (
	"go/ast"
	"go/parser"
	"go/token"
	"testing"
)

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
	if fn == nil || fn.Body == nil {
		t.Fatal("decideUnderHeadLock not found")
	}
	var begin, lock, decide, guardedRollback token.Pos
	for _, stmt := range fn.Body.List {
		if d, ok := stmt.(*ast.DeferStmt); ok {
			lit, ok := d.Call.Fun.(*ast.FuncLit)
			if !ok {
				continue
			}
			var hasHandedGuard, hasRollback bool
			ast.Inspect(lit.Body, func(n ast.Node) bool {
				if id, ok := n.(*ast.Ident); ok && id.Name == "handed" {
					hasHandedGuard = true
				}
				if call, ok := n.(*ast.CallExpr); ok {
					if sel, ok := call.Fun.(*ast.SelectorExpr); ok && sel.Sel.Name == "Rollback" {
						if id, ok := sel.X.(*ast.Ident); ok && id.Name == "tx" {
							hasRollback = true
						}
					}
				}
				return true
			})
			if hasHandedGuard && hasRollback {
				guardedRollback = d.Pos()
			}
		}
		ast.Inspect(stmt, func(n ast.Node) bool {
			call, ok := n.(*ast.CallExpr)
			if !ok {
				return true
			}
			if id, ok := call.Fun.(*ast.Ident); ok && id.Name == "lockExecutionAuthorizationHead" {
				lock = call.Pos()
			}
			if sel, ok := call.Fun.(*ast.SelectorExpr); ok {
				switch sel.Sel.Name {
				case "BeginTx":
					begin = call.Pos()
				case "DecideAdmission":
					decide = call.Pos()
				}
			}
			return true
		})
	}
	if begin == token.NoPos || lock == token.NoPos || decide == token.NoPos || guardedRollback == token.NoPos ||
		!(begin < guardedRollback && guardedRollback < lock && guardedRollback < decide) {
		t.Fatal("guarded rollback must be installed after BeginTx and before lock or decider")
	}
}
