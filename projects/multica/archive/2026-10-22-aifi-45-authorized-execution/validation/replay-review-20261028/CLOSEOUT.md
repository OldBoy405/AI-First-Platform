# 独立只读复核与作者处置

- 快照：`source-manifest.json`；原文及模型响应元数据：`REVIEW-STRONG.md`、`REVIEW-BALANCED.md`、`REVIEW-RECEIPTS.json`。两份原文 SHA 与 session 最终消息逐字节一致。作者在两位结束后、修改前复核快照所列 12 个 multica 文件及 10 个 change 文件均无漂移；这不是 balanced 自己完成的源码复核，也不是 commit 冻结。
- strong 的原结论为 **BLOCK**，balanced 为 **NOT VERIFIED / INCOMPLETE**；均不因下列作者修补升级。两位只审旧快照，后续变更需新鲜独立复核。
- strong F1：作者以两个不同事务实际等待锁跨过 key 到期构造 RED `writer-lock-expiry-red-20261028T081914Z`；首次写入现于相关锁后用服务端时钟复验，GREEN `writer-lock-expiry-green-20261028T082032Z` 33/33、skip 0。只证明指定锁等待窗口的写前校验；不证明最终提交时刻、可信 manifest 或完整路由。
- strong F2：历史 key 到期后恢复仍是开放问题；目前首次验签使用传入信任参数，且记录未保存可供独立历史认证的受保护密钥快照。不能为使重放变绿而绕过新写入认证或擅自确定已撤销 key 的历史政策。
- strong F3：`cross-lineage-conflict-red-20261028T081613Z` 的 command/verdict 两子例均实际等待同 request 的唯一索引后得到 23505；现在只对各表 request 唯一约束映射 `ErrControlStoreConflict` 并保留底层错误，`cross-lineage-conflict-green-20261028T081719Z` 10/10、skip 0。该事务已失败，调用方必须 rollback；不是“事务仍可继续”。
- balanced 指出 `replay-snapshot-gov-20261028T080158Z` 为红、后续 `replay-snapshot-gov-tools-20261028T080416Z` 因 skip 被 harness 判 unverified：原文保留。作者核实前者缺 `AIFI45_TOOLS_ROOT`，后者 0 fail/1 skip，只能作回归比较。balanced 未完成源码语义阅读，不能把作者补查当作其 PASS。其表中“manifest 未列入新增文件”与同表证据自相矛盾：manifest 实际列入且标为 untracked；原报告不改。
- 作者另按 CP 声明逐项使用独立隔离库跑原快照 `CP-RUN-003` 与 `-A…-L`：`cp-single-*-20261028T080856Z` 共 13 条均选中并通过、skip 0，原库未变、专用资源清理；随后源码已改，不能当作新快照完整验收。新测试 `-M/-N` 分别见 `cp-single-cp-run-003-{m,n}-20261028T082608Z`；随后作者在修改后源码上逐条重跑 `cp-final-cp-run-003[-a…-n]-20261028T082912Z` 15 条，均命中指定顶层测试、skip 0、原库未变且资源清理。该作者运行不替代独立复核。
- Gate3、M003 完整可信根/B/路由/producer/摘要互操作及真实部署仍未通过。原始 R4 三路评审与此轮不同，不以此覆盖其 INCOMPLETE 或 BLOCK 结论。
