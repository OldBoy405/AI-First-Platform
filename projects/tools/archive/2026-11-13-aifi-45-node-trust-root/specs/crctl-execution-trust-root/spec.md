# Spec: crctl-execution-trust-root

> Change: 2026-11-13-aifi-45-node-trust-root | Auto-generated Human View

## Requirements

### Requirement: 环境变量 CRCTL_EXECUTION_TRUST_ROOT 只是 --trust-root 的另一条输入通道：同一值经任一通道得到相同的信任根与相同的结果。

#### Scenario: SC-NTR-001

- **GIVEN** 一个声明 authorized-execution/v1 的 CR，其 grant 与公钥位于一个合法的信任根目录，未传 --trust-root，仅设置 CRCTL_EXECUTION_TRUST_ROOT 为该目录。
- **WHEN** 执行 crctl advance，且 binding 经现有 stdio 或 endpoint 通道取得。
- **THEN** SHALL 从该目录选择并读取 grant 与公钥，经现有 control admission 完成消费，并在该目录的 execution-consumptions 写入 receipt。
- **AND** 业务写入发生在工作区，与传同值 --trust-root 时一致。
- **AND** 输出与 receipt 不记录输入来自变量还是 flag。

#### Scenario: SC-NTR-002

- **GIVEN** 同一 fixture 与同一只读输入。
- **WHEN** 分别用 CRCTL_EXECUTION_TRUST_ROOT 与 --trust-root 执行 crctl authorization-bind --check。
- **THEN** SHALL 退出码、stdout 与 stderr 的原始字节逐字节一致，且两次都不产生文件系统副作用。

### Requirement: 变量与 flag 并存时不默默择一；变量被实际选作信任根而值不合法时拒绝，不回退到旧的 .crctl 位置。

#### Scenario: SC-NTR-003

- **GIVEN** 八个生效命令之一同时得到变量与 --trust-root。
- **WHEN** 两个值的原字符串相同，或不同。
- **THEN** SHALL 相同则通过并继续使用该值；不同则在读取工作区之前以 EXECUTION_TRUST_ROOT_INVALID 拒绝。
- **AND** 「相同」指原字符串逐字相等，不做 trim、路径归一或 realpath 比较。
- **AND** 拒绝时不产生任何业务写入或 receipt。

#### Scenario: SC-NTR-004

- **GIVEN** 变量的值为空串、纯空白、相对路径、不存在、普通文件，或位于、包含安装根（含经符号链接或 junction 解析后落入）。
- **WHEN** 命令实际消费信任根（新合同 CR 的 advance、authorization-bind、authorization-scope 等）。
- **THEN** SHALL 以 EXECUTION_TRUST_ROOT_INVALID 拒绝，错误分类与同值 --trust-root 一致，且不回退到 <安装根>/.crctl。
- **AND** legacy CR 的 advance、参数不完整的 repair-resume 等不消费信任根的分支，与同值 --trust-root 一样忽略该值，不新增 admission 或文件访问。

### Requirement: 变量只对当前实际消费信任根的八个命令生效，其余命令与未设置时完全一致。

#### Scenario: SC-NTR-005

- **GIVEN** 对 kb、workspace、business、writeback-apply、planning-entry、competitive-report、git、repair-assess、repair-outcome 的调用，变量被设为任意值（含非法值）。
- **WHEN** 执行这些命令。
- **THEN** SHALL 结果与未设置变量时一致，不新增 flag、白名单错误或 git 参数。
- **AND** 变量未设置时，现有的 trust-root 相关测试全部不变地通过。

#### Scenario: SC-NTR-006

- **GIVEN** 变量指向合法信任根，对 authorization-scope、sensitive-action、repair-admit、完整的 repair-resume、register、archive 的调用。
- **WHEN** 分别执行这些命令。
- **THEN** SHALL 与传同值 --trust-root 的行为一致：首次写入进入现有 control admission，缺少必需授权输入时失败关闭；authorization-scope 仍只读，不进入 control admission，不写 receipt。

### Requirement: 变量不新增 agent 能力，也不构成授权或隔离证明；本地准入不等于平台授权。

#### Scenario: SC-NTR-007

- **GIVEN** agent 自备的目录、自生成密钥、自签 grant 与本地 endpoint。
- **WHEN** 分别经变量与 --trust-root 选择该目录并准入。
- **THEN** SHALL 两个通道的退出码、错误码与稳定结果一致，变量不比 flag 更宽松或更严格。
- **AND** 缺 key、签名无效或 binding 不匹配时，两个通道都按现有规则拒绝。
- **AND** 测试与文档不得把本地准入成功表述为平台授权证明。

#### Scenario: SC-NTR-008

- **GIVEN** 新合同 CR，<安装根>/.crctl 下没有 execution-grant，既未设置变量也未传 --trust-root。
- **WHEN** 执行 crctl advance。
- **THEN** SHALL 以现有的 EXECUTION_CONSUMPTION_REQUIRED 拒绝，不写业务状态，也不写 daemon 信任根下的 receipt。

### Requirement: workspace inspect --detail 提供 daemon 启动节点前核对 authority 所需的两个事实键 targetSpecId 与 targetVersion；只增键，既有输出与默认面不变；只读，只复用既有读取器。（2026-11-14 并入）

#### Scenario: SC-NTR-009

- **GIVEN** 一个 CR 工作区：(a) cr.md 与 _backlog.yml 的 target-spec-id 一致且有效，cr.md 的 target-version 为有效版本值；(b) 两侧都没有 target-spec-id（legacy）；(c) 只有一侧有 target-spec-id；(d) 两侧值不一致；(e) cr.md 没有 target-version；(f) cr.md 的 target-version 为 unassigned。
- **WHEN** 分别执行 workspace inspect <CR> --detail。
- **THEN** SHALL 对 (a) 输出非空的 targetSpecId 与 targetVersion，值等于既有读取器 resolveTargetSpecMode 与 readCrMdTargetVersion 的结果；(b)(c)(d) 的 targetSpecId 为 null；(e) 的 targetVersion 为 null；(f) 的 targetVersion 为字符串 unassigned（原值逐字透传）；所有情形命令 SHALL 仍以既有方式成功退出，不新增错误码。
- **AND** 只读：不写 cr.md、_backlog.yml、事务工作区、journal 或审计记录；不改变 operationalWorkspace 与 freshness 的取值。
- **AND** 不在 inspect 里判断版本值是否有效或 spec id 是否 drift；该判断仍由调用方（multica daemon）以其既有错误码做出。

#### Scenario: SC-NTR-010

- **GIVEN** 同一夹具工作区，分别以 --detail 与默认（summary）面执行 workspace inspect。
- **WHEN** 比对改动前后的输出。
- **THEN** SHALL 除新增 targetSpecId 与 targetVersion 外，detail 面的既有键、类型与值与改动前一致；默认面的键集不变且不含新增两键；crctl-detail 金样本的字段集合、稳定值与易变形态三层比对在金样本同步增补这两个路径后继续通过。

### Requirement: crctl 自己 spawn 的 git 不经 agent 的 controlled-shell git shim；只改 crctl 自己进程的 PATH，agent 直接调用的 git 与 crctl 自己的 git 白名单不变。（2026-11-14 并入）

#### Scenario: SC-NTR-011

- **GIVEN** PATH 依次包含：(a) 放有 shim 的目录——其 git 或 git.cmd 是小于 4096 字节的文件且内容含 gitguard-exec；(b) 其他目录，其中有的 git 文件不含该标记、有的 git 文件不小于 4096 字节（即使含标记）、有的没有 git、有的不存在；另一种情形 (c)：PATH 中没有任何 shim 目录。
- **WHEN** crctl 启动，在任何 git 被调用之前。
- **THEN** SHALL 把 (a) 类目录从 crctl 进程的 PATH 中移除，(b) 类目录保留，所有保留目录的相对顺序不变；(c) 情形 PATH 字符串逐字不变；因此 crctl 自己 spawn 的 git 不会解析到 shim。
- **AND** 不新增或删除 PATH 之外的环境变量，不新增 flag、错误码或输出字段；crctl 的 controlledGit 白名单、调用者名与命令面不变。
- **AND** 只改变 crctl 进程自己的 PATH；agent 直接调用的 git、shim 与 rules.json 不变。
- **AND** 无法读取某个 PATH 目录或其 git 文件时按「不是 shim」处理并保留该目录，不报错。
