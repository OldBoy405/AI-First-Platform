# 2026-11-13-aifi-45-node-trust-root 切片执行计划

> 依据：design.md（Gate 1+2 于 2026-11-14T23:06:22 因并入 B2、B4 重签 current）、test-plan.md（12 TC，其中 TC-NTR-010/011/012 为并入）。全部切片顺序执行，并行组一律 `—`（S1–S3 都改同一个测试文件，且 S2 依赖 S1 的实现；S4、S5 各改自己的新测试文件，互不依赖，仍按序执行）。
> 长程模式（full_auto）：覆盖 tools 仓内 `crctl.mjs`、新测试文件、`gate-registry.json` 登记行的写入，以及本地 `node --test`、git 只读；**不覆盖**提交/推送/部署、修改受审文档、触碰工作树既有未提交改动（`merge-effects.mjs` 及测试、golden、`AGENTS.md`、`CUSTOM.md`、`.crctl/`）、改动 multica 仓。
> LLM 分层：简单与执行类任务由主会话给出修改指导后委派 balanced 子代理（`GB-JP/deepseek-flash:max`，actual=unknown）；断言口径审查、diff 审查、验证与偏离判断留在主会话。

## Dependency Graph Summary

```
S1 合并规则核心(TC-NTR-001/002/003/004/008) → S2 生效范围与威胁边界(TC-NTR-005/006/007) → S3 回归与登记(TC-NTR-009)
                                                                         ↘ S4 inspect authority 事实键(TC-NTR-010/011，2026-11-14 并入；S3 的回归最后对 S4 再确认一次)
                                                                         ↘ S5 crctl 的 git 不经 agent shim(TC-NTR-012，2026-11-14 并入；与 S4 互不依赖，S3 的回归最后对 S5 再确认一次)
```

## Slice Execution Plan

| # | 优先级 | 风险 | 预估工时 | 并行组 | TC 覆盖 | 实现目标 | 依赖 |
|---|--------|------|---------|--------|---------|---------|------|
| 1 | P0 | 🟡 Med | S | — | TC-NTR-001, TC-NTR-002, TC-NTR-003, TC-NTR-004, TC-NTR-008 | `crctl.mjs` 新增变量名常量、八命令集合与 `resolveTrustRoot(cmd, flags, env)`，在 `parseArgs` 之后、`bindTaskWorkspace` 之前调用一次；新增 `node-trust-root.test.mjs`；`tac-control-fixture.mjs` 增加默认关闭的“省略 --trust-root”选项 | — |
| 2 | P0 | 🟡 Med | S | — | TC-NTR-005, TC-NTR-006, TC-NTR-007 | 在同一测试文件追加八命令之外不受影响、其余生效命令与同值 flag 一致、自备根两通道等价；预期多数在 S1 实现后直接通过，任何失败说明合并点有缺口 | S1 |
| 3 | P0 | 🟢 Low | S | — | TC-NTR-009 | 四个既有 trust 测试文件在未设置变量时全部通过；`gate-registry.json` 登记新测试文件（files + cases）；`stdd structure delta` | S1, S2 |
| 4 | P0 | 🟡 Med | S | — | TC-NTR-010, TC-NTR-011 | `crctl.mjs` inspect 分支对 HEAD 纯插入两处补键（`Object.assign(result, { targetSpecId, targetVersion })` 及其取值）；新增 `workspace-inspect-authority.test.mjs`；金样本 `workspace-inspect.json` 按真实输出增补字段路径；`gate-registry.json` 登记新测试文件；最后重跑 TC-NTR-009 回归与全量套件 | S1（同一个 `crctl.mjs`，插入点不相邻） |
| 5 | P0 | 🟡 Med | S | — | TC-NTR-012 | 新增 `lib/git-shim-path.mjs`（纯函数 `stripGitShimDirs`）；`crctl.mjs` 对 HEAD 纯插入一行 import 与 `main()` 第一条语句处的一次调用；新增 `crctl-git-shim-path.test.mjs`（纯函数三个 subtest + POSIX 真实进程接线一个 subtest）；`gate-registry.json` 登记新测试文件；最后重跑 TC-NTR-009 回归与全量套件 | S1（同一个 `crctl.mjs`，插入点不相邻） |

## Rationale

### Slice 1：合并规则核心
- **依赖关系**：无前置。产出 S2/S3 使用的唯一合并点和测试夹具选项。
- **风险分析**：合并规则是跨仓接口的唯一落点；“同值通过/异值拒绝/非法值不回退/legacy 分支忽略”四种语义必须各自独立可测（经验库：每个拒绝条件独立 subtest）。
- **工作量估算**：S（`crctl.mjs` 约 20 行 + 一个测试文件 + 夹具一个可选参数）。

### Slice 2：生效范围与威胁边界
- **依赖关系**：依赖 S1 的合并点。
- **风险分析**：八命令清单与实际消费者漂移，或误对 kb/git/白名单命令注入变量；自备根测试被误读为平台授权证明（断言口径是“两通道一致”）。
- **工作量估算**：S（只追加测试，预期无生产代码变更）。

### Slice 3：回归与登记
- **依赖关系**：S1、S2 完成。
- **风险分析**：套件门禁要求测试文件在 `gate-registry.json` 登记 files + cases，漏登记会让全量 suite 失败。
- **工作量估算**：S。

### Slice 4：inspect authority 事实键（2026-11-14 并入）
- **依赖关系**：与 S1–S3 在同一个 `crctl.mjs`、同一个冻结输入目录；插入点相互独立（S1 在 main 的参数解析边界，S4 在 `workspace` 命令的 inspect 分支）。
- **风险分析**：①改既有行会破坏 multica 覆盖版「只许增行」检查，故只许插入；②`Object.assign(result, ...)` 依赖 `result` 为新建对象，BUILD 时核对；③金样本被工作树标 M，编辑前重新核实与 HEAD 一致；④新测试文件注释勿写 `crctl <子命令>` 字面量，且须在 `gate-registry.json` 登记；⑤失败时 null 而不抛错，不新增错误码。
- **工作量估算**：S（生产代码约 10 行插入 + 一个测试文件 + 金样本 + 登记行）。

### Slice 5：crctl 的 git 不经 agent shim（2026-11-14 并入）
- **依赖关系**：与 S4 互不依赖；两者都改 `crctl.mjs`（插入点不相邻），由 S3 的回归最后确认。
- **风险分析**：剥离只改 crctl 自己进程的 PATH，但会影响其全部子进程（含 `runTestPlan` 的声明命令）——决策 8 已明示；`crctl.mjs` 对 HEAD 必须仍是纯插入；真实进程接线子用例在 win32 skip，本机取证不证明接线，须在 test-report 如实写明；识别字面量与 multica shim 形态的耦合由接口锚定与 TC 固定。
- **工作量估算**：S（新文件约 25 行 + `crctl.mjs` 2 处纯插入 + 一个测试文件）。
- **跨仓事项**：multica 固定来源副本的覆盖清单要加入新文件（multica 侧脚本任务，见 multica `tasks.md` §13），不在本切片内。
