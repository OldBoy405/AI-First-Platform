# 新 disposable PG Gate2 草案：独立静态审阅

> 历史审阅快照：审阅时尚未选择基线方向。后续用户已选择 A 并确认第一阶段设计与实现范围，复核亦确认原 Gate2 无已核实的 BUILD 中途重开入口；当前 B4 状态与仍待决定事项以 `new-disposable-pg-gate2-draft.md` 和 `new-disposable-pg-first-stage-confirmation.md` 为准。下文保留审阅当时的结论，不代表重新审阅或批准修订后草案。

## 结果

独立审阅认为 `new-disposable-pg-gate2-draft.md` 与现有 test-plan、`multica/scripts/aifi45-db/README.md` 和 `run.mjs` 的相关静态事实一致，可作为**待人类审议的草案**，不是 Gate2 批准、创建许可回执或数据库测试证据。审阅未访问容器、环境、会话、数据库或网络，也未运行测试。

审阅指出四项应补充：迁移前自建旧行 fixture 验证兼容、测试进程 URL 缺失必须 fail-fast、冻结 `CRCTL_PATH`、准确限定 README 对 fake-I/O 组件的描述。二次复核发现原补充把 test-plan 的历史表述误作 governance TestMain 当前行为：当前 governance TestMain 缺 URL 会失败但不验证 disposable 身份，handler/service 的 TestMain 及迁移工具才有默认连接回退。草案已原位更正并补充 daemon 的 `MULTICA_CRCTL_PATH`；独立静态复核确认更正与当前源码一致，建议的限定措辞亦已补入。

## 后续 schema 静态复核

后续独立审阅补充文件名清单、648 各阶段初态、handler public 表清单和非幂等迁移的限制；发现并更正了将 Reapply 说成独立可证明初态、将 roundtrip 注释说成运行依赖及历史 642 调用未经证实等过度表述。终核认为修订后的相关段落与所读源码一致；其仅作静态审阅，不证明源码全量快照、实际迁移或数据库结果。复核详情和清单统计范围见 `new-disposable-pg-schema-static-recheck.md`；草案已原位更新，仍不构成 Gate2 批准。

## 未决边界

- 用户已授权新建独立本地实例及清理可证明本轮归属的资源；这不等于新测试环境与入口已获 Gate2 批准。
- 旧入口绑定原实例并读取原库；历史事故库继续 HOLD，不能直接换目标或为了验证新库回读旧库。
- 新实例 schema 及 fixture 来源、权限、身份、安全清理和证据格式仍须设计并取得真实 Gate2；不能静默缩减旧 TC 或解除 Gate3 依赖。
