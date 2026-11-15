# 整体方案与修订（2026-11-08 第二轮）

用户决定：**先补真实 M 闭环再签 Gate 3**。上一轮 M2 实测把闭环卡在了 M 的启动门。
本文件说明「为什么这仍然是一处改动，而不是十个功能」，以及按什么边界实施。

## 修订一：我上一轮的「3/4 已存在」结论要再收一格

函数确实都在，但**闭环要求的那个组合没有人做**：

| 已有 | 位置 |
|---|---|
| 真实签发路由与 DB 归属 | `execution_authorization_http.go:204` → `BuildExecutionAuthorization` |
| daemon-owned trust root 安装 | `execution_trust.go` |
| binding 签发（含白名单） | `execution_binding_issue.go` |
| challenge 中继（daemon 亲启 crctl） | `execution_binding_relay.go` + `executionBindingEndpointForRun` |
| 静态检查 | `execution_verifier.go:78-108`（跑 `authorization-bind --check`，并**要求** `bound=false`、`current_head_verified=false`、`source_verified=false`） |
| **静态检查之后** | **无**：`execution_verifier.go:62-68` 无条件返回 `EXECUTION_CONSUMPTION_REQUIRED` |

所以缺口是**一段**：静态检查之后应当「核对当前 head / 撤销 / claim → 通过受保护通道真实消费 → 见到消费凭据才放行」。
它不是十个功能，也不是新机制——四块积木都在，缺的是把它们接起来的那一段。

## 修订二：不接受「把 TC 判绿」这条捷径

三条 TC（001/002/004）的真实事实在上一轮已经拿到（HTTP 201、14 个 json-pointer 绑定、
digest 等于原始 bytes 的 SHA-256、DB 归属、trust root 安装）。剩下的不是「再补一条断言」，
而是**缺一次真实的非只读消费**。所以做法是产出那个事实，不是调整判定。

## 方案：一处接线，四条判据

在 `execution_verifier.go` 把无条件错误替换为一段可判定的序列，**全部复用既有组件**：

1. **当前 head**：用既有 `HandleDaemonExecutionAuthorizationHead` 的客户端等价物取当前 head，与安装的 grant 比对；不符 → 拒绝。
2. **撤销**：撤销链判定沿用既有 `readGrantForCR`/revocation 语义（T 侧已有），M 侧只要求「head 上不存在撤销」的事实。
3. **claim**：`GetTaskExecutionClaim` 已取，比对 daemon/run/claim 归属；不符 → 拒绝（已有）。
4. **真实消费**：用既有 `relayExecutionBinding` 让 daemon 亲启的 crctl 走一次**非只读** `authorization-bind`
   （`--binding-stdio`，challenge 由 `executionBindingEndpointForRun` 签），拿到 receipt；
   再向既有 consumption 端点确认该 receipt 已落库。
5. 只有 1–4 全部成立才 `return nil`（放行 agent）；任一缺失 → 返回**具体**失败码，**不启动 agent**。

边界（避免过度设计）：

- 不新增账本、新表、新端点、新签名域；不改 governance 的签发与白名单。
- 不放宽 `validateExecutionCheckOutput`（静态检查仍要求 `bound=false`，它是「静态」的证据）。
- 不放宽 legacy：非 strict 合同路径完全不变。
- 每一步失败都 fail-closed，且错误码可区分（便于 T 侧与运维判断是哪一环）。

## 为什么这是「尽可能少的检查」

闭环只需要**一个**判定：`admit = head 一致 ∧ 无撤销 ∧ claim 一致 ∧ 已有真实消费凭据`。
它用一个谓词替换一句无条件拒绝，不引入第二套准入逻辑；T 侧 `requireControlAdmission` 仍是同一份事实的消费方。

## 之后会发生什么

- 重跑 M2：真实非只读消费走通后，**TC-TAC-001/002/004/006/007/008/009/010** 才可能从条款级升整条。
- **TC-TAC-005** 保持条款级：Linux 半侧已有真实内核拒绝证据（`e2-linux-key-isolation-20261108/`），
  Windows 半侧按已裁决的 C 是**部署前置**，不在本 change 关闭。
- 三条 ADJ 的关闭仍需各自判据全部满足；闭环走通不等于 ADJ 自动关闭。

## 不做

- 不做 Windows 受限令牌驱动（与已裁决 C 一致）。
- 不为闭环引入 CA/PKI、第二本账、原生依赖。
- 不改归档 change 的冻结产物。
- 不把一次性实例的闭环证据写成生产可用。
