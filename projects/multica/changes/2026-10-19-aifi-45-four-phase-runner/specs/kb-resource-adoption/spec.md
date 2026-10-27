# Spec: kb-resource-adoption

> Change: 2026-10-19-aifi-45-four-phase-runner | Auto-generated Human View

## Requirements

### Requirement: HTTP/WS heartbeat 共享授权身份和目录资源读取/消费合同

#### Scenario: M-SC-KB-001

- **GIVEN** 同一已授权 runtime 有 workspace、daemon_id 和项目 local_directory 资源，WS 正常时 HTTP 会被跳过
- **WHEN** 分别走 HTTP 手动 heartbeat 响应和 WS heartbeat/action 消费
- **THEN** SHALL 两传输返回并消费同一可选目录快照，WS lease 使用鉴权查询读取的 runtime daemon_id
- **AND** SHALL 不依赖 PAT 缺省 daemon ID 或客户端自报身份，不扩大撤销/机器认证承诺

#### Scenario: M-SC-KB-002

- **GIVEN** 多 workspace/daemon 的资源分属不同项目，某请求身份不匹配
- **WHEN** heartbeat 读取本 runtime 资源
- **THEN** SHALL 按已授权 workspace/daemon 及所属项目限定查询，拒绝跨项目/跨 workspace 资源
- **AND** SHALL 不列项目再逐项 N+1，不新增全量 endpoint，不因发现根扩大普通任务权限

### Requirement: 快照替换投影，区分成功空、缺字段和失败

#### Scenario: M-SC-KB-003

- **GIVEN** workspace/daemon 当前投影为旧路径，随后分别收到新路径快照和成功空快照
- **WHEN** 按顺序消费两个 heartbeat
- **THEN** SHALL 先替换为新路径再清除该 workspace/daemon 投影，不追加旧路径、不影响其他身份投影
- **AND** SHALL runtime/workspace 退出时按既有生命周期移除对应运行期投影

#### Scenario: M-SC-KB-004

- **GIVEN** 已有有效投影，本次快照字段缺失或资源查询失败，heartbeat 已领取 pending actions
- **WHEN** 处理失败响应并在后续收到成功快照
- **THEN** SHALL 失败/缺字段时保留原投影并交付已领取 actions，后续成功快照使投影收敛
- **AND** SHALL 不把读取失败伪装为空，不丢 action，也不回退环境变量根列表

#### Scenario: M-SC-KB-005

- **GIVEN** 无任务冷启动且无 MULTICA_CR_WORKSPACES，资源目录稍后出现、KB 账本稍后初始化或断网恢复
- **WHEN** daemon 启动采集/投递循环并按既有节拍收到有效 heartbeat
- **THEN** SHALL 不依赖认领任务或重启即可识别资源指向的合法 KB 并恢复采集/投递
- **AND** SHALL 首次快照失败只等待后续 heartbeat，保留既有 kb init，不递归发现未知嵌套 KB

### Requirement: 采集、执行定位、settle、投递共用资源根和请求级 workspace

#### Scenario: M-SC-KB-006

- **GIVEN** 两个 workspace 有不同 KB 根，并发执行采集、Pipeline 定位、terminal settle、pending 与 ack
- **WHEN** 使用资源投影定位根并发出请求
- **THEN** SHALL 所有消费者共用同源带 workspace 的根，按请求 X-Workspace-ID 分组且 ack IDs 不串批
- **AND** SHALL 不修改共享 client 的全局 workspace，不从任务历史/本地持久根缓存补源

#### Scenario: M-SC-KB-007

- **GIVEN** 旧环境变量含残留根，资源快照为空或路径非法/非 KB，另有未知嵌套 KB
- **WHEN** 采集器和定位器处理候选根
- **THEN** SHALL 移除 MULTICA_CR_WORKSPACES 根来源并复用路径验证/KB 识别，不恢复残留根、不递归猜未知 KB
- **AND** SHALL 不新增根账本、配置同步或新旧双模式

#### Scenario: M-SC-KB-008

- **GIVEN** 采集与 Pipeline 定位两个既有入口分别遇到 CR not found
- **WHEN** 输出现有错误/诊断信息
- **THEN** SHALL 两处均保留 workspace/CR、资源、daemon/runtime 和投影线索以区分定位失败，不以改报错代替资源接线
- **AND** SHALL 不新增运行时报告、健康检查或机器级认证
