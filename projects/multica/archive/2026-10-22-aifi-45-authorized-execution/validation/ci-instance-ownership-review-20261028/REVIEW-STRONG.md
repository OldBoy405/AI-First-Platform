## 结论

**两份文件的 raw-byte SHA-256 均与给定值一致。** 已读取指定实施计划；本次仅做文件读取、哈希计算和静态推理，**没有修改文件，没有运行测试、数据库或容器，也没有完成或验证 CI**。

该函数已有有效的身份交叉检查，但**不足以独立承担容器操作授权或完整隔离证明**。按目前尚未接线的状态，以下问题是接线前风险，不代表已经发生越权；**本次复审不赋予它容器删除权限，也不构成真实实例探针授权**。

### SHA-256

目录：`C:/Users/GOBAO/Downloads/AI/multica/scripts/aifi45-db/`

| 文件 | 实际 SHA-256 | 比较 |
|---|---|---|
| `instance-ownership.mjs` | `ac6ffb765843813be50bac8dfce5d0fe5a2eaac231988592401e78c2faef4478` | 一致 |
| `instance-ownership.test.mjs` | `fdb71e49ac7897e4a3da98a1bee429f6af3e6097898727c5748640854d57c614` | 一致 |

已读取：`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/ci-disposable-db-implementation-plan-20261028.md`。

## 具体发现

### 1. 高：隔离条件并不完整，不能将返回成功解释为“安全容器”
位置：`instance-ownership.mjs:18–27`

现有检查明确拒绝 privileged、host 网络/命名空间、bind、device 和持久 mount 等，方向正确。但它没有约束其他可改变隔离或执行内容的字段，例如：

- `HostConfig.CapAdd`、`SecurityOpt`；
- 其他设备授权字段，如 `DeviceRequests`、`DeviceCgroupRules`；
- `Config.Entrypoint`、`Cmd`。

**静态可推导的接受案例**：在测试中的合法 fixture 上增加 `CapAdd: ['SYS_ADMIN']` 和 `SecurityOpt: ['seccomp=unconfined']`，其他字段不变，当前检查仍会接受。这里没有实际执行该案例。

这不等于已经证明容器逃逸，但说明“隔离已完整验证”的结论不成立。

**建议：** 根据固定 create argv 和指定 Podman 版本建立字段白名单；检查相关提权字段和预期命令。明确本函数的检查边界，不能把它的成功结果直接接到 stop/rm 授权。

### 2. 中：停止态请求端口校验缺项；动态端口策略尚未被证明
位置：`instance-ownership.mjs:28–40`

当 `State.Running === false` 且允许非运行态时：

- 请求 binding 只检查数量和 `HostIp`；
- `HostPort` 缺失、`null`、非法字符串、越界值均未被检查；
- `NetworkSettings.Ports` 完全不参与检查。

停止态没有实际端口是合理的，不能强行要求它具有运行态映射；但**请求配置本身仍应有效**，出现实际 wildcard/额外映射等残留信息时，也应有明确策略，而不是默认忽略。

运行态另有计划一致性缺口：请求端口只要等于实际端口就通过，因此**无法单凭此函数证明 create 使用了动态分配，而非固定端口**。Podman 也可能将动态请求规范化成已分配端口，不能未经实测就简单要求始终为 `''`。

**建议：** 两种状态都校验请求端口结构；用固定 argv/journal 证明动态分配意图，再按真实 inspect 行为校验实际映射。

**已有正确防线：** `running=false` 并不会跳过一个实际运行容器的端口检查；分支依据 `State.Running`，相应回归测试也覆盖了这一点。

### 3. 中：运行态参数不是必填契约，`Running=true` 也不等于可运行
位置：`instance-ownership.mjs:31–32`

- `running` 缺省、`null` 或其他 falsy 值都会放宽成“允许非运行态”，调用方遗漏参数不报错。
- 只检查 `State.Running`，没有区分 paused 等状态。`Running=true` 不能独自证明实例可执行数据库工作。
- `running=false` 实际表示“允许运行或非运行”，**不是“要求已经停止”**。

**建议：** 改成必填、枚举式用途/状态策略，例如运行工作、创建后核验、停止后核验；拒绝未知模式。明确允许哪些 Podman 状态，并针对 paused、异常状态和缺字段补测试。

### 4. 中：时间、nonce、image 的可信来源仍是外部前提
位置：`instance-ownership.mjs:7–17`

函数验证的是**输入彼此一致**，不是输入来源可信：

- `target.image` 没有与固定镜像策略绑定；
- 时间上下界只要求可解析、有序，没有窗口长度限制；
- nonce 格式不能证明它由本次创建过程随机生成；
- 如果 `target` 与 `inspected` 都来自不可信来源，构造一致数据即可满足检查。

此外，`Date.parse` 接受范围较宽，通常按毫秒精度处理；Podman 的更高精度 Created 时间、时区和边界语义尚未被锁定。

这属于**接线必须建立的信任边界**，不是说该纯函数应自行完成所有授权。

**建议：** `target` 只能来自本次 create 前持久化的可信意图；绑定固定引擎、固定镜像、nonce 和受限时间窗口。明确 RFC3339 时间格式、精度及容差，不能把时间窗口或标签当作删除授权凭证。

### 5. 中：测试数据隔离良好，但关键断言并非都得到独立验证
位置：`instance-ownership.test.mjs`

正面部分：

- 每个 mutation 都重新取得 fixture，未见这些案例之间共享可变 inspect 对象；
- 测试只导入被审函数，没有借用生产校验辅助函数充当 oracle。

但存在具体的“其他条件兜底”：

- **`reject malformed target ID`** 只改 `target.id`，没有同步修改 `inspected.Id`。即使删除 ID 格式检查，ID 不一致仍会使测试拒绝。
- **`reject target name not derived from nonce`** 只改 target 名称。即使删除“名称必须由 nonce 推导”的条件，inspect 名称不一致仍会使测试拒绝。

因此这些用例不能单独证明对应谓词有效，更不能替代计划要求的关键检查变异 RED 证据。

另外缺少：

- 一致但非法的 ID/image/nonce/name；
- 非法、反向及过宽时间窗口；
- 停止态请求端口缺字段或非法值；
- paused、缺省模式及新增隔离字段；
- 真实 Podman inspect 的独立 fixture。

**建议：** 为格式/推导规则构造“两边保持一致但违反该规则”的输入；让每条关键谓词有自己的反例。后续另行执行 mutation 验证，不能将当前静态阅读报告写成测试 GREEN。

### 6. 低：输入类型校验不严格，部分异常不是统一拒绝错误
位置：`instance-ownership.mjs:7–9、26、37–38`

- JS 正则 `$` 可匹配末尾换行之前的位置；ID、nonce、端口格式检查没有完全排除尾换行。
- 正则会进行类型转换，实际端口的数字类型也可能通过。
- `Env` 不是数组，或成员不是字符串时，可能在 `.filter` / `.startsWith` 处抛出 `TypeError`。

后者仍是拒绝，不是 fail-open；但错误分类不稳定。前两项对正常 Podman 输出未证明可利用，属于输入契约缺口。

**建议：** 先校验字符串/数组及成员类型，再校验完整格式；统一结构异常的拒绝方式，并补畸形 JSON 输入案例。

## 必须由真实 Podman 验证的未知

当前成功 fixture 是手工构造的，**不能证明真实 inspect 兼容性**：

1. tmpfs 是否出现在顶层 `Mounts`；若出现，当前 `Mounts.length === 0` 可能拒绝合法实例。
2. `Tmpfs` 选项是否重排、追加默认项或转换 size 表示；精确字符串比较可能误拒绝。
3. create 后、start 后、stop 后，动态端口分别表现为 `''`、`'0'`、已分配值、`null` 还是缺失。
4. 指定 Podman 版本/rootless 配置下，namespace、network mode、空数组与 `null` 的实际表示是否符合断言。
5. `Name`、image ID 和 Created 时间的实际格式与精度。
6. 回执丢失、引擎失联、stop/rm 失败及“精确 ID/名称不存在”的证明——这些生命周期能力**不在此纯函数及其当前测试中**。

应针对固定的本地 Podman 配置取得脱敏、独立的 created/running/stopped inspect 样本，再判断严格条件应保留、规范化还是调整；**不能为了让 fixture 通过而宽泛放松隔离条件**。

**最终判断：保留未接线状态。先补齐隔离与状态契约、独立反例和 inspect 兼容性证据，再按实施计划另行审查生命周期及授权边界；CI BLOCK、既有 verdict 和 Gate3 不因本次静态复审改变。**