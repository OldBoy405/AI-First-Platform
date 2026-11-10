# 签发上限与 append-only 增长边界（AIFI-45 / binding-issue 纵片补正）

前缀 `binding-issue-20261025T081500Z-issuelimit-`。用户已要求连续推进、非必要不请示。

## 缺陷（作者自己的设计遗漏）

`cr_execution_binding_issue` 是 **append-only 台账**：触发器拒绝 `UPDATE`/`DELETE`，也没有回收路径。签发端点在补正前对“同一 head 的**不同** challenge”没有任何上限 —— 真实的 daemon 每次都用新的 64hex challenge，所以只要循环请求就能让该表无限增长（且永远无法清理）。这是一个真实的资源耗损面，不是理论洁癖：唯一的成本是 mdt_ 凭据 + 一次 HTTP。

## 修法（最小、不削弱幂等）

- 新增 `executionBindingIssuanceLimit = 256`，按 `(workspace_id, cr_id, grant_digest)` 统计**新**证明数量。
- handler 顺序刻意保持：**先**查同 challenge 是否已签发（命中即返回原 envelope、`changed=false`），**再**判上限；达上限后新 challenge 返回 **429 `EXECUTION_BINDING_LIMIT_REACHED`** 且不插入。
  - 这样重放永远可用（恢复/重试语义不被上限打断），被限制的只有“不断制造新证明”。
- 限额是**资源边界，不是授权额度**：它不改变 head/claim/challenge 任何校验，超过上限不会让任何请求获得更强或更弱的授权事实。

## 为什么是 256

一个 head 下的真实一条 run 只需要个位数证明（一次正常签发 + 偶发重试/重放）。256 留了两个数量级的余量，同时把单 head 的表增长钉死在可预算范围。数值是常量而非配置：本 change 明确拒绝为此新增 env/global 开关（同上位合同对 manifest 的要求）。

## 证据（本片跑完后填）

- 作者：`…-issuelimit-green2` 4RUN/4PASS（3 leaf）；加锁后 `…-issuelimit-green3` 25RUN/25PASS（22 leaf，含完整 binding 矩阵）。
- **strong 两轮复核的重要修正**：第一轮指出 count→INSERT 在 RR 下不是硬上限（A1/P2）；加 advisory lock 后第二轮仍判 **OPEN** —— 因为事务的 RR 快照在取锁**之前**就已建立，等待锁期间不会刷新计数，两个已快照 255 的事务仍能先后提交到 257。
- 因此本片**不声称硬上限**：真实边界是 `256 + 并发签发者数`。它把“无上限增长”变成“有界增长”（原本要解决的问题），但精确上限需要 `SERIALIZABLE + 重试` 或“专用连接上的 session 级锁跨两个事务”，**两者都未实现**（已写入代码注释）。
- 非作者独立回归与 strong 复核：见同前缀 `…-finalN-independent-report.md`、`…-strong-resume*.md`。

## 仍未关闭

本补正**不**触碰消费/准入/activation/隔离域：`EXECUTION_CONSUMPTION_REQUIRED` 仍然拒绝，T 侧 receipt 未写，daemon 仍不启动 strict 任务的 agent。旁证：同目录 `trust-root-20261025T084600Z-report.md` 实测「同 UID 可替换公钥、容器只读 bind 可挡住」，说明隔离执行域是消费的必要条件，而把 agent 真正跑进容器属于**执行模型变更**，需单独设计决策，不属本片。
