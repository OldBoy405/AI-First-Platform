# node-2.md — code-implementation / write-dev-tasks 节点结构化结果

```yaml
cr-id: CR-2026-076
stage: code-implementation
node: node-2
skill: write-dev-tasks
node-id: 00000000-0000-0000-0015-000000000002
status: complete
round: "review-dev-plan BLOCK 回修轮（reviewLoop replayNodes[1]；plan→TASK delta 重算 + 索引刷新 + 状态推进）"
status-transition: { from: tech-design-reviewed, to: task-breakdown, trigger: write-dev-tasks, expect: tech-design-reviewed, advanced: true, commit: "c712b456", outbox: "20261010T085457974Z-CR-2026-076-status-c712b456.json" }
plan-ref: change-requests/CR-2026-076/plan.md
plan-sha256-lf: e04f17e74e739e6b54b4d8e29ab2cea7d8be5fde6dd436d7c09f7f20f26052f0
plan-commit: 27a6b403
sdd-ref: change-requests/CR-2026-076/sdd.md
target-version: 0.49
tasks-dir: change-requests/CR-2026-076/tasks
task-count: 17
task-count-hint: 17
task-id-set: ["CR-2026-076-TASK-01", "CR-2026-076-TASK-02", "CR-2026-076-TASK-03", "CR-2026-076-TASK-04", "CR-2026-076-TASK-05", "CR-2026-076-TASK-06", "CR-2026-076-TASK-07", "CR-2026-076-TASK-08", "CR-2026-076-TASK-09", "CR-2026-076-TASK-10", "CR-2026-076-TASK-11", "CR-2026-076-TASK-12", "CR-2026-076-TASK-13", "CR-2026-076-TASK-14", "CR-2026-076-TASK-15", "CR-2026-076-TASK-16", "CR-2026-076-TASK-17"]
estimate-total-hours: 228
estimate-total-human-days: 28.5
estimate-cross-check: "plan §3 逐 TASK 人天当量合计 = 28.5（2.0+1.5+1.5+2.0+1.5+1.5+2.5+1.5+2.5+1.5+2.0+1.0+1.5+1.5+1.5+1.0+2.0）× 8h = 228h，与 crctl task init 的 totalEstimateHours 一致；本轮已按 review-dev-plan suggestions-1 把 plan §1 M3 行改为 5.5、合计行改为 28.5 人天（228h），两处口径已闭合，无 WARN 残留"
dependency-graph: "17 节点 / 25 条 depends-on 边 / 无环；本轮未改动任何 depends-on（重算面仅 TASK-11／TASK-15／TASK-17 的产物与完成标志）"
group-mapping-preflight:
  pre-init: "plan §6.1 交付覆盖表引用 TASK 集 = 17 个 id，与文件集 CR-2026-076-TASK-01..17 双向一致（无未引用、无越界）；plan §3 分工表 17 行逐一对应；frontmatter id 连续无重复"
  init: { op: task-init, taskCount: 17, totalEstimateHours: 228, changed: false }
  post-init: "磁盘 TASK 文件集复核 = 17 个 TASK-NN.md + _index.yml；_index.yml 条目 id 与磁盘 id 集双向一致（17 条，首 TASK-01、末 TASK-17，全 status=pending）；无并发增删"
index-file: { path: change-requests/CR-2026-076/tasks/_index.yml, sha256-lf: 9214ec3aef364829dce3048febd9ff2b0499dd7df25493e498c7bbb344acd5cc, bytes: 3432, lines: 88, changed-this-round: false }
cards-recomputed:
  - { id: CR-2026-076-TASK-11, file: change-requests/CR-2026-076/tasks/TASK-11.md, sha256-lf: f577bc639f3f9a7ffcde2cafcfa869da23537d36f4c84cfca05d54c0822dcb46, bytes: 7241, lines: 64, delta: "登记面 owner：涉及文件（gate-registry.json）+ 实现要点 5（硬失败面不放宽 / manifest.cases 收口 / 新文件登记责任归产生卡）+ 完成标志（登记面自洽）+ 接口契约产出（登记面契约供 TASK-15／TASK-17 消费）" }
  - { id: CR-2026-076-TASK-15, file: change-requests/CR-2026-076/tasks/TASK-15.md, sha256-lf: c047f28d44b70cafaf5ffb292d4ad14445422f3732655cf886528221637645f3, bytes: 7427, lines: 69, delta: "涉及文件新增 gate-registry.json 同批登记条（manifest.files + 本文件 manifest.cases 基线）+ 实现要点 7（登记同批与漂移判据）+ 完成标志（同批落盘）+ 接口契约产出（登记面产出）" }
  - { id: CR-2026-076-TASK-17, file: change-requests/CR-2026-076/tasks/TASK-17.md, sha256-lf: ea0c053461a32a53258f3b400a8a9e5636c72f06d5717588feb0a1c77c2ec6d6, bytes: 9350, lines: 71, delta: "同上形（publish-effectiveness.test.mjs 的登记 owner；登记后进入 cmd-11 的 spawn 执行面）" }
cards-untouched: "TASK-01..10、TASK-12..14、TASK-16 共 14 卡逐字保留（本轮 blocker 未涉及；plan→TASK delta 未波及）"
tasks-commit: d360271c
```

## B-1 关闭判据（复评可自验）

```yaml
B-1:
  claim: "AC-23 的「文件集合一致性」在最终状态不可成立：TASK-15／TASK-17 新建的两个测试文件落在 suite-gate 登记目录内，却无 TASK 负责登记进 gate-registry.json#manifest.files"
  closure:
    - "登记 owner 已指定：owner-source-scan.test.mjs → TASK-15；publish-effectiveness.test.mjs → TASK-17（plan §5.5「登记面所有权」第 1 条 + 两卡「涉及文件」「接口契约产出」）"
    - "「新建测试文件与 gate-registry.json 登记同批落盘」已逐字写入两卡「完成标志」与「实现要点」，并写明理由（严格集合相等：suite-gate.mjs:441／:531 比较、:442／:532 触发 SUITE_MANIFEST_FILE_DRIFT；assertion-sources.mjs:88-97 非递归全量；:536 只 spawn declared）"
    - "manifest.cases 同步已写明：新文件必须写入整数基线（缺项 = SUITE_MANIFEST_CASE_DROP 非零退出，suite-gate.mjs:452；低于基线经 FR-12 后仅 warning，:453）"
    - "登记同批生效后两个新文件即进入 cmd-11 的 spawn 列表被真实执行（原 blocker 的第二半：两文件从未被 cmd-11 执行）"
  traceability: "§6.1 FR-12 行与 §7 AC-23 行的 TASK owner 已补写关联 TASK-15／TASK-17；三张稳定表的表头与列数未变"
  self-check: "本轮以只读方式复核判据出处：suite-gate.mjs:436-443／525-536、assertion-sources.mjs:88-97、gate-registry.json manifest.files 28 条与磁盘 28 个 *.test.mjs 排序后逐项相等（现状无漂移，新漂移只由本 CR 新建文件引入）"
suggestions-1: "已在 plan §1 关闭（M3 5.0 → 5.5；合计 → 28.5 人天 / 228h）"
suggestions-2: "已在 plan §5.5 cmd-04 与「登记面所有权」第 2／3 条关闭（manifest.cases 收口 owner = TASK-11，含 crctl.test.mjs；基线为下界，净减少须同批下调）"
```

## 机器事实（本轮只读实测）

```yaml
workspace-inspect:
  operationalWorkspace: "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\knowledge-base\\requirement\\CR-2026-076"
  operationalWorkspaceError: null
  changed: false
  resources:
    - { repo: ai-first-platform-docs, branch: requirement/CR-2026-076, worktreePath: "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\knowledge-base\\requirement\\CR-2026-076", classification: healthy, dirty: false }
    - { repo: multica, branch: requirement/CR-2026-076, worktreePath: "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\multica\\requirement\\CR-2026-076", classification: healthy, dirty: false }
    - { repo: tools, branch: requirement/CR-2026-076, worktreePath: "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\tools\\requirement\\CR-2026-076", classification: healthy, dirty: false }
crctl-status-after-advance:
  status: task-breakdown
  reviewLoops: { review-requirement: "1/3", review-tech-design: "3/3", review-dev-plan: "1/3" }
  legalNext-includes: [ { to: task-breakdown, trigger: write-dev-tasks }, { to: tech-design-reviewed, trigger: "review-dev-plan:block -> write-dev-plan" }, { to: tech-design-review-pending, trigger: "review-dev-plan:upstream-design-blocker" }, { to: developing, trigger: approve-dev-start } ]
crctl-next-after-advance: "{cr: CR-2026-076, status: task-breakdown, next: write-dev-plan, humanApproval: false, why: '开发计划评审未通过（blockers=1 条），回修 plan/TASK'}"
  # 原样返回：旧 attempt 1/3 verdict=block 仍在 canonical 记录中，由 review-dev-plan 复评覆盖（本节点不代评审、不代签）
post-commit-clean: "crctl git status --porcelain 为空（文档提交 27a6b403 / d360271c 与状态提交 c712b456 之后）"
```

```yaml
boundary:
  written:
    - "change-requests/CR-2026-076/plan.md（本轮回修 delta，经 crctl git 受控入口提交 27a6b403）"
    - "change-requests/CR-2026-076/tasks/TASK-11.md、TASK-15.md、TASK-17.md（同批，提交 d360271c）"
    - "change-requests/CR-2026-076/tasks/_index.yml（由 `crctl task init CR-2026-076 --count-hint 17` 刷新，返回 changed=false，内容零改动）"
    - "crctl advance CR-2026-076 --to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed（受控：写 cr.md + commit c712b456 + status outbox 20261010T085457974Z-CR-2026-076-status-c712b456.json）"
    - "node-1.md / node-2.md（本结构化结果，经 crctl git 受控入口提交）"
  not-written:
    - "未手改 change-requests/_backlog.yml / cr.md / approval.yml / review-annotations/* / review-loop.yml / traceability.yml"
    - "未写 specs/ 或 delivery/；未写 test-evidence/（由 implement-code / write-test-report 节点产出）"
    - "未执行 checkpoint / push（阶段终点发布由 review-dev-plan 在 PASS 分支内完成）"
notes:
  - "TASK 数量三步断言（CR-2026-060 AC-08）全部通过：[1] 组映射 preflight（17/17 双向一致）→ [2] task init --count-hint 17（taskCount=17、totalEstimateHours=228，零 TASK_COUNT_MISMATCH）→ [3] init 后磁盘与索引双向复核一致。"
  - "估算交叉校验（FR-23）：本轮无 WARN——plan §1 合计与 §3 逐 TASK 之和、_index.yml 的 totalEstimateHours 三者同值（228h）。"
  - "接口签名核对：本轮新增的登记面契约（manifest.files／manifest.cases）在 TASK-11（产出）与 TASK-15／TASK-17（消费）中引用同一份完整口径，无命名差异 WARN。"
  - "行尾纪律：全部哈希按 \\r\\n → \\n 归一后计算；plan.md、TASK-11/15/17、_index.yml 实测均为 LF。"
```

```yaml
execution_context:
  cr_id: CR-2026-076
  operational_workspace: 'C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-076'
  resources:
    - { repo: ai-first-platform-docs, branch: requirement/CR-2026-076, worktreePath: 'C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-076', classification: healthy, dirty: false }
    - { repo: multica, branch: requirement/CR-2026-076, worktreePath: 'C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-076', classification: healthy, dirty: false }
    - { repo: tools, branch: requirement/CR-2026-076, worktreePath: 'C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-076', classification: healthy, dirty: false }
```
