# 长程模式 — 一次性交互授权

> 用户 2026-10-27 原文：「继续，按照长程模式执行」（前一轮已授权：nonce DB 每轮独占库；**P0 隔离环境尚未获批**——两真实受限身份与裁决 profile 仍 UNVERIFIED，见 tasks P0 段）。
> 依据：项目 `config.d/long_range.yaml`（`pre_auth` 全 allow、`gate3: mandatory`、`degradation: 3 次 / 0.95`）。
> 生效范围：本 change 的 Phase 3 (BUILD)；**Gate 3 仍为强制人工确认**，长程模式不跳过任何流程步骤。

## A. 流程决策授权

### A1. 设计偏离处理

- [x] 小偏离（不改接口和行为语义）→ 自动记录到 `design-adjustments.md` 并继续。
- [x] 大偏离（改接口或行为语义）→ 自动记录并继续，在 `test-report.md` 汇总；**涉及已批准必达 leaf 或范围的，仍按规格修订处理并标注。**

### A2. 技术阻塞处理

- [x] 同意：尝试绕过方案，记录到 `design-adjustments.md`。
- [ ] 跳过当前切片（未选用；阻塞一律先 workaround）。
- [ ] 降级（仅在降级条件触发时）。

### A3. 迭代上限策略

- 最大迭代轮数：**10**（普通模式 5）。
- 达到上限 → 在 `test-report.md` 汇总剩余问题后继续进入 Gate 3，**不静默吞掉**。

## B. 操作类授权

- [x] B1 目录操作（change 目录、`validation/` 证据子目录）
- [x] B2 文件写入（源码、测试、`tasks.md`、`design-adjustments.md`、`validation/`）
- [x] B3 命令执行（`go test`/`go vet`、`node --test`、`stdd` 只读与状态命令、`scripts/aifi45-db/run.mjs`）
- [x] B4 脚本执行（本 change 的验证/证据脚本）
- [x] B5 网络访问（仅必要时；不新增依赖、不安装包）
- [x] B6 文件读取（模板、配置、既有源码、sibling 仓源码）
- [x] B7 Git 只读（`status`/`log`/`show`/`diff`）

**未授权**：`git commit`/`push` 到源码仓（multica/tools 源码改动保持未提交，用户 2026-10-27 选 (a)）；生产部署、真实 CR、破坏性数据操作、权限扩大、`pkg/db/generated/*.sql.go` 提交。
工作区记录仓的提交不属于源码仓，按既有节奏继续。

## C. Gate 确认

- [x] C1 Gate 3 强制：BUILD 完成后等待用户确认 `test-report.md` + `design-adjustments.md`，长程模式不自动跳过。

## 降级触发条件（任一触发即暂停等待用户）

1. 同一问题连续自动修复 3 次仍失败；2. 测试通过率 < 0.95；3. 安全问题（认证/授权/注入）；
4. TC 覆盖 0；5. 连续 3 个切片无新增测试；6. 出现预授权范围外的未预期情况（含需要新环境/新授权）。
