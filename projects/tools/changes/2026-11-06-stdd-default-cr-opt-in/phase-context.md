# BUILD 恢复上下文

- Change：`2026-11-06-stdd-default-cr-opt-in`；业务根 `../tools`，数据根为知识库 `projects/tools`；显式传入 change ID。
- 用户 2026-11-10 最新决定：原位统一 ADJ-001 当前措辞；仅在 STDD 不要求时删除手工 spec；调查文档验收合法路径，不能落地则记录工具缺口并停止。只编辑本 change，不修改业务／全局入口、STDD 代码或其他变更，不批准 Gate、不提交。
- 最新复核将 tools `AGENTS.md` 平台包边界中笼统的“在途变更”限定为“在途 CR”，明确其他流程记录按自身规则管理；8 项针对分流及隔离条款的文本检查通过，tools lint enforce exit 0。此为本 change 范围内的文案修正，不是实际路由验证。
- 历史 Gate 2 已确认方案 A。用户后续原话为“确认采用这段合并措辞，启用长程模式”，再明确“暂用普通模式继续”。长程模式未启用；当前 BUILD / in_progress、Gate 3 pending。2026-11-10 只读 gate status 实查 Gate 1／2 为 historical/unfingerprinted；修订版 Gate 2 仍待按 Skill 重新展示确认，CLI 不自动判 stale，历史记录的 reapprove 还会幂等返回。本轮不修改原批准。
- 目标六文件的入口文案此前已实施。修订前 10 个静态 action 的历史结果为 9/10，旧 CP-PG-003 失败及当时合并措辞检查通过的事实保留在 ADJ-001。2026-11-10 已按授权统一 D5／Canonical CP-PG-003／TC-PG-003／spec，只保留批准新句这一当前预期，当前执行结果见 test-report，不继承替代检查为 PASS。ADJ-001 设计层已处理，但正式 Gate 2 确认未完成，resolved 仍 false；ADJ-002 未处理。
- lint report / enforce 与两项 tools 合同检查的历史复验时间为 2026-11-06 13:48（+0800），当时均 exit 0；本轮不重跑业务 quality。2026-11-10 修订后的 STDD validate／proposal validate／canon verify／ci check-failures 结果见 test-report；静态 CP 不产生原生 TC 证据，CLI 确定性子集以外的失败模式未全量执行。
- tools 全量测试尚未运行：其中隔离证明可能操作 WSL root、固定宿主路径和 detached 子进程，尚未建立足以保护宿主的隔离边界。不可把未运行写为通过。
- `specs/*/spec.md` 因 BUILD A1 回退读取及 DELIVER Step 2 合并要求保留，只作兼容视图；评审直接引用 Canonical CP，不另设同步来源。STDD 原生支持 command/manual、coverage 不适用声明，但项目级 CP 读取／共享报告写入／输入仅支持 project/data 根的限制，使本 change 的跨根文档验收无法在许可范围内闭合，详见 design D7；并非工具完全不支持文档任务。普通模式下记录该工具缺口后停止 BUILD；不制造 coverage.json、不手改 `.stdd.yaml`、不调用 agent verify、不关闭 quality 检查。原生切片证据、`design-adjustments.yaml` 和 Gate 3 均未完成。
- `../tools/CLAUDE.md` 按需加载冲突及既有 CR 事实漂移不在已批准范围；`test-report.md` 已记录。另在知识库被 Git 忽略的 `.claude/settings.local.json` 发现疑似明文令牌常量；未验证有效性或修改文件，不在此记录值，需所有者检查和按需轮换。
- 没有 Git 提交、推送或部署授权，不得执行；不得清理其他在途 dirty。
