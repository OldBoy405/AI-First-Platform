# Current project resource read Implementation Plan

> 按 writing-plans 落最小纵切片；沿用已批准原生STDD BUILD，不新开CR/Gate、不commit/push。

**Goal:** 在既有真实DaemonAuth读接口补当前project的可绑定资源身份元数据，为后续每repo比对提供实时DB来源；不冒充完整binding/claim/新鲜度/准入证明。

**Architecture:** 保持 `/execution-authorization/head` 和历史安装语义不变。复用 `GET /api/daemon/workspaces/{workspaceId}/repos`，仅显式 `project_id=<UUID>` 时启用新读面：真实mdt身份、workspace/project同一只读repeatable-read快照，使用既有workspace-scoped资源查询和 `protocol.NewProjectResourceBinding`。旧请求/旧客户端响应不变；新响应增量 `project_id` 和 `project_resource_bindings`，不传原始resource_ref或秘密。

**Boundaries:** 已批准ADJ-AIFI45-001/M001的当前平台资源回读细化，不改变范围/预算/签名payload/人类来源/head，不新增endpoint、任意nonce代签、表或迁移。它只是本次DB快照，失联/旧服务不提供此字段不能降级为已验证；真正消费仍关闭。只读metadata不声称新task receipt或宿主隔离，不能关闭完整AUTH/RUN TC。

## 文件/所有权

- 主会话：`server/internal/handler/daemon.go` 的既有workspace repos读面/响应；`server/internal/daemon/client.go` 的增量响应和当前绑定读取方法；工具仓记录 `wire-contract.md` addendum。CUSTOM与交接由主会话统一登记。
- balanced writer：仅新增 `server/internal/governance/execution_current_resource_binding_test.go`，通过真实DB-backed mdt→DaemonAuth→公开HTTP handler验证。不得改共享fixture、产品代码、CUSTOM或运行DB。
- 后续独立balanced：冻结源码后通过版本化可丢弃库runner独占执行回归；strong安全复核不访问DB。旧claim锁序事实调查另一路balanced，不与本片写入重叠。

## 执行

- [ ] 首个公开HTTP用例：两种可绑定资源完整返回，scope来自服务端；旧码实际缺当前字段形成行为RED，不把编译错/零匹配/skip算RED。
- [ ] 最小GREEN：显式project查询只许真实mdt/非空daemon ID；同快照校验project belongs workspace，调用 `ListProjectResourcesInWorkspace`，构造支持的descriptor。支持类型的无效身份失败关闭，不回显secret；未知不支持类型不当可绑定资源。
- [ ] 客户端复用该GET，严格要求响应workspace/project及当前集合存在；旧服务忽略查询导致字段缺失必须明确失败，不用缓存/heartbeat代替。空集合与未提供字段区分。
- [ ] 逐个补边界：非coordinator身份修改/删除/reparent后的新回读、纯label不改digest、跨workspace/伪header/PAT兼容身份/无daemon ID拒绝、空project列表、无查询legacy不变；不让测试替实际后续签名/每repo准入闭环。
- [ ] 冻结源码manifest，独立静态/新库动态复核，CUSTOM/phase/tasks与原始证据归档；不勾整TC/major/Gate。

## DB与证据

仅用 `scripts/aifi45-db/run.mjs` 逐命令schema-only新库/受限role；原库/原事故证据不写，旧临时入口HOLD保持。每条原137表和82审批ID/hash比对、锁/session0、临时对象OID/marker及catalog实际不存在。82为事后现场，不是恢复原83。旧run原始证据不覆盖，失败和后续修复使用新前缀。
