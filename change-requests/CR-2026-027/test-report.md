---
cr: CR-2026-027
status: pass
tester: "OldBoy405"
generated-by: crctl-test
generated-at: "2026-08-10T14:02:08+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/crctl.test.mjs", exit: 0, log: "change-requests/CR-2026-027/test-evidence/cmd-01.log" }
  - { command: "node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-027/test-evidence/cmd-02.log" }
---

# 测试报告 · CR-2026-027

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-027/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | 0 | change-requests/CR-2026-027/test-evidence/cmd-01.log |
| 2 | `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | 0 | change-requests/CR-2026-027/test-evidence/cmd-02.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

## 新 blocker 回修后重测（148/148）

- **148/148 全绿**，`lint-prompts enforce` 0 findings。
- **server-approve 签名完整性**：真实 TTY 调用 `approve --resign` 时返回 `RESIGN_SERVER_APPROVAL_UNSUPPORTED`，approval.yml 字节不变；服务端审批必须按新 digest 重签 grant。
- **YAML 安全**：真实 resign 路径覆盖 reason/approver 中的双引号、`#`、反斜杠与换行，迁移后 `validate`、developing gate 均通过。
- **CRLF 与唯一定位**：真实 resign 成功路径改用 CRLF fixture，写入前规范化为 LF；重复审批段、重复或缺失 `evidence-digest` 均返回 `SCHEMA_INVALID`，approval、audit 和 Git HEAD 保持不变。
- **AC-9b CAS 冲突**：通过进程内 fs 读后并发改写注入，真实触发 `CAS_CONFLICT`；backlog 仅保留竞争写入，幽灵块未被清理，audit.log 无 ghost 成功记录。
- **approve --resign 真实成功路径**：模拟 TTY 输入 `yes`，执行生产命令路径并验证 approval CAS 改写、成功审计、受控 Git 提交、审批本体字段保留及 gate 复绿。
