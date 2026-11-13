# 移交包：外部前置验证（供后续 change 取回并修订）

- 来源 change：`2026-11-12-fork-ci-test-evidence-trust`（项目 multica，业务仓 HEAD `903a46c5ae9fa6c3ee644fa4740d189d739dcc91`）
- 建立时间：2026-11-13
- 裁定依据（用户原文）：「选B，将需要移交到后续change的项记录在案，供以后能找回修订。」
- 台账条目：`pending-adjustments.yaml` ADJ-047；Gate 2 于 2026-11-13 以 `--reapprove` 重签
- 用途：本 change 把下列 3 个场景**移交**给后续 change。本文件保留它们的规格原文与测试案例原文，供后继 change 逐字取回；**本 change 不对这 3 项作任何通过声明**。

---

## 1. 移交清单

| TC | Scenario | Requirement | 能力 | 移交原因（外部前置未满足） |
|---|---|---|---|---|
| TC-CBE-005 | SC-CBE-005 | REQ-CBE-002 | ci-backend-environment | 需要真实 CI run：multica 提交+推送授权、管理员 PAT、仓库 secret；本 change 的提交/推送/部署未经授权 |
| TC-TOR-004 | SC-TOR-004 | REQ-TOR-001 | test-ownership-and-ci-reconciliation | 需要 WSL AIFI-ISO root 隔离环境；用户已裁定保持 UNCOVERED，不启动 WSL |
| TC-CCF-003 | SC-CCF-003 | REQ-CCF-001 | ci-credential-and-frontend-typecheck | 需要管理员按最小权限更新 `AIFIRST_TOOLS_READ_TOKEN` 后重跑 transitions-contract-check；本 change 不得读取/创建/轮换凭据 |

**共同点**：三者的验收对象都在本机之外（真实 CI、WSL 隔离环境、管理员凭据动作），任何本地命令都不能替代。此前它们被声明为 `manual` + `applicability: required`，而 `stdd agent confirm` 是计划级、全有或全无、且结果固定为 `manual-pass`，因此在本 change 内既无法执行也无法诚实确认。

## 2. 本 change 的边界声明

1. 本 change 的证据计划（`test-plan.md` 六节）已移除这 3 条 check，覆盖分母从 22 降为 **19**（18 条 command + 1 条 manual TC-TOR-005）。
2. 这 3 个 TC 的**原定义仍逐字保留在 `test-plan.md` 内**（HTML 注释块，机器不解析），并在 §七 以可见表格列出移交去向。
3. `canonical/specs/code/` 中这 3 个 Scenario **保持原样、未删除**：它们是本能力的行为规格，属于后继 change 的验收对象；本 change 只是不在此签收它们。
4. **不得**把本 change 的 18 条命令 CP 通过、或本地一次性库测试，解读为这 3 项已被验证。
5. 本 change 的验收报告 `validation/acceptance-report.md` 记录它们为「未覆盖 / 未闭合」，不报通过。

## 3. 后继 change 的入口条件（硬性）

后继 change 若要取回这 3 项，必须全部满足：

1. 在自己的 `test-plan.md` 中重新加入对应 TC 定义（`| **ID** | TC-... |` 行）与证据计划 check（`manual` 或能真实执行的 `command`）。
2. 先取得各自需要的授权：multica 提交+推送、管理员 PAT 与 secret 更新、WSL 隔离环境启动同意。授权与执行分开记录。
3. 真实执行并保存原始输出：CI run id 与各 job 结论、WSL 隔离入口的通过数/skip 数、transitions-contract-check 的 job 结论。
4. 若某项仍不能执行，如实标 NOT EXECUTED / UNCOVERED 并写边界原因；**不得**改用同 uid 对照、本地模拟或「报告已生成」代替。
5. 后继 change 的证据必须由它自己的 run 产生，**不得**引用本 change 的 run id 顶替。

## 4. 已完成的部分（后继 change 可直接复用，不必重做）

| 项 | 现状 | 位置 |
|---|---|---|
| tools pin 可达性 | `AI-First-tools` 已推送 `e52b8081f159d581bf62f82447c76f818fc52426`，HEAD = origin/main，pin 可达性检查在 checkout 之前 | `validation/gate3-followup/tools-push-verified.txt`、`pin-reachability-order.txt` |
| ci.yml 接线 | provision / tools / evidence / script-checks 步骤已接入；`scripts/ci-scope.mjs` 49/49 | `validation/s13-ci-wiring/` |
| 验收报告 | 已产出，逐项列本地执行与未覆盖项 | `validation/acceptance-report.md` |
| 未闭合项清单 | 3 项移交 + views vitest 既有 flake（ADJ-020） | `test-report.md` §1、§9 |

**尚未满足、后继 change 必须补的**：
- 真实 CI run：**0 次**（本 change 从未推送 multica）。
- WSL AIFI-ISO：**从未启动**，`TestChannelIsolation` 与两个状态敏感探针的隔离执行 **UNCOVERED**。
- `AIFIRST_TOOLS_READ_TOKEN`：**未更新**，transitions-contract-check 的真实 job 结论未知（本 change 只有注入 fetch 的单元测试 TC-CCF-001）。

## 5. 复现命令（后继 change 在其授权范围内执行）

```bash
# SC-CBE-005：真实 CI（推送后）
gh run list --branch main --limit 5
gh run view <run-id> --log
# 期望：backend-tests 内 cmd/server / governance / crosslang_test / handler 各有通过测试，
#       ci-evidence 步骤对名单外 skip 判红，报告记录 run id / commit / 各 job 结论。

# SC-TOR-004：WSL 隔离入口（需用户同意后）
wsl -d AIFI-ISO -u root -- <repo>/scripts/aifi45-disposable/run-selection.mjs <selection>
# 期望：TestChannelIsolation 与两个状态敏感探针通过数 >= 1、skip 0，命令/退出码/通过数入报告。

# SC-CCF-003：管理员更新 PAT 后
gh workflow run <transitions-contract-check workflow>   # 或随推送触发的同名 job
gh run view <run-id> --job transitions-contract-check
# 期望：job 通过；未更新时如实记未闭合。不得读取或打印 token 值。
```

## 6. 原文保留：规格场景（取自 `canonical/specs/code/`，逐字）

### 6.1 `ci-backend-environment.yaml` → SC-CBE-005

```yaml
  - id: SC-CBE-005
    confidence: low
    evidence: canonical/proposals/2026-11-12-fork-ci-test-evidence-trust.yaml#capabilities.modified
    given: CI 的 backend-tests 在修复后的 ci.yml 下运行（需推送授权与 tools pin 可用，见 design U1），
    when: 查看该 run 的 Test 步骤与 ci-evidence 步骤。
    then: SHALL cmd/server、governance、crosslang_test、handler 各自有通过的测试且无名单外 skip；若走 U1 路径 β（tools 未推送），SHALL 如实记录 tools 相关测试未验证并使 pin 完整性检查失败，不得 skip 或报绿。
    and:
    - 验收报告 SHALL 记录 run id、commit、各 job 结论。
```

### 6.2 `test-ownership-and-ci-reconciliation.yaml` → SC-TOR-004

```yaml
  - id: SC-TOR-004
    confidence: medium
    evidence: canonical/proposals/2026-11-12-fork-ci-test-evidence-trust.yaml#capabilities.new
    given: D1 的独立入口：TestChannelIsolation 经 WSL AIFI-ISO（root 加 AIFI45_ISOLATION_PROFILE），两个状态敏感探针经 run-selection 的 down/reapply 初始状态，
    when: 本地在授权后真实执行并保存输出。
    then: SHALL 每项通过数不少于 1、skip 为 0，并把命令、退出码、通过数记入验收报告；任一项不能执行（如 WSL profile 失效）时 SHALL 如实列为未覆盖，不得以同 uid 对照代替。
    and:
    - 执行前 SHALL 先向用户说明并征得同意（WSL 启动、podman 实例）。
```

### 6.3 `ci-credential-and-frontend-typecheck.yaml` → SC-CCF-003

```yaml
  - id: SC-CCF-003
    confidence: low
    evidence: canonical/proposals/2026-11-12-fork-ci-test-evidence-trust.yaml#capabilities.modified
    given: 管理员已按最小权限更新 AIFIRST_TOOLS_READ_TOKEN，
    when: 重跑 transitions-contract-check。
    then: SHALL 该 job 通过；管理员未完成更新时 SHALL 如实列为未闭合。
    and:
    - 本 change SHALL NOT 读取、创建或轮换凭据。
```

## 7. 原文保留：测试案例（取自本 change `test-plan.md`，逐字）

### 7.1 TC-CBE-005

```markdown
#### 案例 TC-CBE-005 — SC-CBE-005

| 字段 | 内容 |
|------|------|
| **ID** | TC-CBE-005 |
| **对应 Spec** | ci-backend-environment → Requirement REQ-CBE-002 → Scenario SC-CBE-005 |
| **优先级** | P1 |
| **置信度** | low |
| **预置条件** | CI 的 backend-tests 在修复后的 ci.yml 下运行（需推送授权与 tools pin 可用，见 design U1）， |
| **输入** | 查看该 run 的 Test 步骤与 ci-evidence 步骤。 |
| **预期结果** | SHALL cmd/server、governance、crosslang_test、handler 各自有通过的测试且无名单外 skip；若走 U1 路径 β（tools 未推送），SHALL 如实记录 tools 相关测试未验证并使 pin 完整性检查失败，不得 skip 或报绿。；验收报告 SHALL 记录 run id、commit、各 job 结论。 |
| **验证方式** | 人工（manual）：`依赖推送授权与 tools pin 可用；真实 CI run 的结果只能在验收报告中人工确认` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |
```

### 7.2 TC-TOR-004

```markdown
#### 案例 TC-TOR-004 — SC-TOR-004

| 字段 | 内容 |
|------|------|
| **ID** | TC-TOR-004 |
| **对应 Spec** | test-ownership-and-ci-reconciliation → Requirement REQ-TOR-001 → Scenario SC-TOR-004 |
| **优先级** | P1 |
| **置信度** | medium |
| **预置条件** | D1 的独立入口：TestChannelIsolation 经 WSL AIFI-ISO（root 加 AIFI45_ISOLATION_PROFILE），两个状态敏感探针经 run-selection 的 down/reapply 初始状态， |
| **输入** | 本地在授权后真实执行并保存输出。 |
| **预期结果** | SHALL 每项通过数不少于 1、skip 为 0，并把命令、退出码、通过数记入验收报告；任一项不能执行（如 WSL profile 失效）时 SHALL 如实列为未覆盖，不得以同 uid 对照代替。；执行前 SHALL 先向用户说明并征得同意（WSL 启动、podman 实例）。 |
| **验证方式** | 人工（manual）：`需要 WSL root 与一次性 podman 实例，须单独授权；结果由人工在验收报告确认` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |
```

### 7.3 TC-CCF-003

```markdown
#### 案例 TC-CCF-003 — SC-CCF-003

| 字段 | 内容 |
|------|------|
| **ID** | TC-CCF-003 |
| **对应 Spec** | ci-credential-and-frontend-typecheck → Requirement REQ-CCF-001 → Scenario SC-CCF-003 |
| **优先级** | P2 |
| **置信度** | low |
| **预置条件** | 管理员已按最小权限更新 AIFIRST_TOOLS_READ_TOKEN， |
| **输入** | 重跑 transitions-contract-check。 |
| **预期结果** | SHALL 该 job 通过；管理员未完成更新时 SHALL 如实列为未闭合。；本 change SHALL NOT 读取、创建或轮换凭据。 |
| **验证方式** | 人工（manual）：`依赖管理员动作与 CI 推送，无法由本地命令代替` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |
```

## 8. 取回校验（后继 change 开单时逐条核对）

- [ ] 3 个 TC 已加入后继 change 的 `test-plan.md`（`| **ID** |` 行可见、机器可解析）。
- [ ] 3 条 check 已加入后继 change 的证据计划 fence，且 `applicability` 与实际授权一致。
- [ ] 每项都有真实原始输出（run id / 命令 / 退出码 / 通过数 / skip 数）。
- [ ] 未能执行的项已标 NOT EXECUTED 并写边界原因，未报通过。
- [ ] 未引用本 change 的 run id 作为后继 change 的证据。
