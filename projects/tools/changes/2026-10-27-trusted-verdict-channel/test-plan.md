# 可信 T committed verdict channel — tools 测试方案

> Gate 2 已确认，BUILD 进行中（长程模式）：已跑 TC 见 multica 侧 `validation/evidence-index.md`，其余仍未实现；未跑即未验证。
> 设计输入：前身 change `validation/trusted-verdict-channel-implementation-plan-20261026.md`（v0.6.5）。
> 跨仓 multica 侧见[配套测试方案](../../../multica/changes/2026-10-27-trusted-verdict-channel/test-plan.md)。
> 必达 leaf 全名以 multica change 的 `validation/channel-test-expectations.json` 为唯一权威（SPEC 已冻结；R2.5 11 条 / R3.5 16 条 / S5 19 条）；本仓不另存副本。

## 一、测试策略

### 1.1 金字塔与边界

合并三族：①merge 范围（committed 区间与写集，19 leaf，按方案固定在 `test/execution-control-policy.test.mjs`）②`merge-facts`（只读事实客户端与码序，11 leaf）
③`merge-effects`（reserve/report、journal 三态与恢复矩阵，16 leaf）；T runtime 单独四族（protocol/store/worker+recovery/policy/readiness）。
真实 Git 临时仓 + 注入 publish 端口；不以退出码代替副作用断言。

### 1.2 安全与执行原则

- Gate 2 后才逐个 TC RED→GREEN；当前不跑真实 merge、不触碰真实 CR、不部署。
- 每条 mutation 必须让对应 leaf 的**断言**失败；超时、连接错、编译错、夹具错不计 RED；至少保留一个未受 mutation 影响的 PASS control leaf。
- 副作用断言注入 publish 端口并观测 journal/锁/outbox/Git 写命令，不只看退出码。
- `merge 范围核对越界零写入` 需**两条** mutation（移到 publish 之后；移到 journal 之后 prepare 之前）；
  `release-subject 缺失` 与 `无法核实` **共用**一条「缺省当空集合放行」mutation——这两处不对称必须显式写出。
- 行尾：源码 CRLF，新增文件先定一种并核 crlf/裸 LF；哈希与跨行解析前先 `\r\n → \n`。
- 原字节（已签 payload、pinned manifest、raw 证据）不规范化、不重序列化。

### 1.3 已有资产与拟新增

| 资产（相对 `crctl/scripts`） | 当前作用及限制 | 本轮处理 |
|---|---|---|
| `lib/change-scope.mjs` | 纯判定器：缺失/非数组 changes 已返回 `AUTH_SCOPE_INPUT_INVALID`（AIFI-45 已修），仅显式 `[]` 放行；`gitFields` 已用 `-z`、rename 双侧已查 | 判定器不改；`collectCommittedPaths` 复用 `gitFields` 与 rename 解析，新增采集完整性四证明 |
| `lib/workspace-transactions.mjs` | `mergeCr`（1986）、`verifyReleaseSubjects` | 插入范围核对；不改既有本地信任行为 |
| `lib/durable-tx.mjs` | best-effort fsync/recoverable write-set | 作为 store 基线，升级为冻结 envelope |
| `test/merge-tx.test.mjs`、`test/merge-release-recovery.test.mjs` | 既有 merge 回归 | 保留并扩展；不替换 |
| 新增 `lib/merge-facts-client.mjs`、`lib/merge-effects-client.mjs` | 无 | 端点调用、码序映射、journal 三态 |
| 新增 `lib/execution-control-{protocol,store,worker,readiness}.mjs` | 无 | T 侧运行时 |
| 新增 `test/execution-control-policy.test.mjs`、`test/merge-facts.test.mjs`、`test/merge-effects.test.mjs` | 无 | 46 条 merge leaf 的宿主（前者按方案固定，后两者本规格冻结） |

## 二、详细测试案例

### 功能 1：merge 范围核对（REQ-MG-001）

#### 案例 1.1 — 区间与批准来源

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-001 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-001 |
| **优先级** | P0 |
| **预置条件** | 临时仓含 release subject 之后的提交；`approval.yml` 与 M 记录相等/不等两套夹具 |
| **输入** | 执行范围核对 |
| **预期结果** | 区间为 `trunk...HEAD`；不等即 `AUTH_SCOPE_UNVERIFIABLE`；越界 `AUTH_SCOPE_VIOLATION` |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 1.2 — rename 与 symlink

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-002 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-002 |
| **优先级** | P0 |
| **预置条件** | 区间含 rename（源/目标一内一外）与 symlink 条目；工作树与实际树不一致 |
| **输入** | 采集 committed 路径 |
| **预期结果** | 源与目标都查；symlink 取自选定 tree/blob `120000`；不读工作树/index |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 1.3 — 空集合四证明

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-003 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-003 |
| **优先级** | P0 |
| **预置条件** | 仓集合缺项、取不到 SHA、采集失败、空路径无零改动证明、release subject 缺失 |
| **输入** | 汇总核对输入 |
| **预期结果** | 缺一即 `AUTH_SCOPE_UNVERIFIABLE`；不得把缺失当空集合 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 1.4 — selection 与 legacy

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-004 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-004 |
| **优先级** | P0 |
| **预置条件** | Unknown selection、目录缺行、可信目录证明的 legacy、Strict 删合同字段 |
| **输入** | 判定是否核对范围/要求 grant |
| **预期结果** | Unknown 拒；legacy 行为不变；Strict 删字段仍 strict |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 1.5 — 恢复输入同一性

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-005 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-005 |
| **优先级** | P0 |
| **预置条件** | 中止的 merge；期间 `approval.yml` 已变 |
| **输入** | 走既有恢复路径重入 |
| **预期结果** | 沿用原冻结输入；输入已变即拒 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 1.6 — 部分发布与零写入

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-006 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-006 |
| **优先级** | P0 |
| **预置条件** | 逐仓 publish 中途撤销；越界注入在 publish 后、journal 后 prepare 前 |
| **输入** | 继续发布或重入 |
| **预期结果** | 停止后续 publish 并保留 journal/receipt；publish 端口零调用 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 1.7 — grants 目录与 head 效力

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-007 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-007 |
| **优先级** | P0 |
| **预置条件** | 更宽的旧 grant 文件；首次读取后确定性交错撤销/前移 |
| **输入** | 解析当前授权并做效力检查 |
| **预期结果** | 不选「最新」文件；撤销/前移分别得 REVOKED/HEAD_MOVED；不按批准时快照判 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 1.8 — 状态推进与 finalize 写集

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-008 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-008 |
| **优先级** | P0 |
| **预置条件** | 越界后检查状态；finalize 三生成路径分别在/不在 `allowed_paths`；获批后 KB 写入 |
| **输入** | 结束核对或执行 finalize |
| **预期结果** | 状态保持 `code-approved`；三个路径逐项授权，漏列即拒；KB 写入被核对 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 2：merge-facts 客户端（REQ-MG-002）

#### 案例 2.1 — 认证与回退凭据

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-009 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-009 |
| **优先级** | P0 |
| **预置条件** | 真实 HTTP 夹具（他人 crID、三类回退凭据） |
| **输入** | 调用客户端并映射外层码 |
| **预期结果** | 404→UNVERIFIABLE；403→UNAVAILABLE；不传版本参数 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 2.2 — 批准下界

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-010 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-010 |
| **优先级** | P0 |
| **预置条件** | 严格祖先、非祖先、区间外祖先三套夹具 |
| **输入** | 本地祖先与区间校验 |
| **预期结果** | 仅严格祖先且区间内放行；其余 UNVERIFIABLE |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 2.3 — 仓库集合与摘要

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-011 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-011 |
| **优先级** | P0 |
| **预置条件** | 少仓、多仓、替换 repo_id、摘要不符 |
| **输入** | 校验计数、唯一性与摘要 |
| **预期结果** | 任一不符即 `AUTH_SCOPE_UNVERIFIABLE` |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 2.4 — 绑定三态与 legacy 证明

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-012 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-012 |
| **优先级** | P0 |
| **预置条件** | mismatch/unknown/ok；legacy 证明缺失与不符 |
| **输入** | 生成 findings 与外层码 |
| **预期结果** | mismatch→VIOLATION；unknown→UNVERIFIABLE；legacy 缺失/不符→UNVERIFIABLE |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 2.5 — 码优先级与不可用

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-013 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-013 |
| **优先级** | P0 |
| **预置条件** | 越界+不可核实并存；不可达/超时/5xx/400/未知 code；撤销；前移；多条当前行 |
| **输入** | 汇总外层码 |
| **预期结果** | `UNAVAILABLE>REVOKED>HEAD_MOVED>VIOLATION>UNVERIFIABLE`；非 200 一律 UNAVAILABLE |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 3：merge-effects 客户端（REQ-MG-003）

#### 案例 3.1 — 排序与锁

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-014 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-014 |
| **优先级** | P0 |
| **预置条件** | 撤销与 reserve 并发（钩位 `55P03`）；两种提交顺序 |
| **输入** | reserve 与后续 push |
| **预期结果** | 锁串行；撤销先→REVOKED 零 push；reserve 先→不追溯 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 3.2 — 远端分类

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-015 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-015 |
| **优先级** | P0 |
| **预置条件** | 远端含 expected；正常前进；confirmed 回退 prev |
| **输入** | 恢复判定 |
| **预期结果** | 不重推、不动作、判 history rewrite 三种动作 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 3.3 — intent 与 no_effect 恢复

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-016 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-016 |
| **优先级** | P0 |
| **预置条件** | journal intent + 远端 prev；服务端 settled_no_effect + journal unknown + 远端 prev |
| **输入** | 重入 merge |
| **预期结果** | 先 not_attempted 结算，再 attempt+1；不直接 push |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 3.4 — 分叉与延迟 push

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-017 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-017 |
| **优先级** | P0 |
| **预置条件** | 远端分叉；journal unknown 且远端仍 prev |
| **输入** | 判定是否继续发布 |
| **预期结果** | 分叉→uncertain 且禁止新 publish；延迟 push→保持 uncertain |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 3.5 — base 漂移与非 base 变化

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-018 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-018 |
| **优先级** | P0 |
| **预置条件** | 只改 base；base 与 head 不变只改候选 HEAD |
| **输入** | 继续推进原事务 |
| **预期结果** | `halted.reason=base_drift` / `input_mismatch`；不换 base 续跑 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 3.6 — finalize 也 reserve

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-019 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-019 |
| **优先级** | P0 |
| **预置条件** | finalize push 待发；reserve 时已撤销 |
| **输入** | 执行 finalize |
| **预期结果** | 先 reserve 再 push；撤销时 REVOKED 且不推送 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 3.7 — attempt 与码序

| 字段 | 内容 |
|------|------|
| **ID** | TC-MG-020 |
| **对应 Spec** | trusted-merge-gate/spec.md → Scenario: SC-MG-020 |
| **优先级** | P0 |
| **预置条件** | attempt 四支；head 前移且摘要不同；畸形/越权/他人 crID/不可用 |
| **输入** | 提交 reserve/report |
| **预期结果** | 200/200/201/409；HEAD_MOVED 不被遮盖；码序 INVALID>UNTRUSTED>NOT_FOUND；非授权失败不写 halted |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 4：T runtime（REQ-TR-001..005）

#### 案例 4.1 — 协议三元组

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-001 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-001 |
| **优先级** | P0 |
| **预置条件** | 正确/错 purpose/错 domain/错 scope/缺字段；Go 侧合法向量 |
| **输入** | `VerifyEnvelope` 与 digest 比较 |
| **预期结果** | 仅完全匹配通过；跨语言 digest 一致 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.2 — exact keys

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-002 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-002 |
| **优先级** | P0 |
| **预置条件** | 双 key 组、重复键、union 双分支、agent 可写路径 |
| **输入** | 加载 manifest 并验签 |
| **预期结果** | 越用途/重复键/非法路径全拒；只接受绝对路径+SHA256 pin |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.3 — 一次提交

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-003 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-003 |
| **优先级** | P0 |
| **预置条件** | 并发三请求；rename 前后 kill；fsync I/O 错误 |
| **输入** | `ApplyOnce` 与恢复后重投 |
| **预期结果** | 一次变化、原 bytes、fsync 失败无 frame |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.4 — 帧链

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-004 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-004 |
| **优先级** | P0 |
| **预置条件** | 断链、跳号、prev_digest 错、占位签名 |
| **输入** | 校验冻结 envelope 链 |
| **预期结果** | 全部拒；不当作追加授权 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.5 — fence

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-005 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-005 |
| **优先级** | P0 |
| **预置条件** | 旧 owner 与新 owner 各持一 fence |
| **输入** | 旧 worker 尝试写入 |
| **预期结果** | 旧 fence 新操作被拒 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.6 — 恢复表

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-006 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-006 |
| **优先级** | P0 |
| **预置条件** | tail 相同/领先一项/prepared/缺失/分叉 |
| **输入** | `ReconcileOwnerTx` |
| **预期结果** | 四类固定动作 + freeze；不建空 store、不清 slot |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.7 — restart 与 key rotation

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-007 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-007 |
| **优先级** | P0 |
| **预置条件** | 普通 restart、key rotation、缺 checkpoint 字段 |
| **输入** | 重启并继续服务 |
| **预期结果** | epoch/seq 不变、原 bytes 重发、历史用旧 key |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.8 — facts 与 repair

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-008 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-008 |
| **优先级** | P0 |
| **预置条件** | 未验签 payload；解码后自带额度 |
| **输入** | repair-admit 规则处理 |
| **预期结果** | 未验签拒；额度不来自 payload |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.9 — 追加 CAS

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-009 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-009 |
| **优先级** | P0 |
| **预置条件** | 两份并发追加 |
| **输入** | 处理追加 |
| **预期结果** | 只有一份被接受，另一份按原结果返回 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.10 — 合同投影

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-010 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-010 |
| **优先级** | P0 |
| **预置条件** | `cr.md` 字段被删/改空/改写 |
| **输入** | 读取合同判定 |
| **预期结果** | 以 store 为准并拒绝；不降 legacy |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.11 — sensitive 规则

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-011 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-011 |
| **优先级** | P0 |
| **预置条件** | 非精确 target；复制根后新 operation；同 operation 重放 |
| **输入** | 执行专项规则 |
| **预期结果** | 只允许精确目标；新 operation 耗尽；重放原 receipt |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

#### 案例 4.12 — readiness 求值

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-012 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-012 |
| **优先级** | P0 |
| **预置条件** | 空/缺/重复/unknown/NA 绕过/marker-only；合法非空 profile |
| **输入** | `EvaluateDeploymentReadiness` |
| **预期结果** | 宽松输入 NOT_READY；正例通过；verify-channel 只出 READY_COMPONENT |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施） |

### 功能 5：P0 隔离证明（REQ-TR-006）

#### 案例 5.1 — T 侧身份隔离

| 字段 | 内容 |
|------|------|
| **ID** | TC-TR-013 |
| **对应 Spec** | verdict-channel-runtime/spec.md → Scenario: SC-TR-013 |
| **优先级** | P0 |
| **预置条件** | 获授权 Linux 与 Windows 测试机、批准 profile（真实不同受限身份、actual launcher） |
| **输入** | 同 UID/同令牌 SID profile；agent 读 key、写 store、连 IPC、替换 Node/模块、注入 env/F1 |
| **预期结果** | 同身份 profile 不合格；攻击全不产生 accepted verdict；受限服务身份签发验证成功；两平台各自出证 |
| **当前状态** | ❌ 测试缺（Gate 2 草案，未实施）；环境未获授权前不可执行 |

## 三、追溯矩阵

| Requirement | Scenario | 测试文件 | leaf 数 |
|---|---|---|---|
| REQ-MG-001 | SC-MG-001..008 | `execution-control-policy.test.mjs` | 19（S5 全量） |
| REQ-MG-002 | SC-MG-009..013 | `merge-facts.test.mjs` | 11（R2.5 全量） |
| REQ-MG-003 | SC-MG-014..020 | `merge-effects.test.mjs` | 16（R3.5 全量） |
| REQ-TR-001 | SC-TR-001/002 | `execution-control-protocol.test.mjs` | 2 |
| REQ-TR-002 | SC-TR-003/004 | `execution-control-store.test.mjs` | 2 |
| REQ-TR-003 | SC-TR-005..007 | `execution-control-worker.test.mjs`、`-recovery.test.mjs` | 3 |
| REQ-TR-004 | SC-TR-008..011 | `execution-control-policy.test.mjs` | 4 |
| REQ-TR-005 | SC-TR-012 | `execution-control-readiness.test.mjs` | 2 |
| REQ-TR-006 | SC-TR-013 | `execution-control-isolation.test.mjs`（Linux/Windows 分别） | 3 + 2 |

不对称记录（清单必须显式写出，不得用「N:N 一一对应」概括）：
- `merge 范围核对越界零写入` 需要**两条** mutation（移到 publish 之后；移到 journal 之后 prepare 之前）。
- `merge 范围 release-subject 缺失即拒` 与 `merge 范围无法核实即拒` **共用**一条「缺省当空集合放行」mutation。

## 四、执行矩阵与未验证声明

| 模块 | 单元 | 集成 | 状态 |
|---|---|---|---|
| merge 范围（19 leaf） | 纯采集/判定 | 临时 Git + 注入 publish 端口 | 未实施 |
| merge-facts（11 leaf） | 码序映射 | 真实 HTTP（multica 端点） | 未实施 |
| merge-effects（16 leaf） | journal 三态 | 真实 HTTP + 文件 journal | 未实施 |
| T runtime | store/worker/fence | 故障注入 + 跨语言向量 | 未实施 |
| readiness | 纯求值 | 真实 DB CAS（multica 侧） | 未实施 |

- 本仓 33 个 TC **全部未实现、未运行**；不提供通过率。
- 未做真实 merge、未触碰真实 CR、未部署；P0 隔离与 S8 profile 未定前记 UNVERIFIED。
- 通道组件通过不自动回填 AIFI-45 的 41/49；其 6 条 RUN 类 TC 的重跑前置见 deliver 产物。
