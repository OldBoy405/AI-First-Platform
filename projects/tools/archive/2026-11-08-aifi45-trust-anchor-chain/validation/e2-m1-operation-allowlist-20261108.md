# M1：绑定签发 operation 白名单（2026-11-08）

## 缺口（已核实）

`server/internal/governance/execution_binding_issue.go` 对挑战里的 `operation` **只校验名称形状**：

```go
if json.Unmarshal(challenge["operation"], &out.Challenge.Operation) != nil ||
    !executionBindingOperationRE.MatchString(out.Challenge.Operation) {
    return out, errors.New("operation must be a canonical operation name")
}
```

因此形状合法的任意 operation（如 `advance-any`），只要 head/claim 合法就会被签名。
设计要的是「五个 operation 白名单，**不开放任意 nonce 代签**」——T 侧 `requireControlAdmission`
把 operation 当作绑定事实，M 侧若能任意命名，该绑定退化为可协商字符串。

## 修法（一处检查 + 一个负例）

- `execution_binding_issue.go`：既有形状校验之后加枚举白名单，名单外 → 既有
  `400 EXECUTION_BINDING_REQUEST_INVALID`，**在事务与签名之前**拒绝。
- 白名单取自 tools 侧 `lib/execution-binding.mjs` 的 `CONTROL_EXECUTION_OPERATIONS`：
  `authorization-bind`、`advance`、`repair-admit`、`repair-resume`、`register`、`archive`。
  设计文字写「五个写入口」，但 `repair/resume` 在实现里是两个 operation，故固定词汇为**六个**。
- 负例 `advance-any`：400、无 `envelope`、`cr_execution_binding_issue` 零行。

## 一处需要点明的测试改动

原 fixture 用 `implement-code` 当 operation。已核实 **`implement-code` 是管线节点名，不是绑定 operation**
（`crctl.mjs:1642` 的 `write: 'implement-code'` 是节点，而 `requestExecutionBinding` 只接受
`CONTROL_EXECUTION_OPERATIONS` 六个值）。所以把它改成 `advance` 是 fixture 卫生，不是放宽断言；
`assertEnvelope` 仍逐字段核对，只是期望值改为跟随 `challenge["operation"]`。

## 验证

```
go build ./...                                            exit 0
go vet ./internal/governance                              exit 0
go test ./internal/governance -run '^TestExecutionBindingIssue$'   PASS
  ├─ happy_path_issues_signed_envelope                     PASS
  └─ operation_whitelist_rejects_unknown_without_signing    PASS
go test ./internal/daemon -run 'TestExecutionBinding'      PASS
```

## 台账

multica `CUSTOM.md`：明细 `#305`、模块 `M25`、CR 索引 → 在途 change
`2026-10-22-aifi-45-authorized-execution`，核对基线行标注「在途，未合并」。
四数 `578 / 1610 / 690 / 278`，本次自身 +1 命中行 / +1 `AIFIRST`。

## 会不会挡住现有真实调用

不会：六个真实控制写入口全在名单内。会挡住的是仓外自定义 operation 名——这正是本次收紧的目的。
历史上已签发的非白名单 binding 不会被重签；T 侧本来也不接受这些 operation。
