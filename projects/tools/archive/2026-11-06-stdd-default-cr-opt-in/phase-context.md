# BUILD 恢复上下文

- Change：`2026-11-06-stdd-default-cr-opt-in`；业务根 `../tools`，数据根知识库 `projects/tools`；所有命令显式带本 ID。
- 2026-11-15：受审文档已按当前合同整体重写（design 四条保证与四个 TC、test-plan 证据计划、specs、Canonical agent 规格、`pending-adjustments.md`）。提案未变。旧的十个 CP／TC 及其字符串断言已被取代；旧验收结果只在 git 历史中。
- 批准状态：Gate 1、Gate 2 已于 2026-11-15 10:27 经用户原话（`dialog`）`--reapprove` 重签并带输入指纹；Gate 3 pending。受审文档（design、specs、test-plan、Canonical 规格、`.canon-index.yaml`、proposal）重签后不得再改，要改须再次重签。
- 入口文案已全部实施：tools `AGENTS.md` 的 CR 驳回路由段已改为引用权威（tasks 2.1）；C1 评审后按 SC-PG-001 又删除该文件的状态链与固定计数、调整知识库 `AGENTS.md` 两处措辞（见 ADJ-003）。
- C1 三路评审、TC-WFR-001 盲评（已按修改后的入口重做）、evidence run（`f16c6ed3-7c01-40b9-ad07-8a7ff7a110c4`）与两条人工确认均已完成，原生 TC 证据 4/4；C4–C7 已写入 `test-report.md`，`slices_completed` 已写。ADJ-003 用户已接受。Gate 3 已于 2026-11-15 11:03:06 由用户确认（`dialog`，原话“确认 Gate 3”）。- Gate 3 确认：2026-11-15 11:03:06，`--confirmed-by dialog`，用户原话“确认 Gate 3”。确认框把“tools 全量测试未运行”的处置与“顶层文件哈希由人工重算”列为确认内容，用户随 Gate 3 一并确认，未单独作答。
- 记录（后于 Gate 3 才发现，未写入 test-report）：`stdd validate` 现报 1 条 SKIP 警告“SC→TC 映射无法核验: 规格无可识别的 SC 编号”。原因不在本 change：2026-11-15 10:53，STDD 资源包 `../stdd/stdd/cli/commands/validate.py`、`ci.py` 被会话之外的改动更新（未提交），原先“TC 案例数 ≥ Spec Scenario 数”的检查换成只读 `canonical/specs/code/*.yaml` 的 `sc_mapping_verdict`；本 change 是文档类变更，只有 `specs/agent`，故 SKIP 而非 FAIL。Gate 3 确认后用当前代码重跑 `ci check-failures`，仍 9/9 通过。
- 记录：Gate 3 确认后曾把上述两条写进 `test-report.md`，该文件是 Gate 3 的冻结输入，`stdd status` 随即报“Gate 3 批准已过期”；已按批准时的字节还原（LF SHA-256 `cac0ad86…0fe3` 与清单一致），Gate 1/2/3 恢复当前批准，未重签、未改受审文档内容。
- 下一步：DELIVER。Step 1 合并 canonical 到项目级并更新项目 `.canon-index.yaml`；Step 2 `stdd archive`（自动合并 Human View 到 `specs/<capability>/`）；Step 3 起两仓逐文件清单，提交须用户逐文件授权；tasks 4.1 交付前重算哈希。
- 范围外发现（不在本 change 范围，需所有者处理）：
  - `../tools/CLAUDE.md` 仍要求 Claude 无条件读取完整 README，与按需加载冲突。
  - 知识库被 Git 忽略的 `.claude/settings.local.json` 含疑似明文令牌的字面值（2026-11-15 仅检测形态，未打印值，未验证有效性，未修改文件）；需所有者检查并按需轮换。
- 没有 Git 提交、推送或部署授权，不得执行；不得清理其他在途 dirty。
