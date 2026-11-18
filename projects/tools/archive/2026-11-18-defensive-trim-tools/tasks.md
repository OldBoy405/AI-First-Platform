# 2026-11-18-defensive-trim-tools 任务清单

## 1. OutputGuard 首行逃生口（P0）

- [x] 1.1 TC-OGE-001/002 先写，删除 `core.mjs` 恒假的换行条件与 `policy.json` 的 `escapeHatch.singleLine`

## 2. 交付配置与就绪（P0）

- [x] 2.1 TC-EVD-101–104：`component-readiness.mjs` 区分读失败与非法声明，`crctl.mjs` 分流采集并输出 `EVIDENCE_COMPONENT_CONFIG_INVALID`
- [x] 2.2 `evidence-delivery.mjs` 只合并组件 findings；迁移 `evidence-components-false` 的可达保证后删除该测试

## 3. 回写候选同源读取（P0）

- [x] 3.1 TC-WSC-001/002/003：`readWritebackBase` 同读正文与摘要，三个生成器改用，删生成侧 `readHashRaw`

## 4. 回写应用冲突与冻结续办（P0，依赖 3）

- [x] 4.1 TC-WSC-004–009：`readHashRaw` 只对 `ENOENT` 返回 `null`；`fresh` 区分新事务与续办（合并原 `checkBefore`）

## 5. 验收

- [x] 5.1 同步 `gate-registry.json`（suite-gate 实测文件与用例数），再对照 design.md「Phase 3 验收清单」逐项核对
- [x] 5.2 同次执行证据与全量回归：`dt-20261118-201625` 15/15 CP/TC，15 个项目输入在合入修复后未变，当前 CLI 9/9；最终源码树与 Linux Node 20 已通过的组合树完全一致（suite-gate 100/100 文件、0 失败/取消，2 项平台跳过；writeback 24/24）。最终 Windows `quality.test` exit 0，2426 通过、0 失败/取消、1 平台跳过。旧 writeback 跨秒波动在 HEAD 复现，不在本 change 范围；详见 [test-report.md](test-report.md)。
