# AIFI-45 继续实施：模型分层与并行

用户要求独立工作尽可能并行，并遵循 LLM 分层。对 `projects/multica` 和 `projects/tools` 分别执行 `stdd config models --format json`，均 exit 0、`schema_version=1`、`kind=configured`，两者一致：

| 档位 | 配置 model | effort | 来源 |
|---|---|---|---|
| strong | `GBClaude/claude-opus-5-5` | `high` | user |
| balanced | `OpenAIPersonal/gpt-6.1-terra` | `high` | user |
| economy | `step/step-5-preview` | `max` | user |

`design` 和 `retry` 指向 strong，来源 builtin；`review.agents` 没有显式配置。主会话的 model/effort 在 `PI_*` 中未取得，不能假设命中同档跳过。后续必要委派以配置的非空 model/effort 为 requested 值，保留 session、harness 和实际后端回执（没有则记 unknown），不为凑齐三档重复工作。

独立源码工作和只读审查可以并行；相同文件保持单 writer，使用共享数据库或真实容器的操作必须单执行者。Gate3 与人为审批不由委派自动通过。此前已发起或完成的 `gpt-6.1-sol`/默认模型复审保留其真实 requested 模型与结论，不伪称为上述当前档位；如需按当前分层补评，仅对所需内容发起，不覆盖原报告。

## 本轮限定验证

- 修订通知缺广播依赖、payload 身份和恢复 UUID 规范化；strong 静态复核及 balanced 独立复跑的分开快照与回执见 `notice-broadcast-review-20261028/`。真实 DB 恢复和实际送达未验收。
- Node→Go 动态双帧签名与 writer 验签前置探针独立复核，见 `crosslang-protocol-review-20261028/`；假事务不证明真实 DB cursor 或可信生产链。
- multica `server` 在清除 `DATABASE_URL`/`PG*` 且 `GOPROXY=off` 下 `go build ./...` 退出 0；`go test -c ./internal/governance` 退出 0，编译到专有临时目录并删除；`go vet` 对 governance、crosslang_test 和 noticeguard_test 退出 0；这些步骤**没有运行测试二进制或访问数据库**。
- tools store 的最新有限故障测试及独立复核在 tools 项目对应 `validation/frame-recovery-freeze-20261028/`；不证明断电持久化。
- 旧通知去重附表偏离规范，当前在 `ntf-x6-canonical-convergence-20261028.md` 设计收敛，真实授权来源、旧数据处置和上线保护仍 BLOCK。
- supervisor 完整缓冲解码仍是未接线草稿；五文件作者 Node 测试 186/186，balanced 对最新 decoder 测试 24/24，均不证明来源认证或运行期输出界限。Windows Job 自包含探针经运行安全审查后，协调会话与 balanced 独立运行各 1/1、skip 0；只观察自有子进程继承与自然退出，未验证 kill-on-close 或对抗性清理。证据分别见 `ci-supervisor-protocol-review-20261028/` 和 `ci-windows-job-probe-review-20261028/`；独立实例与真实容器操作仍 BLOCK。

- RUN-006/007 源码侧核查见 `run006-007-source-analysis-strong-20261028.md`；其中 ACTIVE 未过期的新操作被提前拒绝，已在 `execution_deployment.go` 做 guard 顺序最小修复，作者 fake-Tx 55 项 GREEN 并完成反向 mutation，strong 独立复跑 3 顶层/55 子项 PASS、skip 0（`active-admission-guard-review-20261028/`）。仅验证局部分支；真实签名、锁竞态、未知操作与 RUN-006 尚未验收。code 阶段真实生产入口、按代次关联、额度账本、resume 可信事实及 daemon worker 的接线仍缺。
- `decisions-pending-20261025T153000Z.md` D9 补记 EVD-008 偏差的范围、未登记承接方与审批边界，不代表 TC 通过或已创建后续 change。

**业务 TC 仍 44/49，TC-RUN-003 仍 MISSING，Gate3 NO-GO。**
