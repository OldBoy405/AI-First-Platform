# AIFI-45 一次性库实例生命周期与测试守卫边界 — 切片执行计划

## Dependency Graph Summary

```
S1 (TWG: guard + test-go.test.sh) ──────────────────────────────┐
S2 (instance.mjs: 信封/启动/释放 + 单元) ─┬─► S3 (真实 TTL 强杀)
                                             └─► S4 (run-selection 接线 + 真实入口运行)
S5 (governance 身份核验 + selections.identity.json 两个单测试选择) ─┘（经 S4 的入口验证）
```

**并行化说明**：依赖图零依赖节点是 S1、S2、S5，但本次由主会话顺序执行，不派并行子代理（共享 podman 与同一仓库，收益小于协调成本）。
- 并行组 1（理论上）：S1、S2、S5。
- 并行组 2：S3（依赖 S2）、S4（依赖 S2，最终回归依赖 S5）。

## Slice Execution Plan

| # | 优先级 | 风险 | 预估工时 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|--------|------|---------|--------|---------|---------|------|
| 1 | P0 | 🟢 Low | S | 组1 | TC-TWG-001, TC-TWG-002, TC-TWG-003 | guard 与 `test-go.test.sh` 拒绝含 `:` 的 TMPDIR | 无 |
| 2 | P0 | 🟡 Med | M | 组1 | TC-DTI-001, TC-DTI-003, TC-DTI-004 | `instance.mjs`：`buildRunArgs`、`startInstance`、`releaseInstance` | 无 |
| 3 | P0 | 🟡 Med | S | 组2 | TC-DTI-005 | `instance.real.mjs` 的强杀 TTL 用例 | 2 |
| 4 | P0 | 🟡 Med | M | 组2 | TC-DTI-002, TC-DTI-006 | `run-selection.mjs` 接线、`run-selection.test.mjs`、真实入口用例 | 2 |
| 5 | P0 | 🟡 Med | M | 组1 | TC-DTI-007 | governance TestMain 身份核验、拒绝测试、`selections.identity.json` 的 `governance-nonce-gate` 与 `governance-identity-check` 单测试选择、注释修正 | 无（入口验证经 4） |

## Rationale

### Slice 1: TMPDIR 拒绝（P0，先行）
- **依赖关系**：与其余切片无关，改动小，先完成可早早验证 bash 测试基础设施。
- **风险分析**：经验库无匹配。TC-TWG-001 需在修复前观察到标记文件（RED），该复现只在私有目录内用假命令。
- **工作量估算**：S，两个脚本、各加一个 case 判断，测试写在 `test-go.test.sh`。

### Slice 2: instance.mjs（P0）
- **依赖关系**：S3、S4 的基础。
- **风险分析**：释放判定是本 change 最敏感的逻辑（误删他人容器），单元测试覆盖四种归属不匹配。真实 podman 行为已在 2026-11-11 00:20 的探测里确认：`--rm --timeout=12` 在 12 秒左右移除容器，无遗留卷，端口 `127.0.0.1:<port>`，ID 64 位，标签读回格式为单个 `key=value`。
- **工作量估算**：M，一个模块加一个测试文件，`run` 与 `connect` 注入。

### Slice 3: 真实 TTL（P0）
- **依赖关系**：需要 `startInstance`。
- **风险分析**：此前只做过命令行探测，本切片把它变成可重复的门控测试：子进程创建后被强杀，父进程轮询读回。
- **工作量估算**：S。

### Slice 4: 入口接线（P0）
- **依赖关系**：依赖 S2。`--admin-url` 拒绝的测试不需要 podman。
- **风险分析**：改动既有入口；13 选择的完整 `selections.json` 运行是 C2 回归，需 `AIFI45_TOOLS_ROOT`，不属冻结证据。
- **工作量估算**：M。

### Slice 5: governance 身份（P0）
- **依赖关系**：代码独立；TC-DTI-007 的冻结证据使用 `selections.identity.json` 的 `governance-nonce-gate` 与 `governance-identity-check` 两个单测试选择，经入口运行，验证排在 S4 之后。
- **风险分析**：TestMain 改动影响整个 governance 包；用 RED（临时去掉核验）证明拒绝测试能发现问题。
- **工作量估算**：M。
