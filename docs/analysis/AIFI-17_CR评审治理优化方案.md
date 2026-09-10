# AIFI-17 评审治理优化方案

采纳范围：**P0**（worktree 回收时原子失效 pi session）、**P1a**（评审结论与账本原子对齐）、**P1b**（写手标准对齐评审标准）、**P2**（注册脏检查收窄）、**P3**（需求期 PRD 边界）。
**Provider 稳定性：不做**（按决定排除）。

原则：每项都是最小改动、复用已有机制、不新增流程；对 skill 的修改一律**原位修订**（在现有段落/步骤内改，不追加编号章节）。

---

## P0 — worktree 回收时原子删除/失效对应 pi session 文件

**根因**：pi 的 session 文件是 `~/.multica/pi-sessions/<ts>.jsonl`，其路径同时充当 opaque `SessionID`（`pi.go:216-218`）。worktree 回收后，该文件仍存在（`piSessionFilePresent` 只查文件存在，`daemon.go:6270-6275`），下一轮 `gateResumeToReachableSession` 放行 resume → pi 读到自己 session 里记录的 cwd 已不存在 → 启动即退（exit 1）→ 死循环。coordinator 每次手工把 session 文件改名 `.stale-broken-cwd` 绕过，正是这件事的自动化。

**改动（Go，2 处原位）**

1. `multica/server/pkg/agent/pi.go`：在 `PiSessionDir()`（约 807-810 行）旁新增导出函数

```go
// InvalidatePiSession removes a Pi-family session file when its owning
// worktree is confirmed gone, so a later claim never resumes into a
// recycled cwd (Pi exits immediately on a missing stored workdir).
func InvalidatePiSession(sessionID string) error {
	if sessionID == "" {
		return nil
	}
	dir, err := piSessionDir()
	if err != nil {
		return err
	}
	// 只删 pi-sessions 目录下的文件，防止误删任意路径。
	if filepath.Clean(filepath.Dir(sessionID)) != filepath.Clean(dir) {
		return nil
	}
	if err := os.Remove(sessionID); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}
```

2. `multica/server/internal/daemon/daemon.go`：Finalize defer 的 `finalizeErr == nil` 分支（约 7779-7785 行），在 `DurableWorkDir` 赋值后、`return` 前原位插入：

```go
if finalizeErr == nil {
	if localAssignment != nil {
		taskResult.DurableWorkDir = localAssignment.AbsPath
	}
	// worktree 已确认移除 → 其 pi session 不可恢复。删掉 session 文件，
	// 下次 claim 走 fresh session，避免 pi 因 stored cwd 缺失而 exit 1 的 resume 死循环。
	if err := agent.InvalidatePiSession(taskResult.SessionID); err != nil {
		taskLog.Warn("invalidate pi session after worktree finalize",
			"session_id", taskResult.SessionID, "error", err)
	}
	return
}
```

说明：`taskResult.SessionID` 是 named return 字段（`types.go:303`），Finalize defer 在 runTask 返回时执行，此时已被 provider 启动路径写入，可安全读取；best-effort，失败只 log 不改变任务结果。

**验收**
- 单测：`pi_test.go` 覆盖 `InvalidatePiSession`（空/非 pi 路径不删、pi 路径删除、已不存在不报错）。
- daemon 测：worktree finalize 成功后，对应 session 文件不存在。
- 回归：worktree 回收 → 下一轮委派以 fresh session 启动，不再出现 `Stored session working directory does not exist` / exit 1 循环；已有 `.stale-broken-cwd` 残留文件不受影响（继续手工清理一次）。

**影响面**：只影响 pi-family provider 的 worktree 任务；非 worktree 任务 `taskResult.SessionID` 对应文件不在 pi-sessions 目录，`InvalidatePiSession` 直接 no-op。
**回滚**：还原 `pi.go` / `daemon.go` 两处即可。

**可选加固（不在本次范围）**：在 `piSessionFilePresent` 同时校验 session 内记录的 cwd 是否仍存在（需解析 pi session JSONL，耦合更深）。删除即失效已覆盖主路径，暂不做。

---

## P1a — 评审结论与账本原子对齐（review-requirement）

**根因**：verdict 的自然语言评论由模型在 `review-record` 之后自由生成，流中断/模型矛盾时「评论发了但没落盘」或「评论与落盘矛盾」。账本（`review-annotations/`）才是事实源，防漂移现在压在 coordinator 事后 crctl 兜底上。

**改动（`tools/skills/requirement/review-requirement/SKILL.md`，原位修订 2 处，不新增步骤）**

① `用途` 段（第 14-16 行）原位改：在「…记录为 `review-annotations` 评审记录（经 `crctl review-record` 落盘），并更新 `traceability.yml`。」后补一句事实源声明。

原文：
```
将评审结论记录为 `review-annotations` 评审记录（经 `crctl review-record` 落盘），并更新 `traceability.yml`。
```
改为：
```
将评审结论记录为 `review-annotations` 评审记录（经 `crctl review-record` 落盘），并更新 `traceability.yml`。评审结论以 `crctl review-record` 落盘为唯一事实源，自然语言评论不是评审证据。
```

② Step 3 第 3 点（第 118 行）原位扩一句，落在「crctl 独占写」这条既有规则上：

原文：
```
3. **模型不得直接 Write `review-annotations/requirement.yml` 或手写 review-loop**（guard deny + crctl 独占写）。
```
改为：
```
3. **模型不得直接 Write `review-annotations/requirement.yml` 或手写 review-loop**（guard deny + crctl 独占写）。verdict/blockers 只能取落盘结果；落盘成功后才生成评论，且评论必须与落盘一致；未落盘即结束本轮视为失败（不视为「评审完成」）。
```

（不新增 Step 5.5；「落盘是唯一事实源、评论不先行/不矛盾」就地并入既有的「canonical 写入交 crctl」语义。）

**验收**：复现「只发评论不落盘」/「评论 verdict 与落盘矛盾」两类场景，reviewer 的完成条件判定为失败；下一次 run 以 fresh session 重跑并落盘，评论与 canonical 一致。

**影响面**：仅 review-requirement 一个 skill 的两处文案；不动 crctl、不动 pipeline。
**回滚**：还原两处原文。

---

## P1b — 写手标准对齐评审标准（write-requirement-prd）

**根因**：写手 bar 是「FR/AC 覆盖 + 契约形状」，评审 bar 是「同一输入唯一输出」。AIFI-17 第 1 轮 4 个 blocker 全是「契约不够确定性」：幂等指纹无规则、权限判定无固定顺序、错误闭包不完整、副作用/事务边界未拆分。把 bar 前移到写手自检，v0.1 一次过。

**改动（`tools/skills/requirement/write-requirement-prd/SKILL.md`，原位修订 2 处，不新增章节）**

① Step 3「功能需求」章节行（第 77 行）原位扩：

原文：
```
3. **功能需求** — FR-* 列表（必须可量化 / 可测试）
```
改为：
```
3. **功能需求** — FR-* 列表（必须可量化 / 可测试；定义用户可调用契约时，幂等规则、权限判定顺序、错误闭包、副作用与事务边界必须确定性——已有代码库先例引用并说明差异即可，实现算法归 SDD，见 P3）
```

② Step 4「落盘」的校验句（第 87 行）原位改，把契约确定性四查并入既有落盘校验（不新增「自检段」）：

原文：
```
落盘后重新读取 `prd.md`，按 Step 3 的明确合同校验 frontmatter 必填字段、七个章节和未替换占位符；任一项缺失立即停止，不进入后续评审。提交与发布由外层 checkpoint / `crctl` 流程负责，Skill 不输出手工 commit 指令。
```
改为：
```
落盘后重新读取 `prd.md`，按 Step 3 的明确合同校验 frontmatter 必填字段、七个章节、未替换占位符，以及（定义了用户可调用契约时）下列确定性四查；任一项缺失立即停止、补写后重新落盘，不进入后续评审。提交与发布由外层 checkpoint / `crctl` 流程负责，Skill 不输出手工 commit 指令。

契约确定性四查（缺即补写，均指可观察行为，实现算法归 SDD）：
- 幂等：给出指纹的确定性规则（参与字段集合、幂等键作用域、查重/重放/冲突的优先级），禁止只写「相同请求指纹」。
- 权限：给出固定判定顺序与唯一 HTTP 状态 / error code，消除「403 或 404」类并列。
- 错误闭包：每类错误 = 状态 + 固定 code + 错误体 + 零写入范围 + 客户端动作；至少覆盖输入解析 / 权限 / key 冲突 / 锁与事务失败。
- 副作用：按分支拆分、写清事务边界或补偿、失败零残留、唯一 task/资源语义，禁止「不得创建 X 却又要求创建 X」的矛盾。
```

（`crctl gate --mode pre-review` 只承载 mode/target-version 判据，不承载语义确定性检查，故此项直接并入 Step 4 既有落盘校验，不加 crctl 门禁，避免上游入侵。）

**验收**：拿 AIFI-17 第 1 轮 4 个 blocker 当回归样本，按新自检写出的 PRD 应天然满足 B-API-01~04 的修复方向；首轮评审不再因确定性缺口 block。

**影响面**：仅 write-requirement-prd 文案。
**回滚**：还原两处原文。

---

## P2 — 注册脏检查收窄到 change-requests/

**根因**：`REGISTRATION_TRUNK_DIRTY` 对 knowledge-base 整仓 `git status --porcelain`，AIFI-17 被一份无关的 `docs/product/评审run重试熔断最小方案.md`（AIFI-16 的未提交 WIP）挡住，被迫提交他人未提交文档。注册事务只写 `change-requests/`，无关 dirty 不该阻塞。

**改动（`tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs`，原位 2 处）**

两处（约 810 行「register 分配前」、828 行「账本写前」）把

```js
const st = gitRun(kb.rootPath, ['status', '--porcelain']);
```

改为

```js
const st = gitRun(kb.rootPath, ['status', '--porcelain', '--', 'change-requests/']);
```

- 871 行的 reset/rebuild 守卫（`remote stale 后主 checkout 出现用户改动`）**不动**——那是覆盖整仓 checkout 安全的关键校验，语义不同。
- 更紧的口径可选 `'change-requests/_backlog.yml' 'change-requests/_index.yml'`（两个账本文件，因为 `{CR-ID}/cr.md` 此刻尚不存在）；先用 `change-requests/` 前缀，单行改动，若后续出现「同目录其他 CR 在制品误挡」再收窄。

配套文案（`tools/skills/requirement/requirement-register/SKILL.md` 44/72/93 行，原位改）：把「knowledge-base trunk 工作区 clean」改为「knowledge-base 的 `change-requests/` 工作区 clean（无关文件 dirty 不阻塞）」。

**验收**
- 单测：`register-tx.test.mjs` 新增「`docs/` 下有未提交文件但 `change-requests/` 干净 → 注册放行」；保留「`_backlog.yml` dirty → 仍 `REGISTRATION_TRUNK_DIRTY` 且零写入」。

**影响面**：注册前置门禁的判定范围收窄，不动写路径与事务幂等。
**回滚**：删掉 `-- change-requests/` 恢复整仓检查。

---

## P3 — 需求期 PRD 边界（防过度设计，双向降本）

**根因**：单个 POST 端点被要求写到 SHA-256 canonical fingerprint（固定键序/小写/排序去重/布尔化）+ 全量错误闭包表，是实现级细节；而代码库已有先例可引用。需求期 PRD 应停在「行为 + 验收 + 引用先例」，确定性实现细节归开发期 SDD。

> 与 P1b 的边界：P1b 四查要求的是**可观察行为的确定性**（固定判定顺序、唯一状态码、副作用拆分、幂等优先级）；P3 下沉的是**实现算法**（指纹键序/哈希、错误码全量枚举表、事务实现方案）。两者不矛盾。

**改动（两处 skill 文案，原位修订，不新增章节）**

1. `tools/skills/requirement/write-requirement-prd/SKILL.md` Step 3 章节列表（第 74-81 行）第 7 条后原位加一条边界说明：

原文：
```
7. **范围排除** — 明确不做的内容
```
改为：
```
7. **范围排除** — 明确不做的内容

**需求期边界**：PRD 只写到「行为 + 验收标准 + 引用先例」这一层；确定性算法的实现细节（指纹键序/小写归一化、错误码全量枚举表、事务实现方案）归开发期 SDD，不在 requirement 期展开。
```

2. `tools/skills/requirement/review-requirement/SKILL.md` Step 2「首轮完整契约域」说明段（第 64 行）原位补一句：

原文：
```
当 PRD 定义用户可调用契约（HTTP API、CLI 或 Skill 契约）时，首轮必须在生成 verdict 前按下列闭合清单一次检查完该契约域的全部适用项；同一契约域的独立缺口必须出现在同一轮 blockers，不得在首个 blocker 处提前结束、把剩余缺口留给下一轮。缺适用项须显式写 `N/A` 及原因：
```
改为：
```
当 PRD 定义用户可调用契约（HTTP API、CLI 或 Skill 契约）时，首轮必须在生成 verdict 前按下列闭合清单一次检查完该契约域的全部适用项；同一契约域的独立缺口必须出现在同一轮 blockers，不得在首个 blocker 处提前结束、把剩余缺口留给下一轮。缺适用项须显式写 `N/A` 及原因。对已有代码库先例（idempotency 唯一键、固定错误体、锁/唯一索引等），评审只要求「引用先例 + 说明差异」，不要求 PRD 重写实现算法；确定性实现细节归开发期 SDD，不在 requirement 期阻塞。
```

**验收**：与 P1b 合验——同一份 v0.1 在「引用先例」口径下可直接 PASS；评审深度从「实现设计」回落到「可唯一验收」。

**影响面**：两个 skill 文案，不涉及任何机制。
**回滚**：还原两处原文。

---

## 实施顺序与验证

1. **P1a + P1b + P3**（纯 SKILL 文案原位修订，零风险）→ 先上，立即作用于 AIFI-17 的后续同类 CR，当天可见效果。
2. **P2**（crctl 单行 + 单测）→ 本地 `node --test` 跑 `register-tx.test.mjs` 通过后上。
3. **P0**（Go daemon，需构建/回归）→ `go test ./pkg/agent ./internal/daemon` 通过后上；这是唯一涉及上游运行时二进制的一处，单独一 PR。

## 明确不做

- **Provider 稳定性**（固定 provider/model、429 退避）：按决定排除。
- **reviewer 的 provider 模型更换**：不在本方案。
- **在 `piSessionFilePresent` 里解析 session cwd 做 resume 时二次校验**：可选加固，本次不做。
- **给 crctl 新增「语义确定性」门禁**：不加，用 SKILL 自检承载（最小上游入侵）。
- **以「追加章节」形式改 skill**：已全部改为原位修订。
