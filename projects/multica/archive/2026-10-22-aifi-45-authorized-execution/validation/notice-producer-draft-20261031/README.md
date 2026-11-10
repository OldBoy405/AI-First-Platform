# 交付通知 producer 草案（隔离存档，非生产源码）

本目录保留未通过独立评审的草案，不参与 Go 构建。原草案尝试把 writeback 完成接入通知 producer；只读审查发现 pending 广播恢复、旧版迁移兼容、授权主体与消费记录绑定、证据链接、重试和真实入口等阻断问题。不能部署或据 helper 测试声称业务 TC 通过。

生产接线必须在解决上述问题、隔离安全证明和真实入口/DB 验证后重新设计；不得使用历史 HOLD DB 或 `scripts/aifi45-db/run.mjs`。本次测试隔离事件和 unknown 见 [预检记录](../notice-producer-preflight-20261031.md)。
