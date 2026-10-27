# DELIVER — 可信 T 裁决通道（M003）

> 本文件是本 change 的交付记录。Gate 3 已由用户口头确认（见 `validation/gate3-readiness.md` §8）。
> **两仓源码改动按用户决定保持未提交**（选项 a），因此「已交付」指「已实现 + 已出证 + 已登记台账」，不含 push。

## 1. 交付范围

| 项 | 数量 | 说明 |
|---|---|---|
| 验收 label | 37（go 28 / node 9） | `channel-test-expectations.json` 冻结名单 |
| 证据行 | 42 | 每条含 `verify` 通过 + `meta.json` 干净判据 |
| 新增 DB 表 | 14 | 648 单一迁移，含 10 个触发器函数、部分唯一索引，无 FK/cascade |
| daemon 端点 | 5 | verdict / merge-facts / merge-effects / consumption 复用 / activation 复用 |
| multica 改动文件 | 59 | 见 `fork-changed-files.txt` |
| tools 改动文件 | 23 | 见配对 change 的 `delivery/fork-changed-files.txt` |
| 变异归档 | 112 patch | 107 可打到当前源码，5 条为历史记录（见 `validation/mutations/README.md`） |

## 2. 三个切片的核心不变量

- **裁决 store 不可伪造**：`(request, epoch, seq)` 唯一、帧链 digest 断链即拒、ACK 不释 slot、撤销先提交则 no_effect。
- **权威只来自持久化事实**：strict/legacy/unknown 三态，unknown 不降级；fence 取并集（已有 consumption ∨ strict selection）；无 committed T 则零派发。
- **T 决定 ready，M 只做身份/绑定/generation/有效期/CAS**：`verify-channel` 只能出 `READY_COMPONENT`，`READY_STRICT` 只来自 `enable-policy×strict-production`。

## 3. 未声称的（Gate 3 材料必须一并带上）

| 项 | 原因 | 处置 |
|---|---|---|
| `strict-production` | 本 change 只按 `channel-component` 验收（ADJ-4）；`READY_STRICT` 需 `admission_decider === 'present'`，完整 decider 属 AIFI-45 剩余工作 | 下游，另开 change |
| Windows 平台隔离（node 2 / go 3 leaf） | 无第二个受限 Windows 令牌（ADJ-10），且 Windows 驱动未实现 | ADJ-13 延后；**冻结 leaf 不删**，`verify --platform windows` 仍失败 |
| 对 agent 的隔离 | agent 以 GOBAO 运行，可 `wsl -u root` 免密 | ADJ-10 接受为残余风险 |
| execve 审计 | WSL 非初始 PID 命名空间，auditd 不可用 | bpftrace `sched_process_*` 替代（`p0-isolation-evidence.md`） |

## 4. 验证入口（可复跑）

```bash
# 单 label 证据复核（任一 label）
node scripts/aifi45-verify/channel-evidence.mjs verify binding \
  "<change>/validation/bi4-20261027T144831Z" \
  --expectations "<change>/validation/channel-test-expectations.json" --side go

# CP 覆盖审计（须在 change 目录内运行）
node scripts/aifi45-verify/channel-evidence.mjs audit .

# 数据库测试（每轮独占 nonce 库；不加 642）
node scripts/aifi45-db/run.mjs ./internal/governance '^TestChannelIngestBinding$' <prefix> \
  -migration=server/migrations/643_cr_execution_binding_issue.up.sql ... -migration=server/migrations/648_cr_execution_control.up.sql

# Node 侧（cwd = tools/skills/shared/crctl/scripts）
AIFI45_ISOLATION_PROFILE=995:994 AIFI45_ISOLATION_AGENT=994:993 \
  node --test --test-reporter=tap test/execution-control-isolation.test.mjs
```

`meta.json` 必须 `original_unchanged:true`、`owned_resources_cleaned:true`、`skip:0`，否则该轮不算。

## 5. 交接事项

| 对象 | 内容 |
|---|---|
| AIFI-45 | `validation/aifi45-run-tc-rerun-prerequisites.md`：六条 RUN TC 的重跑前置、逐条 M003 贡献与不在范围项。**41/49 未回填**，计数仍归 AIFI-45 |
| 本 change（待环境） | 独立 Linux 主机重跑 P0 隔离（agent 账号无 sudo）→ 结掉 ADJ-10 与 auditd 替代 |
| 台账 | `multica/CUSTOM.md` M14 已登记 #221–#235（16 行），是 fork 定制与 rebase 核对的唯一清单 |

## 6. lint 口径（`stdd validate` 的一条警告）

`stdd validate` 报 `spec.md: AND 数量 (35) 超过上限 (5)`。这是**整文件**计数的启发式（`stdd/cli/commands/validate.py` 对全文 `**AND**` 计数，阈值 5）；权威规则在 `ci.py::check_and_count`，按 `### Scenario` 切块**逐场景**计数、阈值 5。

实测权威检查：`stdd ci check-failures` → `✓ (g) AND 数量正常`（6 通过 / 0 警告 / 0 错误；同时 `(d) TC-ID 唯一 45 个`、`(f) THEN 含 SHALL`、`(k) 契约一致 2 capabilities` 均通过）。

结论：**误报，不改规格**。本规格有 35 个场景、每个 1 条 AND，属正常形态；为消除提示去合并或删除 AND 子句会改动 Gate 2 冻结的规格文本，代价高于收益。

## 7. 交付提交状态

- 记录仓（本工作区）：Gate 3 记录、本交付文档、交付清单均在提交内。
- 源码仓：**未提交**（用户决定 a）。multica 侧 `CUSTOM.md`、`server/cmd/server/router.go`、`server/internal/governance/execution_dispatch_root.go` 为改动文件，其余为新增；`server/pkg/db/generated/*.sql.go` 12 个生成物按约定不提交。
- 未归档：`stdd archive` 属独立决定，本阶段未执行；`stdd` CLI 在本机解析不到该 change（见 §8 记录方式说明）。
