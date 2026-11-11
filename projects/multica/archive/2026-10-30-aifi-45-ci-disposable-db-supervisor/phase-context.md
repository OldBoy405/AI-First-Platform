# Phase Context — 2026-10-30-aifi-45-ci-disposable-db-supervisor

> 阶段交接摘要。冲突时以各 phase 的正式产出物为准。

---

## Phase 1: UNDERSTAND (completed 2026-11-11T00:11)

### 关键决策
- **按行业方案收窄**：容器是最小处置单位，入口自建、自释放，靠 `--rm --timeout` 兜底强杀；不做 journal、lost-ack、进程树证明、清扫器、库级回滚（详见 proposal.md non_goals）。
- **不改 CI，不负责让 CI 变绿**：fork CI 后端任务多因失败，已登记 `docs/analysis/fork-ci-failure-register-20261111.md`，待负责人取舍后另立 change。
- 模式 standard（预估 6 分）。

### 用户关注点
- 先核对需求再动手，已有的库级隔离证据不重做；不过度设计，不逐异常打补丁。
- 委派遵循 STDD 模型分层，不手选模型。

### 被否决的方向
- 保留 `--admin-url` 并加校验：仍需校验"该端口是不是我们的容器"，调用方仍要手工建删容器。
- 接线 `scripts/aifi45-db/` 的 instance-*/supervisor-* 草稿：含 journal 与恢复协议，属被收窄范围。
- 把 fork CI 的 nonce 不兼容并入本 change：多因，无法变绿，且验证需推送。

### 产出物清单
- proposal.md — Gate 1 已确认（2026-11-11 00:11，dialog）。

### 完整上下文文件清单
- proposal.md：背景、能力、约束、成功标准。
- docs/analysis/fork-ci-failure-register-20261111.md：CI 失败登记。

---

## Phase 2: SPEC (completed 2026-11-11T00:19)

### 关键技术决策
- 资源信封固定在 `buildRunArgs`：`pgvector/pgvector:pg17` + `--pull=never`、`127.0.0.1::5432`、tmpfs、名称与标签含 nonce、`--rm`、`--timeout`（默认与上限 3600）；密码经子进程环境传入。排除：host 网络、bind mount、argv 带密码。
- 释放只按完整 ID，名称加精确标签键值匹配才 `rm -f -v`，之后按 ID 与标签读回为零。排除：按名称删、不回读、批量清扫。
- governance 身份检查在 governance 包内复制一份（`cmd/server` 是 `package main` 无法导入，`internal/testutil` 是上游包）；拒绝测试用 fixture `updated_at` 不变证明未写入。
- guard 与 `test-go.test.sh` 拒绝含 `:` 的 TMPDIR；`test-go.test.sh` 的拒绝只在修复后验证。

### 经验触发记录
- 经验库 2 条，命中 0 条（均涉及 verdict 链/锁顺序）。

### 产出物清单
- design.md、canonical/specs/{code,agent}/{disposable-test-instance,test-wrapper-path-guard}.yaml、specs/*/spec.md（Gate 2 生成）、test-plan.md（10 个 TC）。Gate 2 已确认（2026-11-11 00:19，dialog）。

### 长程模式
- 已预授权（full_auto）。例外：信封或保证类偏离（`--rm --timeout` 在 podman machine 上不可行、扩大信封、触碰非本次创建的容器/卷/库）暂停报告；`git add/commit/push`、打 tag、改 CI、改 `provision.mjs`/`selection.mjs`、网络访问不在预授权内。Gate 3 强制等用户确认。

### 完整上下文文件清单
- design.md：决策、风险、落点。
- test-plan.md：TC 与回归矩阵。

---

## Phase 3: BUILD (in progress, 2026-11-11)

### 切片记录
- S1 TMPDIR 拒绝：`go-test-with-agent-cli-guard.sh`、`test-go.test.sh`；TC-TWG-001/002/003；TC-TWG-001 RED 实测（修复前 status 0、假命令被执行）。
- S2 `instance.mjs` + `instance.test.mjs`：TC-DTI-001/003/004，10 个单元测试；变异检查（标签子串匹配）被 TC-DTI-004 抓到。
- S3 真实 TTL：`instance.real.mjs` TC-DTI-005，17 秒内消失，容器与卷集合不变。前置探测（00:20）：`--rm --timeout=12` 约 12 秒移除，无遗留卷，端口 127.0.0.1，ID 64 位。
- S4 入口接线：`run-selection.mjs`、`run-selection.test.mjs`（TC-DTI-002 ×2，RED 先行）、真实 TC-DTI-006（一通过一失败，读回为零）。
- S5 governance：`TestMainRejectsWrongDisposableNonceBeforeSetup` RED（子进程 15 秒不退出）→ TestMain 加 `verifyDisposableTestDatabase` 后 GREEN；完整入口 13 选择 228 PASS（须 AIFI45_TOOLS_ROOT）。
- CUSTOM.md 行 #314；`pending-adjustments.yaml` ADJ-001（CP-DTI-007 前置）。

### Phase 3 补记：证据链接线与 Gate 2 重签（2026-11-11 10:16）
- 真实测试改名 `instance.real.mjs`（无 `.test.`，无环境开关），清理改为只释放自己拿到的 ID，不扫描。
- Gate 2 重签批：test-plan 第六节 `stdd-evidence-plan-v1`（10 TC→10 CP，coverage `not_applicable`）；两份 spec 改 TAP reporter、Node CP 加 `# pass N`；CP-DTI-007 收窄为 `selections.identity.json` 的两个单测试选择，13 选择完整入口改作 C2 回归；ADJ-002/003/004 已处理。Gate 2 于 10:16:17 用户原话重新确认。
- 同次证据 run `28a37e50-a05d-4634-8830-e8e8637f089e`：`agent verify` 10/10，`check-failures --run` 9 通过 / 1 警告 / 0 错误，TC 10/10。回归：13 选择 229 PASS。
- 评审：balanced 三轮实施 + strong 两轮审核（actual 均 unknown）。详见 test-report.md 第六节。
- 待办：Gate 3 由用户确认；归档前须说明 `tc-evidence.json` 对象路径随目录移动，归档后只能历史留存；提交、推送、结构索引写入各需另行授权。
