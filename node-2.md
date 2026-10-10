# node-2.md — code-implementation / write-dev-tasks 节点结构化结果

```yaml
cr-id: CR-2026-076
stage: code-implementation
node: node-2
skill: write-dev-tasks
node-id: 00000000-0000-0000-0015-000000000002
status: complete
status-transition: { from: tech-design-reviewed, to: task-breakdown, trigger: write-dev-tasks, expect: tech-design-reviewed, advanced: true, commit: "373dfa6a", outbox: "20261010T083322093Z-CR-2026-076-status-373dfa6a.json" }
plan-ref: change-requests/CR-2026-076/plan.md
plan-sha256-lf: 5288e9994664b8cfd45afce3f08a10d98205fd3dbeca7dfd35213ac0a0c348b5
sdd-ref: change-requests/CR-2026-076/sdd.md
target-version: 0.49
tasks-dir: change-requests/CR-2026-076/tasks
task-count: 17
task-count-hint: 17
task-id-set: ["CR-2026-076-TASK-01", "CR-2026-076-TASK-02", "CR-2026-076-TASK-03", "CR-2026-076-TASK-04", "CR-2026-076-TASK-05", "CR-2026-076-TASK-06", "CR-2026-076-TASK-07", "CR-2026-076-TASK-08", "CR-2026-076-TASK-09", "CR-2026-076-TASK-10", "CR-2026-076-TASK-11", "CR-2026-076-TASK-12", "CR-2026-076-TASK-13", "CR-2026-076-TASK-14", "CR-2026-076-TASK-15", "CR-2026-076-TASK-16", "CR-2026-076-TASK-17"]
estimate-total-hours: 228
estimate-total-human-days: 28.5
estimate-cross-check: "plan §3 逐 TASK 人天当量合计 = 28.5（2.0+1.5+1.5+2.0+1.5+1.5+2.5+1.5+2.5+1.5+2.0+1.0+1.5+1.5+1.5+1.0+2.0）× 8h = 228h，与 crctl task init 的 totalEstimateHours 一致；plan §1 写「合计约 28 人天当量」为取整表述，差额 0.5 人天（4h）系 §1 取整，WARN 不静默覆盖 plan（plan §3 逐 TASK 列为唯一事实源，未修改 plan.md）"
dependency-graph: "17 节点 / 25 条 depends-on 边 / 无环（loadTaskCards 的 DEPENDS_ON_UNKNOWN 与 TASK_DEPENDENCY_CYCLE 校验均通过）；拓扑与 plan §2 依赖图逐条一致；共享改动仅 TASK-03 与 TASK-09 两处，不得声明为单点回滚（plan §4）"
group-mapping-preflight:
  pre-init: "plan §6.1 交付覆盖表引用 TASK 集 = 17 个 id，与文件集 CR-2026-076-TASK-01..17 双向一致（无未引用、无越界）；plan §3 分工表 17 行逐一对应"
  init: { op: task-init, taskCount: 17, totalEstimateHours: 228, changed: true }
  post-init: "磁盘 TASK 文件集复核 = 17 个 TASK-NN.md + _index.yml；_index.yml 条目 id 首 TASK-01、末 TASK-17、17 条 status=pending，与 init 返回值一致（无并发增删）"
index-file: { path: change-requests/CR-2026-076/tasks/_index.yml, sha256-lf: 9214ec3aef364829dce3048febd9ff2b0499dd7df25493e498c7bbb344acd5cc, bytes: 3432, lines: 88 }
task-cards:
  - { id: CR-2026-076-TASK-01, file: change-requests/CR-2026-076/tasks/TASK-01.md, sha256-lf: 3d041eff26bd3bb2, bytes: 6565, lines: 66, estimate: 16h, depends-on: [], repo: multica }
  - { id: CR-2026-076-TASK-02, file: change-requests/CR-2026-076/tasks/TASK-02.md, sha256-lf: fe27298710b800e9, bytes: 5586, lines: 70, estimate: 12h, depends-on: [CR-2026-076-TASK-01], repo: multica }
  - { id: CR-2026-076-TASK-03, file: change-requests/CR-2026-076/tasks/TASK-03.md, sha256-lf: 30b4e3c80e4656d1, bytes: 6804, lines: 64, estimate: 12h, depends-on: [CR-2026-076-TASK-01], repo: tools }
  - { id: CR-2026-076-TASK-04, file: change-requests/CR-2026-076/tasks/TASK-04.md, sha256-lf: 92228d0dae89c6cd, bytes: 6411, lines: 64, estimate: 16h, depends-on: [CR-2026-076-TASK-03], repo: tools }
  - { id: CR-2026-076-TASK-05, file: change-requests/CR-2026-076/tasks/TASK-05.md, sha256-lf: 097606467fe95102, bytes: 5490, lines: 70, estimate: 12h, depends-on: [CR-2026-076-TASK-04], repo: tools }
  - { id: CR-2026-076-TASK-06, file: change-requests/CR-2026-076/tasks/TASK-06.md, sha256-lf: de9f33f7111c4cdc, bytes: 6732, lines: 69, estimate: 12h, depends-on: [CR-2026-076-TASK-03], repo: tools }
  - { id: CR-2026-076-TASK-07, file: change-requests/CR-2026-076/tasks/TASK-07.md, sha256-lf: e4952ef482a8e53c, bytes: 7445, lines: 68, estimate: 20h, depends-on: [CR-2026-076-TASK-05, CR-2026-076-TASK-06], repo: tools }
  - { id: CR-2026-076-TASK-08, file: change-requests/CR-2026-076/tasks/TASK-08.md, sha256-lf: 92a6147d04f06417, bytes: 5027, lines: 70, estimate: 12h, depends-on: [CR-2026-076-TASK-04], repo: tools }
  - { id: CR-2026-076-TASK-09, file: change-requests/CR-2026-076/tasks/TASK-09.md, sha256-lf: bc8a0a883b8fdd0e, bytes: 7205, lines: 73, estimate: 20h, depends-on: [CR-2026-076-TASK-06], repo: tools }
  - { id: CR-2026-076-TASK-10, file: change-requests/CR-2026-076/tasks/TASK-10.md, sha256-lf: 688a871e045ff85c, bytes: 5827, lines: 72, estimate: 12h, depends-on: [CR-2026-076-TASK-09], repo: tools }
  - { id: CR-2026-076-TASK-11, file: change-requests/CR-2026-076/tasks/TASK-11.md, sha256-lf: 73c4013188654429, bytes: 5994, lines: 64, estimate: 16h, depends-on: [CR-2026-076-TASK-03], repo: tools }
  - { id: CR-2026-076-TASK-12, file: change-requests/CR-2026-076/tasks/TASK-12.md, sha256-lf: db22851b2335d005, bytes: 4084, lines: 59, estimate: 8h, depends-on: [], repo: tools }
  - { id: CR-2026-076-TASK-13, file: change-requests/CR-2026-076/tasks/TASK-13.md, sha256-lf: 5fbdec9537ef9973, bytes: 6602, lines: 72, estimate: 12h, depends-on: [], repo: tools }
  - { id: CR-2026-076-TASK-14, file: change-requests/CR-2026-076/tasks/TASK-14.md, sha256-lf: 74c7d32e670641d7, bytes: 6906, lines: 72, estimate: 12h, depends-on: [CR-2026-076-TASK-13], repo: tools }
  - { id: CR-2026-076-TASK-15, file: change-requests/CR-2026-076/tasks/TASK-15.md, sha256-lf: 7426de3544e69d4e, bytes: 5986, lines: 66, estimate: 12h, depends-on: [CR-2026-076-TASK-13, CR-2026-076-TASK-14], repo: tools }
  - { id: CR-2026-076-TASK-16, file: change-requests/CR-2026-076/tasks/TASK-16.md, sha256-lf: 0134c67d3027ac57, bytes: 4853, lines: 65, estimate: 8h, depends-on: [], repo: ai-first-platform-docs }
  - { id: CR-2026-076-TASK-17, file: change-requests/CR-2026-076/tasks/TASK-17.md, sha256-lf: f41a22ea1178e5bd, bytes: 7897, lines: 68, estimate: 16h, depends-on: [CR-2026-076-TASK-01, CR-2026-076-TASK-02, CR-2026-076-TASK-03, CR-2026-076-TASK-04, CR-2026-076-TASK-05, CR-2026-076-TASK-06, CR-2026-076-TASK-07, CR-2026-076-TASK-08, CR-2026-076-TASK-09, CR-2026-076-TASK-10, CR-2026-076-TASK-11, CR-2026-076-TASK-12, CR-2026-076-TASK-13, CR-2026-076-TASK-14, CR-2026-076-TASK-15, CR-2026-076-TASK-16], repo: "multica + tools + 人类 owner" }
evidence-inheritance: "每张卡的第 4/5 项逐条继承 plan §6.1 交付覆盖表的 cmd-NN、§5.5 的实际运行范围与声称面，未新增 plan 未列的全仓命令；唯一全仓命令 cmd-11 只在 TASK-11 出现，依据 AC-23"
process-control-tasks: none   # 全 17 张卡完成边界均落在 developing 内；无 merge／writeback／archive／code-approved 前置（CR-2026-057 FR-10）
new-files-declared-by-tasks: ["skills/shared/crctl/scripts/test/owner-source-scan.test.mjs (TASK-15)", "skills/shared/crctl/scripts/lib/owner-source-scan.mjs (TASK-15)", "skills/shared/crctl/scripts/test/publish-effectiveness.test.mjs (TASK-17)", "change-requests/CR-2026-076/test-evidence/prd-handover-check.md (TASK-16)", "change-requests/CR-2026-076/test-evidence/effective-version.md (TASK-17)", "change-requests/CR-2026-076/test-evidence/fr14-launch-receipt.md (TASK-17)", "change-requests/CR-2026-076/test-evidence/fr14-run-behavior.md (TASK-17)"]
unverified-dependencies-carried: ["上传附件 → 知识库 source 桥接（平台侧）→ TASK-14 实施期定点核实，二选一分支，不以既有能力排期", "repocache 身份加载与 GIT_CONFIG_GLOBAL 的交互（平台侧）→ TASK-02 实施期定点核实，存在则同批收口"]
next: review-dev-plan   # crctl next 原样值（状态已推进为 task-breakdown）
```

## 机器事实（本轮实测，只读 + 受控写入）

```yaml
workspace-inspect:
  operationalWorkspace: "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\knowledge-base\\requirement\\CR-2026-076"
  operationalWorkspaceError: null
  changed: false
  resources:
    - { repo: ai-first-platform-docs, branch: requirement/CR-2026-076, worktreePath: "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\knowledge-base\\requirement\\CR-2026-076", classification: healthy, dirty: false }
    - { repo: multica, branch: requirement/CR-2026-076, worktreePath: "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\multica\\requirement\\CR-2026-076", classification: healthy, dirty: false }
    - { repo: tools, branch: requirement/CR-2026-076, worktreePath: "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\tools\\requirement\\CR-2026-076", classification: healthy, dirty: false }
crctl-status-before: { status: tech-design-reviewed, legalNext: [{ to: task-breakdown, trigger: write-dev-tasks }, { to: rejected, trigger: cr-review-record:reject }, { to: withdrawn, trigger: cr-review-record:withdraw }], gateBlockers: { task-breakdown: ["文件不存在（tasks/_index.yml）", "目录缺失或无匹配文件（tasks/）"] } }
crctl-status-after: { status: task-breakdown, gateBlockers: {} }
crctl-next-after: { cr: CR-2026-076, status: task-breakdown, next: review-dev-plan, humanApproval: false, why: "缺少 dev-plan.yml 评审记录，先跑 review-dev-plan" }
writes:
  - "crctl task init CR-2026-076 --count-hint 17（受控：生成 tasks/_index.yml，CAS/审计）"
  - "crctl advance CR-2026-076 --to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed（受控：写 cr.md + commit 373dfa6a + status outbox 20261010T083322093Z-CR-2026-076-status-373dfa6a.json）"
  - "change-requests/CR-2026-076/tasks/TASK-01..17.md（本节点产物，经 crctl git 受控入口提交）"
  - "node-2.md（本结构化结果，经 crctl git 受控入口提交）"
not-written:
  - "未手改 change-requests/_backlog.yml / cr.md / approval.yml / review-annotations/* / review-loop.yml / traceability.yml"
  - "未写 specs/ 或 delivery/；未写 test-evidence/（由 implement-code / write-test-report 节点产出）"
  - "未执行 checkpoint / push 发布动作（code-implementation pipeline 无 checkpoint 节点；阶段终点发布由 review-dev-plan 在评审分支内完成）"
notes:
  - "TASK 数量三步断言（CR-2026-060 AC-08）全部通过：[1] 组映射 preflight（17/17 双向一致）→ [2] task init --count-hint 17（taskCount=17，零 TASK_COUNT_MISMATCH）→ [3] init 后磁盘复核一致。"
  - "估算交叉校验（FR-23）：228h 与 plan §3 逐 TASK 一致；与 plan §1「约 28 人天」的 4h 差额为取整表述，按 WARN 报告，未修改 plan.md。"
  - "接口签名核对：全 17 卡共享契约完整锁定（TASK-01/02 的 taskWorkspaceBinding 与 configureTaskGitEnvironment、TASK-03 的 bindTaskWorkspace 口径、TASK-04 的 cmdReviewRecord 与 ledgerTxKey 幂等键、TASK-06 的 warnings[] 形状、TASK-09 的 compareTree 返回形状、TASK-13/14 的 owner/source 值域、TASK-15 的维度名与测试文件名）；消费方引用均指向同一定义处，无命名差异 WARN。"
  - "行尾纪律：全部哈希按 \\r\\n → \\n 归一后计算；TASK 卡与 _index.yml 均为 LF。"
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
