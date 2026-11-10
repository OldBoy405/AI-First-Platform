> **口径说明（2026-11-10 手工补注）**：`stdd structure delta` 取的是整个工作树 diff，因此下表还包含与本次无关的在途 AIFI-45 改动，并且可能漏掉新增文件。本 change 实际触及的 tools 文件如下：

> - `skills/shared/crctl/scripts/lib/execution-control-protocol.mjs`
> - `skills/shared/crctl/scripts/test/execution-control-protocol.test.mjs`
> - `skills/shared/crctl/scripts/test/control-operation-domain.test.mjs`
> - `skills/shared/crctl/scripts/test/fixtures/control-vectors.json`
> - `skills/shared/crctl/scripts/test/gate-registry.json`

> 以源代码为准；下表仅作参考。

# Code Structure Delta — 2026-10-29-trusted-verdict-outcome-binding
> 生成时间: 2026-11-10T15:54:31.163877 | Git commit: f774ffb
> 置信度: 0.70 (AI-generated — 以源代码为准)

## 变更文件

- `skills/shared/crctl/scripts/lib/execution-control-protocol.mjs`
- `skills/shared/crctl/scripts/lib/merge-effects.mjs`
- `skills/shared/crctl/scripts/test/control-operation-domain.test.mjs`
- `skills/shared/crctl/scripts/test/execution-control-protocol.test.mjs`
- `skills/shared/crctl/scripts/test/merge-effects.test.mjs`