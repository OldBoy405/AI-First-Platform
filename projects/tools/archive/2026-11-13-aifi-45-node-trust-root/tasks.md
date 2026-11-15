# 2026-11-13-aifi-45-node-trust-root 任务清单

> 委派约定：标「→B」的任务由主会话给出修改指导后委派 balanced 子代理；标「→M」的由主会话执行。禁止触碰工作树既有未提交改动（`merge-effects.mjs` 及测试、golden、`AGENTS.md`、`CUSTOM.md`、`.crctl/`）。

## 1. 合并规则核心（P0，S1）
- [x] 1.1 →B 夹具：`tac-control-fixture.mjs` 的 `invokeControl`/`invokePlain` 增加默认关闭的省略 `--trust-root` 选项，既有调用点不变
- [x] 1.2 →B RED：新建 `node-trust-root.test.mjs`，写 TC-NTR-001/002/003/004/008（顶层 `test('TC-NTR-xxx ...')`，拒绝条件独立 subtest），确认失败
- [x] 1.3 →M 审查 RED 的断言口径与失败原因
- [x] 1.4 →B GREEN：`crctl.mjs` 增加 `CRCTL_EXECUTION_TRUST_ROOT` 常量、八命令集合、`resolveTrustRoot`，在 main 里调用一次
- [x] 1.5 →M 审查 diff；S1 验证（B3.4）并写 `.stdd.yaml`

## 2. 生效范围与威胁边界（P0，S2）
- [x] 2.1 →B 追加 TC-NTR-005/006/007
- [x] 2.2 →M 审查；跑通；若有失败判断是测试缺陷还是合并点缺口；S2 验证

## 3. 回归与登记（P0，S3）
- [x] 3.1 →M 运行 TC-NTR-009（四个既有测试文件，未设置变量）
- [x] 3.2 →B `gate-registry.json` 登记 `node-trust-root.test.mjs`（files 与 cases），不改其他条目
- [x] 3.3 →M `stdd structure delta`；C1–C7 评审与质量检查；test-report；Gate 3 等用户确认

## 4. inspect authority 事实键（P0，S4，2026-11-14 并入；Gate 1/2 重审通过后才写代码）
- [x] 4.1 →M 核实金样本 `workspace-inspect.json` 内容与 HEAD 一致（`git diff HEAD --quiet`）；核对 `ensureWorkspace` 三处返回为字面量；grep inspect 输出的消费者
- [x] 4.2 →B RED：新建 `workspace-inspect-authority.test.mjs`，TC-NTR-010 六种情形各一个 subtest，确认失败；注释不写 `crctl <子命令>` 字面量
- [x] 4.3 →M 审查 RED 的断言口径与失败原因
- [x] 4.4 →B GREEN：`crctl.mjs` inspect 分支纯插入补键；金样本按真实输出增补；`gate-registry.json` 登记新文件
- [x] 4.5 →M 审查 diff（确认对 HEAD 无删改行）；变异检查（去掉 null 分支、改成抛错、把键写进默认面）使 TC-NTR-010/011 红后还原；`crctl-summary.test.mjs` 8/8
- [x] 4.6 →M 全量套件与 TC-NTR-009 回归；`stdd structure delta`；C1–C7、test-report 更新；取新 run；Gate 3 等用户确认

## 5. crctl 的 git 不经 agent shim（P0，S5，2026-11-14 并入，决策 8；Gate 1/2 重审通过后才写代码）
- [x] 5.1 →M 核实 `lib/git-shim-path.mjs` 在 HEAD 不存在；重新 grep crctl 的 spawn 点，确认 shim 目录之外没有被依赖的程序；确认 `crctl.mjs` 当前对 HEAD 仍是纯插入
- [x] 5.2 →B RED：新建 `crctl-git-shim-path.test.mjs`，TC-NTR-012 四个 subtest（识别并剥离、保留、无 shim 逐字不变、真实进程接线——仅 POSIX），确认失败；注释不写 `crctl <子命令>` 字面量
- [x] 5.3 →M 审查 RED 的断言口径与失败原因（真实进程子用例须证明记录器被调用，不能空通过）
- [x] 5.4 →B GREEN：新建 `lib/git-shim-path.mjs`（`stripGitShimDirs`）；`crctl.mjs` 纯插入一行 import 与 `main()` 第一条语句处的调用；`gate-registry.json` 登记新测试文件
- [x] 5.5 →M 审查 diff（`crctl.mjs` 对 HEAD 仍为纯插入）；变异检查（不剥离、剥离所有含 git 的目录、去掉标记判定、去掉大小上限、移除 `main()` 里的调用）使 TC-NTR-012 红后还原并 cmp
- [x] 5.6 →M 与 4.6 合并做：全量套件与 TC-NTR-009 回归；`stdd structure delta`；C1–C7、test-report 更新（如实写明 win32 接线子用例 skip）；取新 run（原 9 项 + B2 的 2 项 + 本次 1 项同一个 run）；Gate 3 等用户确认
