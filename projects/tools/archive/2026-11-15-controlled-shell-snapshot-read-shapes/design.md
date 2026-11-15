# controlled-shell 白名单放宽 3 种 git show 只读形状 - 技术设计

## Context

- 权威规则：`skills/shared/controlled-shell/rules.json`。`git[sub=show].shapes` 现有两条：
  1. `^<40hex>:change-requests/CR-…/review-annotations/(requirement|sdd|dev-plan|code).yml$`
  2. `^<40hex>:change-requests/(_backlog.yml|_history.yml|CR-…/cr.md)$`
- 两个消费方对规则的解释**完全相同**（已读源码核实）：
  - tools：`crctl.mjs` 的 `controlledGit`（约 602–603、618–650 行）用 `new RegExp(shape)` 构造，`args.join(' ')` 后 `re.test`。
  - multica：`server/pkg/gitguard/gitguard.go` 的 `Check`：`strings.Join(args, " ")` 后 `re.MatchString`。
- **`callers` 字段目前只是声明，两个消费方都不读取、不强制**（`gitguard.go` 无 callers 解析；`crctl.mjs` 无 `.callers` 访问）。因此放宽 `show` 的效果是：任何走该 guard 的调用方都得到这三种读取，不只 system-orchestrator。已有的两条 show 形状本来就是如此，本 change 不改变这一事实，只在 design 与 Gate 2 里明示。
- multica 的 `TestProposedSnapshotReadShapes`（`crevents_test.go:946`）固化了它需要的三种形状和 11 种必须继续拒绝的近似形状。
- 实测（2026-11-15）：`MULTICA_CONTROLLED_SHELL_RULES` 指向本仓真实 rules.json 时，该测试及 5 个 `TestM26B2/B4*` 共 6 个失败；指向「加了三种形状的临时副本」时 6 个全过。

## Decisions

### 1. 在 `show.shapes` 末尾追加三条独立形状，原两条不动

**方案**（JSON 里是双反斜杠，这里写成正则源码，`<CR>` = `CR-(?:[A-Z][A-Z0-9]{1,7}-)?[0-9]{4}-[0-9]{3,}`，与现有两条使用同一 KEY 片段）：

- `^--name-only --format= [0-9a-f]{40}$`
- `^[0-9a-f]{40}:change-requests/<CR>/test-report\.md$`
- `^[0-9a-f]{40}:change-requests/<CR>/trace\.tests(?:\.yml|\.yaml|\.json)?$`

**为什么**：每条只对应一种读取，全部 `^…$` 锚定、sha 固定 40 位小写 hex，不含 rev 名、分支名；diff 一眼可审，将来要收回其中一种只删一行。

**备选方案及排除原因**：
- 备选 A：合并进现有第 2 条的 alternation。该条已是三选一，再并入会变成难审的长正则，收回一种读取要改正则内部。
- 备选 B：放宽成 `change-requests/.*`。把账本、approval、任何文件都纳入，违背 multica 测试固化的「approval.yml 是 ledger，永不作为快照输入」。
- 备选 C：撤回 TODO-017 措辞、让 multica 自带规则。用户已于 2026-11-15 裁定不采用。

### 2. 一个 tools 侧测试，用与真实消费方相同的语义检查「放行表 + 拒绝表」

**方案**：新增 `skills/shared/crctl/scripts/test/controlled-shell-rules.test.mjs`（`node --test`，零第三方依赖）。读取真实 rules.json，找出 `git[sub=show]`，按 `crctl.mjs` 的方式构造 RegExp（字符串或 `{re, flags}`），对 `args.join(' ')` 做 `test`。两个用例：

- 放行表：新三种形状（含账本式 KEY、`trace.tests` 四种后缀）与原两种形状，各至少一个正例。
- 拒绝表：multica 已固化的 11 种近似形状原样搬入（简写 sha、`HEAD:`、路径穿越两种、非批准文件 `prd.md`、`trace.tests.exe`、`approval.yml`、`package.json`、后缀松弛、小写 KEY、9 位 KEY）。

**为什么**：这是本 change 唯一会写进代码库的保证，一个测试两张表足够；拒绝表是防止「放宽」变成「放得过宽」的唯一护栏。

**备选方案及排除原因**：
- 备选 A：额外加「所有 show 形状必须锚定」的元断言。11 种拒绝形状已覆盖锚定失效的几种典型后果；再加一条是第二套判据，不加。
- 备选 B：在 tools 里调用 Go 的 gitguard。tools 无 Go 工具链，且跨仓。

### 3. 跨仓一致性只做一次性验证并记录，不做成自动化

**方案**：BUILD 完成后，在 multica 仓对该 rules.json 跑 6 个测试（命令与结果、multica HEAD sha 写进 test-report）。

**为什么**：两个消费方的匹配语义已核实相同，tools 测试镜像它已足够；真正把 multica 真实消费方接入 CI 是 multica 的 M3（升级 pin 并接线），不属于本 change。

**备选方案及排除原因**：把它做成 CP 命令：证据会依赖相邻仓当时的 HEAD，不可复现，反而削弱证据。

### 4. 文档同步

**方案**：`controlled-shell/SKILL.md` 的 `show` 说明增加三种形状；`tools/CUSTOM.md` 的 CUSTOM-TODO-017 描述改为与代码一致（它声称已补的内容现在才成为事实），并补一句「`callers` 当前仅声明、不强制」。

**备选方案及排除原因**：不改 SKILL.md。会让文档继续落后于规则，重复 TODO-017 的问题。

## Architecture

```
rules.json (权威)
  └─ git[sub=show].shapes ── crctl.mjs controlledGit        (tools)
                          └─ pkg/gitguard.Check             (multica，MULTICA_CONTROLLED_SHELL_RULES)
本 change：只在 rules.json 追加三条形状；新测试按同一语义验证放行表与拒绝表。
```

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| 放宽安全白名单，形状写宽 | 全部 `^…$` 锚定；拒绝表 11 种；diff 复核只动 `show.shapes`（TC-CSS-003） |
| `callers` 未强制，放宽对所有调用方生效 | 如实写入 design 与 Gate 2；三种对象都是只读且限定到某一提交的固定文件名，与已有两条同级 |
| tools 测试与 Go 实现的正则方言差异（JS 与 RE2） | 所用语法只有锚点、字符类、`(?:…)`、`{n,m}`，两种方言一致；跨仓一次性验证补一道（TC-CSS-004） |
| 临时副本验证不等于已提交内容 | 以已提交的 rules.json 重新验证并记录 |
