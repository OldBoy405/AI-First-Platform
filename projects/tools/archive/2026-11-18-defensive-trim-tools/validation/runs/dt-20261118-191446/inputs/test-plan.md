# Tools 防御性编程精简：测试方案与详细案例

> 版本：2026-11-18-defensive-trim-tools；创建日期：2026-11-18  
> 对应 Phase 2 Spec：`canonical/specs/code/{evidence-delivery-contract,writeback-source-consistency,output-guard-escape-hatch}.yaml`

## 一、测试策略

### 1.1 测试金字塔
交付与回写走真实 CLI 或固定生成器；OutputGuard 走公开 Pre/Post 入口。

### 1.2 测试原则
夹具真正省略缺省参数（`components` 缺省与 `[]` 分开测）；命令型 CP 断言 `pass 1 fail 0`，避免零用例退出 0；Windows 下不用带引号的 glob。

### 1.3 已有测试资产
交付 `evidence-delivery-gate.test.mjs`、生成 `writeback.test.mjs`、事务 `writeback-tx.test.mjs`、OutputGuard `core.test.mjs`。

## 二、详细测试案例

### 功能 1：交付配置与就绪

#### 配置读错或非列表（SC-EVD-101）

| 字段 | 内容 |
|---|---|
| **ID** | TC-EVD-101 |
| 预置 | 已选合同且其余证据齐全；用临时 linked worktree 分离可用安装根和交付根。 |
| 操作 | 仅在交付根造成文件缺失、目录替代文件或 `components` 非列表（含显式 `null`），运行 `evidence-check`。 |
| 预期 | 退出 `1`，报 `EVIDENCE_COMPONENT_CONFIG_INVALID`、交付配置路径和原因，无放行输出。 |

#### 缺省及空列表（SC-EVD-101）

| 字段 | 内容 |
|---|---|
| **ID** | TC-EVD-102 |
| 预置 | 合同 CR 其余证据齐全，分别从配置中省略 `components` 键、明确写 `components: []`。 |
| 操作 | 分别运行 `evidence-check`。 |
| 预期 | 两者均退出 `0`，`decision: deliver`。 |

#### 旧合同和合同诊断优先（SC-EVD-102）

| 字段 | 内容 |
|---|---|
| **ID** | TC-EVD-103 |
| 预置 | 交付配置有同一错误；分别准备证据齐全的真正 legacy CR 和命中合同非法、登记非法、降级、不一致的 CR。 |
| 操作 | 运行真实 `evidence-check`。 |
| 预期 | legacy 仍 `deliver`，其他各报原合同错误码并 `blocked`，均无配置错误。 |

#### 匹配、阻断与原始原因（SC-EVD-103）

| 字段 | 内容 |
|---|---|
| **ID** | TC-EVD-104 |
| 预置 | 合同 CR 有非空组件声明；含组件错配与授权或验证不满足的共存例。 |
| 操作 | 运行 `evidence-check`，对比匹配及错配等可达的声明与观测。 |
| 预期 | 匹配且证据齐全时 `deliver`；有组件 findings 时 `blocked`，核对原始 finding 的 `code`、`component`、关键原因、顺序及共存 finding。 |

### 功能 2：回写候选与续办

#### 正文和摘要同读（SC-WSC-001）

| 字段 | 内容 |
|---|---|
| **ID** | TC-WSC-001 |
| 预置 | 为 PRD/SDD、traceability、任务索引和规格索引准备有效的 UTF-8 CRLF 底稿 A。 |
| 操作 | 运行三个固定生成器的真实子进程，在夹具中于目标首次读出 A 后立即替换为 B。 |
| 预期 | 候选正文基于 A，`beforeSha256` 为 A 的 SHA-256。 |

#### 缺失与零字节（SC-WSC-002）

| 字段 | 内容 |
|---|---|
| **ID** | TC-WSC-002 |
| 预置 | 分别用缺失目标、空底稿、零字节任务索引和零字节规格索引。 |
| 操作 | 运行对应固定生成器。 |
| 预期 | 缺失的 `beforeSha256` 为 `null`；空底稿和空任务索引使用空内容的 SHA-256；空规格索引报 `STRUCTURE_MISMATCH`。 |

#### 生成侧读取失败（SC-WSC-003）

| 字段 | 内容 |
|---|---|
| **ID** | TC-WSC-003 |
| 预置 | 把三个生成器各自的目标文件换成目录。 |
| 操作 | 运行真实固定生成器。 |
| 预期 | 非零退出，诊断含目标路径和读错原因，无按缺失生成的候选。 |

#### 应用冲突（SC-WSC-004）

| 字段 | 内容 |
|---|---|
| **ID** | TC-WSC-004 |
| 预置 | 用 CRLF 底稿 A 生成，`writeback-after-journal-create` 在应用前中断；记录 origin。 |
| 操作 | 把 A 换成异于 before/after 的 B，原参续办 `writeback-apply`。 |
| 预期 | `TX_RECOVERY_CONFLICT` 报路径及 `before`/`after`/`actual`，B 字节不变且 origin 不前进。 |

#### 应用预检读取失败（SC-WSC-003）

| 字段 | 内容 |
|---|---|
| **ID** | TC-WSC-005 |
| 预置 | 临时 Tools 副本中的固定 baseline 生成脚本在产出正常候选后把一个候选目标换成目录。 |
| 操作 | 在该夹具中运行无 journal 的 `writeback-apply`，让其进入独立 before 预检。 |
| 预期 | 非零退出，报告目标路径与实际读错原因，而不是 `WRITEBACK_BEFORE_MISMATCH`。 |

#### 生成器升级后续办（SC-WSC-005）

| 字段 | 内容 |
|---|---|
| **ID** | TC-WSC-006 |
| 预置 | 用实际省略 spec/version/里程碑参数的 new mode 中断事务，记录 txId 和冻结候选，随后仅升级固定脚本。 |
| 操作 | 原样重跑 `writeback-apply`。 |
| 预期 | 以同一 txId 完成，只发布一次原候选内容。 |

#### 冻结 manifest 改变（SC-WSC-006）

| 字段 | 内容 |
|---|---|
| **ID** | TC-WSC-007 |
| 预置 | 中断事务后调整冻结 manifest 的 JSON 缩进，令字节改变但自摘要仍有效。 |
| 操作 | 以原参数续办，观察测试脚本的重生成标记及目标。 |
| 预期 | `TX_INPUT_CONFLICT`，无重生成，目标不变。 |

#### 冻结 blob 改变（SC-WSC-006）

| 字段 | 内容 |
|---|---|
| **ID** | TC-WSC-008 |
| 预置 | 另一中断事务仅改一个冻结 blob。 |
| 操作 | 以原参数续办，观察测试脚本的重生成标记及目标。 |
| 预期 | `WRITEBACK_BLOB_HASH_MISMATCH`，无重生成，目标不变。 |

#### 新事务的生成器 SHA 不符（SC-WSC-007）

| 字段 | 内容 |
|---|---|
| **ID** | TC-WSC-009 |
| 预置 | 无 journal，临时 Tools 固定脚本生成自摘要有效但声明脚本 SHA 不符的候选。 |
| 操作 | 新跑 `writeback-apply`。 |
| 预期 | `WRITEBACK_GENERATOR_MISMATCH`，不建立 journal。 |

### 功能 3：OutputGuard 首行逃生口

#### 首行命中（SC-OGE-001）

| 字段 | 内容 |
|---|---|
| **ID** | TC-OGE-001 |
| 预置 | 首行标记和原因合法、后续有命令，分别用 LF、CRLF，准备超限正文。 |
| 操作 | 同一命令分别传 `parseCall`、`evaluateResult`。 |
| 预期 | 两端均为 `passthrough`、`ruleId: escape-hatch`；Post 正文完整。 |

#### 第二行不命中（SC-OGE-002）

| 字段 | 内容 |
|---|---|
| **ID** | TC-OGE-002 |
| 预置 | 首行是 `cat src/big.mjs`，只有第二行有标记，正文超限。 |
| 操作 | 同一命令分别传 `parseCall`、`evaluateResult`。 |
| 预期 | 两端 `ruleId` 均非 `escape-hatch`；Post 普通裁剪。 |

## 三、测试执行矩阵

| 模块 | 自动检查 | 层级 | 状态 |
|---|---|---|---|
| 交付就绪 | TC-EVD-101–104 | CLI 集成 | 待 Phase 3 |
| 回写一致性 | TC-WSC-001–009 | 生成器与事务集成 | 待 Phase 3 |
| OutputGuard | TC-OGE-001–002 | Pre/Post 单元 | 待 Phase 3 |

## 四、回归风险矩阵

| 风险区域 | 已有回归保护 |
|---|---|
| 交付及回执 | 交付 gate、合同、回执复用 |
| 回写事务 | 结构拒绝、并发索引、提交后重放与 outbox 补发 |
| OutputGuard | `core`、conformance、adapters、metrics |

## 五、建议补充顺序

1. 先验证配置拒绝、底稿同源和应用冲突，再验证冻结续办与首行判定。

## 六、同次执行证据计划 / Same-Run Evidence Plan

```stdd-evidence-plan-v1
{
  "task": "evidence-delivery-contract",
  "tasks": ["evidence-delivery-contract", "writeback-source-consistency", "output-guard-escape-hatch"],
  "inputs": [
    {"root": "project", "path": "skills/shared/crctl/scripts/crctl.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/lib/component-readiness.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/lib/evidence-delivery.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/test/evidence-delivery-gate.test.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/lib/workspace-transactions.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/lib/durable-tx.mjs"},
    {"root": "project", "path": "skills/shared/crctl/scripts/test/writeback-tx.test.mjs"},
    {"root": "project", "path": "skills/writeback/scripts/lib.mjs"},
    {"root": "project", "path": "skills/writeback/scripts/writeback-prd-sdd.mjs"},
    {"root": "project", "path": "skills/writeback/scripts/writeback-tasks.mjs"},
    {"root": "project", "path": "skills/writeback/scripts/writeback-traceability.mjs"},
    {"root": "project", "path": "skills/writeback/scripts/test/writeback.test.mjs"},
    {"root": "project", "path": "output-guard/core.mjs"},
    {"root": "project", "path": "output-guard/policy.json"},
    {"root": "project", "path": "output-guard/test/core.test.mjs"}
  ],
  "coverage": {"applicability": "not_applicable", "reason": "Node 栈，仓库覆盖率检查只支持 pytest-cov"},
  "checks": [
    {"tc": "TC-EVD-101", "case_id": "unavailable-component-config", "requirement": "REQ-EVD-101", "scenarios": ["SC-EVD-101"], "cp": "CP-EVD-101", "kind": "command", "applicability": "required"},
    {"tc": "TC-EVD-102", "case_id": "component-config-opt-out", "requirement": "REQ-EVD-101", "scenarios": ["SC-EVD-101"], "cp": "CP-EVD-102", "kind": "command", "applicability": "required"},
    {"tc": "TC-EVD-103", "case_id": "contract-precedence", "requirement": "REQ-EVD-101", "scenarios": ["SC-EVD-102"], "cp": "CP-EVD-103", "kind": "command", "applicability": "required"},
    {"tc": "TC-EVD-104", "case_id": "original-component-findings", "requirement": "REQ-EVD-102", "scenarios": ["SC-EVD-103"], "cp": "CP-EVD-104", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSC-001", "case_id": "single-read-crlf-base", "requirement": "REQ-WSC-001", "scenarios": ["SC-WSC-001"], "cp": "CP-WSC-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSC-002", "case_id": "missing-vs-empty-base", "requirement": "REQ-WSC-001", "scenarios": ["SC-WSC-002"], "cp": "CP-WSC-002", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSC-003", "case_id": "generator-target-io-error", "requirement": "REQ-WSC-001", "scenarios": ["SC-WSC-003"], "cp": "CP-WSC-003", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSC-004", "case_id": "resumed-write-set-conflict", "requirement": "REQ-WSC-002", "scenarios": ["SC-WSC-004"], "cp": "CP-WSC-004", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSC-005", "case_id": "apply-preflight-io-error", "requirement": "REQ-WSC-001", "scenarios": ["SC-WSC-003"], "cp": "CP-WSC-005", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSC-006", "case_id": "resume-after-generator-upgrade", "requirement": "REQ-WSC-003", "scenarios": ["SC-WSC-005"], "cp": "CP-WSC-006", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSC-007", "case_id": "frozen-manifest-drift", "requirement": "REQ-WSC-003", "scenarios": ["SC-WSC-006"], "cp": "CP-WSC-007", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSC-008", "case_id": "frozen-blob-drift", "requirement": "REQ-WSC-003", "scenarios": ["SC-WSC-006"], "cp": "CP-WSC-008", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSC-009", "case_id": "new-transaction-generator-mismatch", "requirement": "REQ-WSC-003", "scenarios": ["SC-WSC-007"], "cp": "CP-WSC-009", "kind": "command", "applicability": "required"},
    {"tc": "TC-OGE-001", "case_id": "first-line-escape", "requirement": "REQ-OGE-001", "scenarios": ["SC-OGE-001"], "cp": "CP-OGE-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-OGE-002", "case_id": "second-line-marker-ignored", "requirement": "REQ-OGE-001", "scenarios": ["SC-OGE-002"], "cp": "CP-OGE-002", "kind": "command", "applicability": "required"}
  ]
}
```
