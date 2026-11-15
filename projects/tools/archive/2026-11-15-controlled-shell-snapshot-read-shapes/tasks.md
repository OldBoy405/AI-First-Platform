# 2026-11-15-controlled-shell-snapshot-read-shapes 任务清单

## 1. controlled-shell git show 只读形状（P0）

- [x] 1.1 新增 `skills/shared/crctl/scripts/test/controlled-shell-rules.test.mjs`：读真实 `rules.json`，按 `crctl.mjs controlledGit` 语义构造 RegExp（`args.join(' ')` + `test`），用例 1 为放行表（TC-CSS-001），用例 2 为拒绝表（TC-CSS-002）
- [x] 1.2 运行新用例确认 RED：TCCSS001 因 `show.shapes` 缺三种形状而失败，TCCSS002 在改前即通过（拒绝表在放宽前后都必须成立）
- [x] 1.3 `rules.json` 的 `git[sub=show].shapes` 末尾追加三条锚定形状，原两条逐字保留
- [x] 1.4 复跑两个用例 → GREEN；跑全量 `quality.test` 确认无回归

## 2. 文档同步与范围核对（P1）

- [x] 2.1 `controlled-shell/SKILL.md` 的命令白名单新增 `show` 行，逐条列出 5 种形状（依赖 1.3）
- [x] 2.2 `CUSTOM.md` 的 CUSTOM-TODO-017 描述改为与规则一致，注明 `callers` 当前仅声明、不强制；登记本 change（依赖 1.3）
- [x] 2.3 TC-CSS-003：对比 HEAD 与改后 `rules.json`，除 `git[sub=show].shapes` 外无差异、原两条逐字保留（依赖 1.3）
- [x] 2.4 TC-CSS-004：multica 仓 `MULTICA_CONTROLLED_SHELL_RULES` 指向本仓规则文件，跑 6 个测试；「已提交」部分在提交后复验（依赖 1.3）
- [x] 2.5 TC-CSS-005：人工对照 SKILL.md、CUSTOM.md 与 `rules.json` 逐条一致（依赖 2.1、2.2）

## 3. 收尾

- [x] 3.1 `stdd structure delta` 记录本 change 的结构变化
- [ ] 3.2 C1–C7 质量验证、`test-report.md`、Gate 3 用户确认
