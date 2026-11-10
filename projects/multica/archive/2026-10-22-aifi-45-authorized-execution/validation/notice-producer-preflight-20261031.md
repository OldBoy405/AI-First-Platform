# 通知生产接线：测试安全与验收边界

## 本轮事实

子代理曾新增 `multica/server/internal/governance/execution_notice_producer.go`、`noticeproducer_test/execution_notice_producer_test.go`，并修改 `runner.go`、`runner_code.go` 和 `server/cmd/server/router.go`。独立只读审查发现阻断问题后，主会话仅撤销本轮新增接线，将两份本轮新增文件逐字节备份到 `notice-producer-draft-20261031/` 后移出生产源码；其他既有脏改未回退。**不代表 NTF-001/002 完成或真实 DB/广播通过。**

子代理在暂停消息之前运行了导入 governance 的测试二进制：两项 helper 测试旧版本 RED，随后新版本测试 4 个顶层、12 个叶子通过、0 skip；这些是带 fake sink 的 helper/构造器测试，不是数据库 producer→Inbox→广播链路。最后两处源码收紧后仅 `go build ./cmd/server` 和 `gofmt`，未重跑测试。测试前后源码及依赖哈希、测试二进制路径 unknown；原始测试输出仅在执行者工具回执，没有独立归档。

## 安全事件与未知

测试执行时没有已证明的 OS 文件或网络隔离，也没有事先审计传递依赖的 init。命令使用 `env -i`、`GOENV=off`、`GOPROXY=off`、`GOSUMDB=off`、`GOTOOLCHAIN=local`、自建 HOME/GOCACHE/TMP，并显式读取本机 Go 模块缓存 `C:\Users\GOBAO\go\pkg\mod`；但 `PATH="$PATH"` 继承了宿主 PATH，准确值未记录。依赖 init 是否访问其他文件或尝试网络、完整进程树与后代是否退出均 **unknown**；不能以代理未主动访问或离线 Go 选项推断为无访问。

执行者随后对所称自建随机路径 `/tmp/aifi45-ntf-producer-eRlpz0xE` 执行了 `rm -rf` 并报告成功；该路径排他创建、与本会话 `/tmp` 映射相同以及删除时未被替换的证明未记录，故其归属和任何潜在影响均 **unknown**。不为补证而扫描或删除未知资源。

主会话最初委派时要求审查后代真实副作用并使用最小环境，但没有明确把「未证明第三方 init 与 OS 隔离前禁止运行 Go 测试二进制」列为硬停止；追加暂停指令到达时测试已发生。后续严禁将该测试当作隔离合规证据。暂停后执行者未再运行测试二进制；`go build` 不等于执行生产包 init，也不证明依赖读取范围完全隔离。

## 独立只读审查与后续准入

复核指出：pending 广播失败后现有重复插入分支不会重播，而无生产 `RecoverPendingNotices` 调用；producer 把存在任意消费记录当作授权且未绑定当前 head、拼造 test-report 链接，可能将永久授权错误变成无界 run 卡住；无 644 表的 legacy 环境还可能报错。当前 `cmd/server/main.go` 未注入 AdmissionDecider，默认关闭 Runner，开启则在缺 decider 时 fail-closed，不能把可编译的 router 组合当作可运行生产入口。这些为源码审查结果；缺陷的真实 DB 动态边界仍须验证。复核建议使用旧 DB runner 与本工作区 HOLD 约束冲突，**不采纳、不运行**。

- 后续先解决生产链路、身份和收敛/重放；不能以 fake sink GREEN 证明生产者可达或行为正确。
- 任何新的生产测试二进制执行前，须独立审查并证明该**目标进程自身**的 token、受限句柄、文件与网络边界、子进程及精确清理；当前 AppContainer 原型的问题见 `notice-tab-isolation-20261031/ISOLATION-REVIEW.md`。
- 真实 DB、pending 恢复、收件人权威、X6 及 Gate3 均未验证；不连接历史事故库。

## 2026-11-01 独立复核后的最小实现前置

本次 strong 档只读复核 requested `GBClaude/claude-opus-5-5:high`，actual backend `unknown`，session `01a194bd-77de-7468-8217-4bf6a2e6131b`；未运行程序或数据库。以下是源码静态事实与需验证的切片，**不是生产已接线、可见通知已重复或 TC 已通过**。

1. `server/internal/governance/execution_notice.go` 的 `NoticeDedupeKey` 当前使用 CR、cause、evidenceDigest、audience；不包含 project 或具体 recipient。`DeliverNotice` 的冲突分支查到 pending 后直接返回，不触发补发；Inbox 插入未写 `details`。`RecoverPendingNotices` 扫描指定 workspace，遇首个广播错误即返回；尚未确认生产调度调用。它自己的数据库事务不能自动与调用方业务事务合并。
2. 已批准 `design.md` §5 要求 `inbox_item.details.execution_notification_key`、按 workspace / recipient / key 的 partial UNIQUE、运行通知引用与 Inbox 同事务，以及收件者变化时不同的通知身份。当前独立账本及 v1 键与此存在偏差；**不能先宣称一致，再靠客户端去重兜底**。历史兼容、旧 pending、收件者改变和迁移策略需按现有变更流程处理。
3. `LoadInboxItem` 与客户端 `hasExecutionNotificationKey` 的生产 payload 接线尚需逐字段核实：服务端没有在现有插入中写 key，因此重投能否被所有启用客户端识别为新策略不能由夹具证明。`wecom/outbound.go` 订阅 `inbox:new` 的真实外部行为也未实测；重复推送是风险而非已发生事实。
4. **候选纵切片 S1（待测试环境安全通过，不视为已完成）**：先为真实创建和加载链增加失败断言，核查 Inbox 持久 details 与广播 item 的 key、recipient、workspace、必要原有字段一致，并测试旧记录无 key 的兼容。实施必须遵守批准的实际唯一键与迁移合同；仅写一个 v1 标记不解决收件者/项目碰撞或完整设计偏离。
5. **候选纵切片 S2（依赖 S1 且需并发协议）**：模拟 after-commit pending、同一 Inbox ID 的重复恢复及已 delivered 不重播；用并发恢复、广播后标记失败、故障隔离与多个 workspace 覆盖，证明不会丢事实。服务端重复发布不等于用户已看到或去重；外部接收者不能无证假设 exactly-once。
6. **producer 仍阻塞**：须先从实际可信业务事实确定触发、授权主体和接收者，明确撤销后的身份、证据引用以及可与业务事实原子提交的通知意图。`archived` 普通投影和存在任意消费记录均不能直接替代可信终态或当前授权。无批准的权威接线不恢复此前撤下的草案。
7. 当前不得在未证明隔离的真实 NTF 测试入口上直接运行；`scripts/aifi45-db/run.mjs` 指向的历史 HOLD 资源持续禁止。先审定专用环境、运行命令和影响，留存实际非零用例的 RED/GREEN、源码身份及独立复核；测试夹具、fake sink、单层组件结果均不替代正式 TC。

requested 模型与 actual backend 回执未核实，actual `unknown`。
