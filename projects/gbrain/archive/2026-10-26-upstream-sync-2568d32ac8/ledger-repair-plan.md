# 台账修复方案（Gate 1 硬前置，§0 BLOCK → PASS）

> 依据 CUSTOM.md《合并守则》第一条：「任何未入台账的改动会在合并时静默丢失，视为欠债——先补台账，再合并」。
> 本文件只列**待你批准的 CUSTOM.md 编辑**；未经批准不改台账、不进 Gate 1。

## 1. 证据来源

- fork 增量清单：`fork-changed-files.txt`（`git diff --name-only 2895edb3c6..HEAD` = 509 文件）
- 与上游窗口交集：`conflict-surface.txt`（47 文件）
- 交叉核对法：对 fork-only 代码文件（33 个 `src/ test/ scripts/ docs/operations/ tsconfig.json`）逐个 `grep -F <basename> CUSTOM.md`

## 2. A 类：完全未登记（必须补登，否则合并时静默丢失）

| # | 文件 | 实际改动 | 性质 | 建议登记位置 |
|---|------|----------|------|--------------|
| A1 | `src/core/eval-shared/json-repair.ts` | `stripFences` / `tryParse` / `repairJson` 由文件私有改为 `export`（+6/−3） | 支撑 `src/core/compile-truth.ts` 复用上游 JSON 修复，属 fork 对上游文件的可见性改动 | 《后端增量·工作流》真理沉淀行补「依赖 `eval-shared/json-repair.ts` 的三个导出符号」；改上游函数可见性=合并高危点，上游重构即失效 |
| A2 | `tsconfig.json` | 删 `baseUrl: "."`，`@/*` 映射改 `"./src/*"`（+1/−2） | 构建配置定制，不在任何台账表内 | 新增《后端增量·构建与类型配置》行（或并入《二开专属文件》说明）；注明验证命令 `bun run typecheck` |
| A3 | `test/doctor-categories.test.ts` | 类别扫描纳入 `src/commands/onboard/checks.ts`（+4），注释说明 v0.41.18.0 后 `runAllOnboardChecks` 的 check 名不再出现在 `doctor.ts` | 上游文件被我方改动的契约测试，改号/改名会红 | 《后端增量》新增行：doctor 类别守卫覆盖 onboard checks；验证命令 `bun test test/doctor-categories.test.ts` |

## 3. B 类：能力已登记、但《回归》行写的是「相关 tests」，无法逐文件核对

守则要求「`grep + 台账核对` 只能核对已入台账的改动」。以下 7 个 fork 改动测试文件当前只能靠人推断归属，建议把《回归》行改成**具体文件清单**：

| 文件 | 归属的已登记能力 | 加行数 |
|------|------------------|--------|
| `test/ai/gateway.test.ts` | Ollama 显式 embed 维度（`dimsProviderOptions` 第 5 参 `providerId`） | +17 |
| `test/ai/gateway-chat.test.ts` | DeepSeek recipe touchpoint（`deepseek-v4-pro/flash`） | +11 |
| `test/ai/build-gateway-config.test.ts` | DeepSeek Base URL + `config.deepseek_api_key` → env 注入 | +34 |
| `test/embedding-dim-check.test.ts` | Ollama 任意模型 + Matryoshka 宽度（台账第 83 行「文件现与上游一致」与实际 +51 行**矛盾**，见 §4-C1） | +51 |
| `test/init-env-detection.test.ts` | `DEEPSEEK_API_KEY` → expansion ready | +5 |
| `test/ingestion/ingest-capture.test.ts` | Inbox 工作流 ingest 分支（`inbox_status` + provenance） | +17 |
| `test/skill-brain-first.test.ts` | Windows CRLF frontmatter（台账第 67 行提到用例名，缺文件路径） | +17 |

## 4. C 类：台账内容与 git 事实不符（STALE-STATUS，须事实性修正）

| # | 台账位置 | 现文 | 事实 | 处置 |
|---|----------|------|------|------|
| C1 | 《已上游化》`embedding-dim-check.ts` 行 | 「我方原增量只是注释；文件现与上游一致」 | `test/embedding-dim-check.test.ts` 有 +51 行 fork 用例；且 `src/core/embedding-dim-check.ts` 本次窗口未变（不冲突） | 改为「源文件与上游一致；测试侧保留 Ollama 宽度用例（文件：`test/embedding-dim-check.test.ts`）」 |
| C2 | 《后端增量·工作流》迁移行 | 「占号史 v126→133→142→160→**239**（上游本次占了 160）」 | 括号指 0.51 轮；239 轮实际上游占 160..238 | 改为「（上游 v0.60.176 占至 238）」，并把水位更新并入下一次 Gate 3 阶段记录，不改历史事实 |
| C3 | 《合并守则·迁移号顺延》 | 「`inbox_workflow_frontmatter` 当前 **239**」 | 上游 master 现已占 239..274，239 号被上游 `v239-extract-rollup-halt-reasons.ts` 使用 | 本轮顺延目标 **275**（上游最新 274 + 1）。守则行是「当前值」陈述，Gate 3 后随阶段记录刷新 |
| C4 | 《已知测试失败基线》 | 无 Bun 版本现场值 | 本机 `bun --version` = **1.3.14** < `MINIMUM_BUN_VERSION` 1.4.0 | 属环境前置未满足，不是基线行；在 Gate 1 §2 前置检查里作为**未通过项**列出，由你决定是否 `bun upgrade` |

## 5. 修复提交纪律

- 只改 `CUSTOM.md`：A 类补登 + B 类《回归》行改文件清单 + C 类事实修正。**不动任何代码**。
- 独立提交在同步分支上（`sync/upstream-2026-10-26-2568d32ac8`），`master` 不动。
- 提交后重跑 §0，四维应全部 FRESH/EXPLAINABLE → 判 PASS，才进 Gate 1。
- 历史《阶段记录》行不回填；本轮合并记录在 Gate 3 后追加（守则：补登与状态刷新在 Gate 1 前，历史基线行/合并记录在 Gate 3 后）。

**执行结果**：提交 `1b8e921983`（2026-10-26，分支 `sync/upstream-2026-10-26-2568d32ac8`），`CUSTOM.md` +16/−8，仅此一个文件。复跑 §0 四维全部 FRESH → PASS。

## 6. 附带项（需你单独裁定，不属于台账欠债）

| 项 | 现状 | 选项 |
|----|------|------|
| `.stdd/`（本次新增，未跟踪） | 含 `binding.yaml`，记录仓在 `AI First Platform/projects/gbrain/` | A：加入 `.gitignore`（`.gitignore` 本身在 47 冲突面内，会顺带进裁决矩阵）／B：保持未跟踪并在《二开专属文件》登记「勿提交」 |
| `.gbrain/`、`.qoder/better-harness/` | 已登记为勿提交，`git status` 仍显示未跟踪 | 不动，Gate 1 §2 记为已知非阻塞项 |
