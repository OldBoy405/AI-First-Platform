---
id: __CR__-sdd
type: SDD
cr-ref: __CR__
prd-ref: "change-requests/__CR__/prd.md"
target-version: 0.46
status: approved
created: "__AT__"
---

# __CR__ 技术设计（fixture 快照）

## 1. 设计概览与不变量

| 不变量 | 内容 | 落点 |
|---|---|---|
| I1 | 新模块是纯函数层：无 I/O、无时钟、无全局状态 | FR-1 / FR-2、AC-1 / AC-2 |
| I2 | 非法入参一律返回 `null` / `""`，不抛异常（分支责任留在调用方） | FR-1、AC-1、AC-2 |
| I3 | 不新增依赖、不改既有模块导出面 | FR-2、§8 `zero_diff` |

### 1.1 既有实现依赖与事实

无：本快照是 greenfield（新增单文件 + 单测试文件），不消费既有符号，不依赖 `dep-N`。

## 2. 接口契约

| 符号 | 签名 | 语义 | 错误面 |
|---|---|---|---|
| `parseDuration` | `parseDuration(text: string): number \| null` | 解析 `"1h30m"` → 毫秒；非法输入 → `null` | 不抛异常 |
| `formatDuration` | `formatDuration(ms: number): string` | 毫秒 → 规范化文本；负数 → `""` | 不抛异常 |

## 3. 交付项与落点

| FR/AC | 交付项 | 文件 |
|---|---|---|
| FR-1 / AC-1 | `parseDuration` 纯函数 | `tools/scripts/duration.mjs` |
| FR-2 / AC-2 | `formatDuration` 纯函数 | `tools/scripts/duration.mjs`（同文件） |

## 4. 验证策略

定向单元用例分别覆盖 AC-1 与 AC-2 的可观测结果；用例名稳定（`duration parse targeted case`、`duration format targeted case`），关键证据命令按最窄用例选择（两案各自只跑一个用例）。

## 5. 风险与回滚

单文件新增，回滚 = 删除该文件与其测试文件；无数据迁移、无共享服务、无兼容性影响。

## 6. 非目标

不含 CLI 入口、不含本地化与时区处理、不接任何账本、状态机或门禁。

## 7. 多仓口径

改动只在 `tools` 仓单文件；KB 仓只承载本快照的过程文档。

## 8. 批准范围

- `scope_in`：`tools/scripts/duration.mjs` 的 `parseDuration` / `formatDuration` 两个纯函数；其定向用例文件 `tools/scripts/duration.test.mjs`。
- `scope_out`：CLI 入口、本地化、既有模块导出面改动、任何全仓质量门槛调整。
- `zero_diff`：`tools/skills/**`、`skills/shared/crctl/**`、状态机、gates、pipeline、账本字段。
- `follow_up`：若后续需要 CLI 入口，另立 CR。
