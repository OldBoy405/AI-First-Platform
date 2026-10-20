# Spec: public-key-grant-delivery

> Change: 2026-10-19-aifi-45-four-phase-runner | Auto-generated Human View

## Requirements

### Requirement: 当前签发公钥和 grant 在同一可信投递通道就绪

#### Scenario: M-SC-KEY-001

- **GIVEN** 新 KB 无当前 key，可信服务端 pending 中有签名 grant 和对应 public_key
- **WHEN** daemon 通过所属 workspace 的唯一目标根投递
- **THEN** SHALL 复用 PublicKeyPEM() 输出 key_id/pem，先使对应公钥就绪，再完整落盘 grant，最后将 ID 加入 ack
- **AND** SHALL 不要求人工拷当前 key，不改变 crctl 验签算法或增加验钥命令

#### Scenario: M-SC-KEY-002

- **GIVEN** 分别使用有效远程 TLS、允许的本地回环和不可信远程明文连接
- **WHEN** 首次安装公钥并验证 grant
- **THEN** SHALL 只沿已有可信连接边界安装，不将不可信响应中的 key 和 grant 当作彼此自证
- **AND** SHALL 保留来源、workspace、签名及证据验证

### Requirement: 唯一目标与完整文件是加入 ack 的前置

#### Scenario: M-SC-KEY-003

- **GIVEN** 所属 workspace 下 CR 定位分别为唯一、零匹配、多匹配，其他 workspace 恰有同号 CR
- **WHEN** deliverGrants 选择目标 KB
- **THEN** SHALL 只向本 workspace 唯一可信目标投递，零/多匹配保持 pending，不广播全部根、不以任意根成功代替目标成功
- **AND** SHALL 不把其他 workspace 的同号 CR 当目标

#### Scenario: M-SC-KEY-004

- **GIVEN** key 内容冲突、对应 key 缺失、key/grant 写失败或进程在两次写入之间中断的故障夹具
- **WHEN** 执行投递并按原 pending 重投
- **THEN** SHALL 失败不加入 ack、不暴露半份文件，保留 pending 并允许幂等重投
- **AND** SHALL 不覆盖已有 key，只有 key 与完整 grant 均就绪才 ack

### Requirement: 保留旧信任锚且不把范围扩大为完整历史密钥系统

#### Scenario: M-SC-KEY-005

- **GIVEN** 旧 grant 分别已有对应可信旧 key 或缺旧 key，pending 同时只带当前签发 key
- **WHEN** daemon 消费旧 grant
- **THEN** SHALL 有可信旧 key 时沿原验签消费，缺旧 key 时保持 pending 并留待受控恢复，不用当前 key 冒充旧 key
- **AND** SHALL 保留旧 key，不承诺完整轮换或多 daemon 副本协议

#### Scenario: M-SC-KEY-006

- **GIVEN** 临时 KB 使用 crctl 默认 .crctl/.gitignore 的 *，另有平台例外 !keys/** 与已跟踪信任锚夹具
- **WHEN** 在未来隔离演练中安装 key/grant 并核对忽略例外的最小收敛
- **THEN** SHALL 运行时 key/grant 不制造工作区 dirty，不删除已跟踪信任锚、不覆盖 key、不要求每 KB 新增配置
- **AND** SHALL 本次仅设计一次性例外处理，不修改真实 KB 或配置
