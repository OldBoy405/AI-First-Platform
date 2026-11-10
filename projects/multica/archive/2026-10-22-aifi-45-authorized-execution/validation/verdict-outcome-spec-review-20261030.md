# 可信 verdict 两侧 SPEC 草案：安全审阅与阻塞

> 本文记录用户采纳四条建议**之前**的审阅快照；其后两侧草案已按 `verdict-authority-acceptance-20261030.md` 修订，下方 SHA 不再代表当前文件。该方向确认不等于 Gate2。

## 结论

用户原话“确认采用 thorough，全自动长程模式”。两侧原生状态均为 `SPEC / thorough`，Gate1 confirmed，Gate2/3 pending。长程是用户表达的 Gate2 后意向，不代替 Gate2，也不解除旧数据库及容器 HOLD、真实操作审批或原 AIFI-45 验收。

两侧均已有 `design.md`、`canonical/specs/code/2026-10-29-trusted-verdict-outcome-binding.yaml`、`specs/verdict-channel/spec.md` 和 `test-plan.md` **草案**。仍有关键事实、共享方案和 agent-spec 未定；**Gate2 BLOCK，不是可批准的完整实施规格**。

| 侧 | REQ | Scenario | TC 草案 | 置信度（高/中/低） | 其他 |
|---|---:|---:|---:|---|---|
| multica | 6 | 19 | 19 | 1/16/2 | agent-spec 仍是 TODO |
| tools | 5 | 15 | 15 | 1/12/2 | agent-spec 仍是 TODO |

TC 均为计划，未运行；跨语言同一执行拟由 M 侧唯一计数，T 引用，归属待用户或有权人确认。静态检查以严格重复键 YAML 解析，核 Scenario/TC/生成 Human View 的 ID 对应、唯一性与 SHALL；该检查不证明安全或业务运行。两侧 `stdd validate` 均 exit 0、`stdd canon verify` 均 2/2；前者未识别 agent-spec 的 TODO，后者只报告工具实际检查的源哈希和字段引用，均**不能**作为 Gate2、语义完整或测试通过的证明。生成的 spec Human View 不展示 canonical 的 confidence/evidence 和文件头草案标记；审阅须同时看 canonical 和 design 状态。

## 独立审阅与处理

- thorough 设计按每个 change 一个 planner 请求 `GBClaude/claude-opus-5-5:high`；multica `01a18b6c-b66e-7020-aecc-d4cbbef725c9`，tools `01a18b6c-b67e-7020-aecc-d4cd356aa107`。没有 backend 回执，actual unknown。两者只读调查，未执行程序。
- 独立安全 reviewer 请求同一 strong/high，会话 `01a18b79-e38c-7020-aecc-d4cf98737e9a`，只读审阅及定向复核。最初指出 dispatch/后续 effect 循环、no_effect 与 unknown 混淆、不同写入口的权威对象混用、scope 及覆盖归属不明等问题。协调者核对源码并修订后，reviewer 最后一轮对所复核的范围标注、状态机区分、回滚追溯、跨仓计数文字判为 **RESOLVED-FOR-DRAFT**，同时保持 Gate2 BLOCK。
- reviewer 没有独立核算下列最终文件哈希；以下是协调者计算的当前 raw SHA-256，不冒称 reviewer 已签核此字节快照。最后一次复核后，M canonical 仅在两处 evidence 增加了 SC-VM-018 的引用；Human View 不渲染 evidence。
- 未执行任何业务测试、数据库、旧 runner、容器内探针或真实签发；静态证据不证明生产可达性或旧数据状态。

## 未决：Gate2 前必须有权威事实或明确人类决策

1. **信任与证明：** 实际裁决/效果的权威来源、生产签发者/私钥控制者、manifest 的可信来源和固定方式、key 撤销/轮换事件及可信签发时间。只需角色和机制，不要求用户发送密钥、密码或环境变量。
2. **合同：** 先验证既有签名合同能否满足结果、冻结命令、权威主体、request/lineage/generation 绑定；再由双方选择维持既有合同、经批准的兼容证明或新版本等方案。结果闭集、精确原像/digest、未知字段处理、兼容与 key 事件语义未决，不预设 v2。
3. **结算及真实效果：** 按 effect 类型核可达写入者及权威对象；`request_id=task_id` 的生产路径需证据。认证的 no_effect 如何证明没有发生效果、slot 释放条件和远端 push 回执来源均待定。unknown/无证据不释放 slot、不凭 caller kind 支持新增 effect。
4. **scope 与发布：** 用户或有权人确认各写入路径与测试分别归本 change、AIFI-45 或另立变更；共享跨语言执行拟 M 唯一计数。真实存量和部署状态未知；回滚到可能凭 caller kind 放行的路径需经批准的前滚或部署防降级机制，不能假设旧环境为空或自动安全回滚。
5. **产物：** 待上述合同和可执行测试接口决策后，补齐两侧 `canonical/specs/agent/` 的 CP、实际测试命令与断言，重新进行静态/独立审阅，再向用户完整展示 Gate2；确认之前不得进入 BUILD。

## 当时草案 raw SHA-256（历史快照）

以下路径均相对于各侧 `projects/{side}/changes/2026-10-29-trusted-verdict-outcome-binding/`。

| 侧 / 文件 | SHA-256 |
|---|---|
| M `design.md` | `704242fda7c00de62060ae028c898aa0a72f84e81fa3a8dc33444a6cba701336` |
| M `canonical/specs/code/2026-10-29-trusted-verdict-outcome-binding.yaml` | `37df302cd566b62f8b4dbec8b06d205d801d2704090e0de57712fa847bffd896` |
| M `canonical/specs/agent/2026-10-29-trusted-verdict-outcome-binding.yaml` | `fbdf34fbd72798ca7c7feef2f0fa032b895a3c33261d41e433b9258c9785f8b5` |
| M `test-plan.md` | `bbec73b793bd59dbf2894a9b6b947d1e059c93f002a8ad65136fc5ec18e49b06` |
| M `specs/verdict-channel/spec.md` | `27cb4ec3b979b8198f9f46cd7983814ff3ea1f5083dd9b95df58418016cc9c12` |
| T `design.md` | `1516bb89cce6ea75000c3292efc1e697a292b31a40b3564973ebe546e5bcf942` |
| T `canonical/specs/code/2026-10-29-trusted-verdict-outcome-binding.yaml` | `e66bf6684d4addee4e6a7cbef2ad8a919ef8ac5e12ee17d25774c6bb0599d78e` |
| T `canonical/specs/agent/2026-10-29-trusted-verdict-outcome-binding.yaml` | `6579d6790b088a5bc7b80db2bbb02167f1c82bcce21494f0110dc6f86015972f` |
| T `test-plan.md` | `3f44ae109a4aad7ff44394f0f4edbf9a189d88d0d42724622dc219b686be7cd2` |
| T `specs/verdict-channel/spec.md` | `5e0530f6428a2d26ca4b545040ce26ec0d5b54ced8d743d7ea93f3482633a7b3` |
