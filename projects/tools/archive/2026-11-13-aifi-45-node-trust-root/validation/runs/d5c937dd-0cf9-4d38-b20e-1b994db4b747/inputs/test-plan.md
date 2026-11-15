# crctl 执行信任根环境变量 测试方案与详细案例

> 版本：2026-11-13-aifi-45-node-trust-root
> 创建日期：2026-11-13
> 对应 Phase 2 Spec：specs/crctl-execution-trust-root/spec.md（SC-NTR-001～008）
> 案例与执行矩阵为设计阶段记录；BUILD 实际结果以 test-report.md 为准。全部 TC 在 tools 仓本地以 node 测试运行，不需要数据库、daemon、模型或网络资源。

## 一、测试策略

### 1.1 测试金字塔

- 全部为 crctl 的集成测试：以子进程调用 crctl，用临时目录 fixture 构造工作区与信任根。没有单元层（解析函数只有一处合并规则，由 TC-NTR-003/004 经命令入口覆盖），没有 E2E 层（真实 daemon 与授权节点由 multica 成对 change 的真实运行验证）。

### 1.2 测试原则

- 一个 TC 对应一个场景，名称以 `TC-NTR-xxx` 开头，作为顶层 `test()`；一个场景有多个拒绝条件时用独立命名的 subtest，不用混合 fixture 同时覆盖多个原因（经验库）。
- 等价类断言只比较“变量通道与 flag 通道的结果相同”，不断言“自造信任根必被拒绝”；不把本地准入成功写成平台授权证明。
- 新测试为子进程显式构造 env，并先清除 `CRCTL_EXECUTION_TRUST_ROOT`，避免外部环境污染；既有测试文件不改断言。
- 逐行解析多行输出时使用 `split(/?
/)`，不依赖 LF（本机为 Windows）。
- 零匹配不算通过：CP 用 `--test-name-pattern`（放在文件参数之前）并断言 `ok 1 - TC-NTR-xxx`；node 对零匹配会输出文件级 `ok 1 - <文件名>` 且退出 0。
- 不读取、不依赖、不格式化、不提交工作树里未提交的 M008 planRecovery 改动。

### 1.3 已有测试资产

| 测试文件 | 用例数 | 类型 | 覆盖范围 |
|----------|--------|------|----------|
| skills/shared/crctl/scripts/test/trust-anchor-chain.test.mjs | TC-TAC-001..006 | 集成 | --trust-root 覆盖、信任根位于/包含安装根、自备目录构造（fixture() 234-262，假 endpoint 293-317） |
| skills/shared/crctl/scripts/test/tac-control-fixture.mjs | 夹具 | 夹具 | createTrust/installMaterial/invokeControl/snapshot/assertNoSideEffects，新测试复用 |
| skills/shared/crctl/scripts/test/execution-authorization.test.mjs | TC-AUTH-TRUST-ROOT 等 | 集成 | agent 可写副本不能压过声明的 daemon 信任根；authorization-scope/sensitive-action |
| skills/shared/crctl/scripts/test/delivery-trust-anchor-chain.test.mjs | TC-TAC-009/010 | 集成 | register/archive 控制准入 |
| skills/shared/crctl/scripts/test/repair-trust-anchor-chain.test.mjs | TC-TAC-007/008 | 集成 | repair-admit/resume |
| skills/shared/crctl/scripts/test/node-trust-root.test.mjs | 新增 | 集成 | 本 change 新测试文件：TC-NTR-001..008 |

## 二、详细测试案例

### 功能 1：变量是 --trust-root 的另一条输入通道（REQ-NTR-001）

#### 案例 1.1 — TC-NTR-001 仅设变量时 advance 与同值 flag 一致

| 字段 | 内容 |
|------|------|
| **ID** | TC-NTR-001 |
| **对应 Spec** | crctl-execution-trust-root/spec.md → SC-NTR-001（REQ-NTR-001） |
| **优先级** | P0 |
| **测试位置** | skills/shared/crctl/scripts/test/node-trust-root.test.mjs，顶层 test('TC-NTR-001 ...') |
| **预置条件** | 新合同 CR；grant/公钥在合法信任根目录（复用 tac-control-fixture 的 createTrust/installMaterial）；binding 经现有 stdio/endpoint 通道。 |
| **输入** | 子进程 env 显式清除后只设 CRCTL_EXECUTION_TRUST_ROOT，不传 --trust-root，执行 advance。 |
| **预期结果** | 完成 admission 与消费；receipt 写入所选根的 execution-consumptions；业务写入与传同值 flag 的对照一致；输出不含通道来源。 |
| **当前状态** | ❌ 测试缺（待实现）|

#### 案例 1.2 — TC-NTR-002 authorization-bind --check 的变量/flag 输出字节一致

| 字段 | 内容 |
|------|------|
| **ID** | TC-NTR-002 |
| **对应 Spec** | crctl-execution-trust-root/spec.md → SC-NTR-002（REQ-NTR-001） |
| **优先级** | P0 |
| **测试位置** | skills/shared/crctl/scripts/test/node-trust-root.test.mjs，顶层 test('TC-NTR-002 ...') |
| **预置条件** | 同一 fixture 的两个相同副本。 |
| **输入** | 分别用变量、--trust-root 执行 authorization-bind --check。 |
| **预期结果** | 退出码、stdout、stderr 原始字节逐字节一致；用 snapshot()/assertNoSideEffects 证明两次都零副作用。 |
| **当前状态** | ❌ 测试缺（待实现）|

### 功能 2：并存与非法值（REQ-NTR-002）

#### 案例 2.1 — TC-NTR-003 变量与 flag 并存的同值/异值

| 字段 | 内容 |
|------|------|
| **ID** | TC-NTR-003 |
| **对应 Spec** | crctl-execution-trust-root/spec.md → SC-NTR-003（REQ-NTR-002） |
| **优先级** | P0 |
| **测试位置** | skills/shared/crctl/scripts/test/node-trust-root.test.mjs，顶层 test('TC-NTR-003 ...') |
| **预置条件** | 八个生效命令中的代表命令；两个不同的合法信任根目录。 |
| **输入** | 同值、异值（含 /a/trust 与 /a/trust/ 这种仅尾分隔符不同）各一个独立 subtest。 |
| **预期结果** | 同值通过；异值在读取工作区前 EXECUTION_TRUST_ROOT_INVALID；拒绝后无业务写入、无 receipt。 |
| **当前状态** | ❌ 测试缺（待实现）|

#### 案例 2.2 — TC-NTR-004 非法变量值被实际选用时拒绝且不回退

| 字段 | 内容 |
|------|------|
| **ID** | TC-NTR-004 |
| **对应 Spec** | crctl-execution-trust-root/spec.md → SC-NTR-004（REQ-NTR-002） |
| **优先级** | P0 |
| **测试位置** | skills/shared/crctl/scripts/test/node-trust-root.test.mjs，顶层 test('TC-NTR-004 ...') |
| **预置条件** | 新合同 CR，且 <安装根>/.crctl 下放有可用的合法 grant（用来证明没有回退）。 |
| **输入** | 表驱动：空串、纯空白、相对路径、不存在、普通文件、位于安装根内、包含安装根、符号链接/junction 别名（平台不支持时该行记录为未执行，不静默跳过）；每行一个独立 subtest；另对 legacy CR advance 与参数不完整的 repair-resume 设非法值。 |
| **预期结果** | 被消费的分支：每行 EXECUTION_TRUST_ROOT_INVALID，与同值 flag 对照一致，且没有使用 .crctl；不消费的分支与同值 flag 一样忽略该值。 |
| **当前状态** | ❌ 测试缺（待实现）|

### 功能 3：生效范围与回归（REQ-NTR-003）

#### 案例 3.1 — TC-NTR-005 八命令之外的命令不受变量影响

| 字段 | 内容 |
|------|------|
| **ID** | TC-NTR-005 |
| **对应 Spec** | crctl-execution-trust-root/spec.md → SC-NTR-005（REQ-NTR-003） |
| **优先级** | P0 |
| **测试位置** | skills/shared/crctl/scripts/test/node-trust-root.test.mjs，顶层 test('TC-NTR-005 ...') |
| **预置条件** | kb、git、workspace（freshness）、planning-entry/competitive-report、writeback-apply、repair-assess、repair-outcome 各自现有 fixture。 |
| **输入** | 对每个命令设非法变量值，各一个独立 subtest。 |
| **预期结果** | 输出与未设置变量时一致；没有新增 BAD_ARGS、白名单错误或 git 参数。 |
| **当前状态** | ❌ 测试缺（待实现）|

#### 案例 3.2 — TC-NTR-006 其余生效命令与同值 flag 一致

| 字段 | 内容 |
|------|------|
| **ID** | TC-NTR-006 |
| **对应 Spec** | crctl-execution-trust-root/spec.md → SC-NTR-006（REQ-NTR-003） |
| **优先级** | P0 |
| **测试位置** | skills/shared/crctl/scripts/test/node-trust-root.test.mjs，顶层 test('TC-NTR-006 ...') |
| **预置条件** | authorization-scope、sensitive-action（本地 startPlatform 平台替身）、repair-admit、完整 repair-resume、register、archive 的现有 fixture。 |
| **输入** | 每个命令分别以变量和以同值 flag 执行；register/archive 另含缺 --cr-id/--project-id/grant 的失败关闭用例。 |
| **预期结果** | 稳定结果一致；首次写入进入现有 control admission；缺输入失败关闭且零事务写入；authorization-scope 不写 receipt。 |
| **当前状态** | ❌ 测试缺（待实现）|

#### 案例 3.3 — TC-NTR-009 未设置变量时现有四个 trust 测试文件全部通过

| 字段 | 内容 |
|------|------|
| **ID** | TC-NTR-009 |
| **对应 Spec** | crctl-execution-trust-root/spec.md → SC-NTR-005（REQ-NTR-003） |
| **优先级** | P0 |
| **测试位置** | 既有四个测试文件，不新增 |
| **预置条件** | 父进程环境未设置 CRCTL_EXECUTION_TRUST_ROOT。 |
| **输入** | 运行 trust-anchor-chain、execution-authorization、delivery-trust-anchor-chain、repair-trust-anchor-chain 四个测试文件。 |
| **预期结果** | # fail 0，退出码 0；既有断言不删不改。 |
| **当前状态** | ❌ 测试缺（待实现）|

### 功能 4：威胁边界（REQ-NTR-004）

#### 案例 4.1 — TC-NTR-007 自备信任根的两个通道等价

| 字段 | 内容 |
|------|------|
| **ID** | TC-NTR-007 |
| **对应 Spec** | crctl-execution-trust-root/spec.md → SC-NTR-007（REQ-NTR-004） |
| **优先级** | P0 |
| **测试位置** | skills/shared/crctl/scripts/test/node-trust-root.test.mjs，顶层 test('TC-NTR-007 ...') |
| **预置条件** | 两个全新 fixture：自造目录、自生成 ed25519 密钥、自签 grant、本地假 endpoint（沿用 trust-anchor-chain 的构造）。 |
| **输入** | 一个走变量、一个走 flag；另有缺 key、签名无效、binding 不匹配三个拒绝子用例，各走两个通道。 |
| **预期结果** | 退出码、错误码和稳定结果一致；拒绝用例两个通道都拒绝；断言只比较等价，不断言自造根必被拒绝，也不把成功当作平台授权。测试注释写明这一点。 |
| **当前状态** | ❌ 测试缺（待实现）|

#### 案例 4.2 — TC-NTR-008 无变量无 flag 且 .crctl 无授权时仍拒绝

| 字段 | 内容 |
|------|------|
| **ID** | TC-NTR-008 |
| **对应 Spec** | crctl-execution-trust-root/spec.md → SC-NTR-008（REQ-NTR-004） |
| **优先级** | P0 |
| **测试位置** | skills/shared/crctl/scripts/test/node-trust-root.test.mjs，顶层 test('TC-NTR-008 ...') |
| **预置条件** | 新合同 CR；<安装根>/.crctl 下没有 execution-grant；daemon 信任根下放有合法材料但不被引用。 |
| **输入** | 既不设变量也不传 --trust-root，执行 advance。 |
| **预期结果** | EXECUTION_CONSUMPTION_REQUIRED；无业务写入；daemon 信任根下无 receipt。 |
| **当前状态** | ❌ 测试缺（待实现）|

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试 | E2E | 状态 |
|----------|---------|----------|-----|------|
| 变量作为输入通道 | — | TC-NTR-001/002 | 由 multica 成对 change 的真实运行验证 | 🔴 |
| 并存与非法值 | — | TC-NTR-003/004 | — | 🔴 |
| 生效范围与回归 | — | TC-NTR-005/006/009 | — | 🔴 |
| 威胁边界 | — | TC-NTR-007/008 | — | 🔴 |

## 四、回归风险矩阵

| 风险区域 | 本 change 改动 | 已有回归保护 | 风险等级 |
|----------|---------------|-------------|---------|
| 有 flag 白名单的命令（kb/workspace/business/writeback-apply） | 变量按命令过滤，不向它们注入 | TC-NTR-005 | 🟡 |
| legacy CR 与既有 --trust-root 用法 | 未设置变量时零新增分支 | TC-NTR-009、TC-NTR-004 的 legacy 子用例 | 🟡 |
| register/archive 在授权节点内新增 control 要求 | 与同值 flag 一致 | TC-NTR-006 | 🔴 |
| 外部环境泄漏进测试 | 新测试显式清除变量 | TC-NTR-001..008 的 env 构造 | 🟢 |

## 五、建议补充顺序

1. **第一优先**：TC-NTR-003/004（并存与非法值，决定合并点的形状）、TC-NTR-001/002。
2. **第二优先**：TC-NTR-005/006/008/007。
3. **第三优先**：TC-NTR-009（回归，最后一次全量确认）。

## 六、同次执行证据计划 / Same-Run Evidence Plan

> 本节随 Gate 2 锁定。在册 TC 9 个，每个有且仅有一条 check，均为 `command` 并各绑定独占 CP，没有 `manual`。TC-NTR-009 绑定 SC-NTR-005 的回归部分。
> Locked at Gate 2. 9 TCs, each with exactly one command check bound to its own CP; no manual checks.

覆盖率义务：`not_applicable`（Node 脚本，覆盖率采集目前只支持 pytest-cov）。

```stdd-evidence-plan-v1
{
  "task": "crctl-execution-trust-root",
  "inputs": [
    {"root": "project", "path": "skills/shared/crctl/scripts"}
  ],
  "coverage": {
    "applicability": "not_applicable",
    "reason": "被测对象为 Node 脚本，覆盖率采集目前只支持 pytest-cov；项目配置 quality.coverage.enabled=false"
  },
  "checks": [
    {"tc": "TC-NTR-001", "case_id": "main", "requirement": "REQ-NTR-001", "scenarios": ["SC-NTR-001"], "cp": "CP-NTR-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-NTR-002", "case_id": "main", "requirement": "REQ-NTR-001", "scenarios": ["SC-NTR-002"], "cp": "CP-NTR-002", "kind": "command", "applicability": "required"},
    {"tc": "TC-NTR-003", "case_id": "main", "requirement": "REQ-NTR-002", "scenarios": ["SC-NTR-003"], "cp": "CP-NTR-003", "kind": "command", "applicability": "required"},
    {"tc": "TC-NTR-004", "case_id": "main", "requirement": "REQ-NTR-002", "scenarios": ["SC-NTR-004"], "cp": "CP-NTR-004", "kind": "command", "applicability": "required"},
    {"tc": "TC-NTR-005", "case_id": "main", "requirement": "REQ-NTR-003", "scenarios": ["SC-NTR-005"], "cp": "CP-NTR-005", "kind": "command", "applicability": "required"},
    {"tc": "TC-NTR-006", "case_id": "main", "requirement": "REQ-NTR-003", "scenarios": ["SC-NTR-006"], "cp": "CP-NTR-006", "kind": "command", "applicability": "required"},
    {"tc": "TC-NTR-007", "case_id": "main", "requirement": "REQ-NTR-004", "scenarios": ["SC-NTR-007"], "cp": "CP-NTR-007", "kind": "command", "applicability": "required"},
    {"tc": "TC-NTR-008", "case_id": "main", "requirement": "REQ-NTR-004", "scenarios": ["SC-NTR-008"], "cp": "CP-NTR-008", "kind": "command", "applicability": "required"},
    {"tc": "TC-NTR-009", "case_id": "main", "requirement": "REQ-NTR-003", "scenarios": ["SC-NTR-005"], "cp": "CP-NTR-009", "kind": "command", "applicability": "required"}
  ]
}
```

Gate 2 前预检 / Preflight before Gate 2: `stdd agent verify crctl-execution-trust-root --change 2026-11-13-aifi-45-node-trust-root --dry-run`
