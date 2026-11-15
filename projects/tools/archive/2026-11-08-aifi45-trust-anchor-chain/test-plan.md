# AIFI-45 控制准入信任锚链 测试方案与详细案例

> 版本：SPEC v1（Gate 2 前草稿）
> 创建日期：2026-11-08
> 对应 Phase 2 Spec：`specs/execution-authorization/spec.md`、`specs/repair-governance/spec.md`、`specs/evidence-delivery-contract/spec.md`
> 行为源：`canonical/specs/code/`；检查动作源：`canonical/specs/agent/`。
> 当前状态统一为**待实现 / 未运行**；本阶段没有创建测试文件，也没有任何业务 TC、ADJ 或部署通过结论。

## 一、测试策略

### 1.1 测试金字塔

- **行为集成测试为主**：10 个 TC 都通过真实公开 crctl、临时 Git/workspace、签名材料和故障夹具验证入口行为与零副作用，而不是只测私有 helper。
- **跨端真实链为必要闭环**：M 的真实认证 route、一次性 DB、当前 claim/head、daemon 安装与中继必须覆盖 ADJ-001/002；T 单仓 fixture 不能替代。
- **部署身份验证为独立底层证据**：每个拟启用 Linux/Windows 平台均用真实 agent 身份执行公钥覆盖，采集内核拒绝与 digest 不变证据。该层不是 Node 权限位断言。
- 单元断言只用于严格 JSON、原 bytes digest、json-pointer、operation 白名单和 dev/ino 等窄边界；它们可以解释失败，但不能单独登记完整 TC 或 ADJ 通过。

### 1.2 测试原则

- SC 与 TC 一一对应；每个 SC 的 THEN 与全部 AND 都在同一顶层 TC 中断言。CP action 用 `^TC-TAC-NNN$` 精确选中一个测试，并同时要求 `ok 1 - ...`、`# fail 0`、`# skipped 0`、`# todo 0`。
- 先构造真实失败再实现；匹配 0 条、只打印测试名、超时、skip、todo、仅组件子断言或 `exit=0` 但无成功行均不是 PASS。
- 正例同时检查业务结果与证据链；负例在调用前后比较 CR/Git HEAD/index/worktree、registry、repair ledger、授权 receipt、任务数、stop/progress_epoch、journal 与 trust root digest，不能只断言非零退出。
- 签名 payload 和 structured-human-request 原 bytes 不做 CRLF 归一化或重序列化；测试文本读取的 CRLF→LF 规则不得污染这两类输入。
- 跨 project 负例使用同一真实签名服务/同一 key，确保拒绝原因是归属与根绑定而非“未知 key”。复制负例覆盖单证明与整套 key/grant/source 材料。
- 普通读与已提交 journal/receipt 恢复单独回归；首次业务写入与幂等恢复不得混为一个入口语义。
- 测试只使用临时仓库、一次性平台资源、测试身份和测试密钥。真实 CR、共享 DB、生产 trust root 与部署启用不在本地测试授权内。
- P0/P1 均须在 Gate 3 前完成；真实部署证据缺失时必须保持未验证，不能用 skip 换取绿色汇总。

### 1.3 已有测试资产

以下路径相对 T 仓；SPEC 阶段未重跑或重新统计旧用例数，旧报告数量不转写为本 change 的通过证据。

| 测试文件 | 用例数 | 类型 | 覆盖范围 |
|----------|--------|------|----------|
| `skills/shared/crctl/scripts/test/execution-authorization.test.mjs` | 本阶段未统计 | 单元/CLI集成 | 现有 grant、来源、验签与授权边界回归 |
| `skills/shared/crctl/scripts/test/execution-binding-endpoint.test.mjs` | 本阶段未统计 | 集成 | 现有 binding endpoint 与 challenge 边界 |
| `skills/shared/crctl/scripts/test/execution-control-*.test.mjs` | 本阶段未统计 | 集成 | 当前控制协议、恢复、store 与 worker 回归 |
| `skills/shared/crctl/scripts/test/repair-governance.test.mjs` | 本阶段未统计 | CLI/Git集成 | 既有额度、origin、幂等、停止与恢复 |
| `skills/shared/crctl/scripts/test/{register-tx,register-entry-idempotent,archive-tx}.test.mjs` | 本阶段未统计 | CLI/Git集成 | 既有注册、归档事务与重放恢复 |
| `skills/shared/crctl/scripts/test/delivery-contract.test.mjs` | 本阶段未统计 | 合同/CLI集成 | 既有交付合同与证据语义 |
| **拟新增** `skills/shared/crctl/scripts/test/trust-anchor-chain.test.mjs` | 6（BUILD创建） | 行为集成 | TC-TAC-001～006 |
| **拟新增** `skills/shared/crctl/scripts/test/repair-trust-anchor-chain.test.mjs` | 2（BUILD创建） | 行为集成 | TC-TAC-007～008 |
| **拟新增** `skills/shared/crctl/scripts/test/delivery-trust-anchor-chain.test.mjs` | 2（BUILD创建） | 行为集成 | TC-TAC-009～010 |

## 二、详细测试案例

每行完整给出 Arrange/Act/Assert。操作列中的“真实链”指一次性 M 服务/DB＋认证 daemon＋T 公开 CLI，而不是 fixture signer 自回环。

### 功能 1：execution-authorization / REQ-TAC-001

| ID | SC | 优先级 | 场景 | 操作 | 断言 |
|---|---|---|---|---|---|
| TC-TAC-001 | SC-TAC-001 | P0 | 当前 project、真实来源、受保护 key、当前 claim/head 与实际根全部一致 | 通过真实人类请求签发，daemon 安装并分别启动 authorization-bind 非只读与 advance | 三项校验均在既有事务前完成；平台独立生成来源事件/digest/bindings；env 仅定位；原 bytes 未变；仅业务 gate 通过才继续 |
| TC-TAC-002 | SC-TAC-002 | P0 | 同签名 key 的 project A/B 证明互换，并把整套材料复制到另一安装根 | 对 A 逐项替换 B 的有效证明与材料，再请求两个首次写入口 | 全部因 scope/claim/root dev/ino 拒绝；签名有效也不放行；CR、Git、receipt、task 与 trust root 前后不变 |
| TC-TAC-003 | SC-TAC-003 | P0 | 仅有 env、可编辑 sidecar、伪造/替换 endpoint、自报路径/路径 pin，或缺 key、未知 key、trustRoot 位于/包含安装根 | 表驱动请求 authorization-bind 非只读与 advance，逐项伪造或替换 env、sidecar、endpoint 与路径 | 每项真实控制准入均失败关闭且无业务副作用；endpoint 即使指向可响应服务也不得仅凭响应放行，结果仍只由签名与归属合同判定；不回退本地静态验签；输出不得把 installDirectory 检查称为身份隔离证明 |
| TC-TAC-004 | SC-TAC-004 | P0 | 平台已签发结构化来源，随后 accepted_rules 原 bytes 改一个字符但 grant/签名不变；另有机器凭据/错误 actor 与跨 DB project 归属两组签发负例 | 先验证真实平台签发前独立提取、来源结构与错误映射拒签，再分别注入机器凭据/错误 actor、跨 DB project 归属，最后经 daemon 投递篡改来源并请求真实控制准入 | digest/结构/json-pointer 不符被拒绝；两组 actor/DB 负例各自均拒签，DB 无新增签发记录且 CR、Git、授权消费、平台任务零变化；篡改准入的 CR、Git、消费、任务零变化；payload 与合法来源 bytes 未被重序列化；缺真实 M route/DB 证据时仅登记条款级，不记整条通过且新合同失败关闭 |
| TC-TAC-005 | SC-TAC-005 | P0 | Linux 不同 UID、Windows 不同 daemon/agent 身份下的真实公钥覆盖 | 每个拟启用平台以 agent 身份执行覆盖、替换、追加，再读取公钥并请求准入 | 每次写由内核返回 EACCES/EPERM 或 Access Denied；前后 SHA-256 相同；身份确实不同；缺任一拟启用平台的真实内核证据时仅登记条款级，不记整条通过且不得启用；同 UID mode/pin 不计证据 |
| TC-TAC-006 | SC-TAC-006 | P1 | 错 scope、旧 policy/template/tools、旧 head、撤销、平台失联，与普通读及已提交恢复并存 | 分别请求首次写、status/next/gate 等读、check/check-source 和 journal/receipt 重放 | 不适用首次写均零副作用；普通读无新增 trustRoot/daemon 要求；check 保持 bound=false；恢复不重复准入或消费 |

### 功能 2：repair-governance / REQ-TAC-002

| ID | SC | 优先级 | 场景 | 操作 | 断言 |
|---|---|---|---|---|---|
| TC-TAC-007 | SC-TAC-007 | P0 | 有效当前证明下 repair-admit 与 repair-resume 满足原 origin、独立评估、额度和停止条件；另有已提交重放与提交边界崩溃恢复 | 经真实 daemon 请求准入、恢复及同操作重放，分别在提交前后注入崩溃并恢复；操作前后枚举安装根与账本目录 | 先过共用信任缝再走原业务裁决；无第二信任/凭据账、预算或历史账，安装根与账本目录无新增信任/凭据账文件，信任事实只来自既有 grant/keys；origin、消耗、streak、stop 保留；恢复不跳过预算；已提交重放返回原 repair_id/receipt 且不重新消费；崩溃恢复按已提交事实恢复，未提交写入回滚 |
| TC-TAC-008 | SC-TAC-008 | P0 | 尚未提交的新 repair/resume 业务写入使用缺失、跨 project、跨根复制、改一字来源、坏 key、错 scope、旧 head 或撤销证明 | 仅对尚未提交的新业务写入逐项执行 repair-admit 与 repair-resume 负例和模糊继续回退尝试，不把已提交重放列为拒绝分支 | 全部拒绝；无 repair receipt、消耗、任务、stop/progress_epoch 或 Git/write-set 变化；旧历史保持；无本地验签/口令降级 |

### 功能 3：evidence-delivery-contract / REQ-TAC-003

| ID | SC | 优先级 | 场景 | 操作 | 断言 |
|---|---|---|---|---|---|
| TC-TAC-009 | SC-TAC-009 | P0 | 平台预分配 CR/claim 与 registration key、本地候选 CR、project/root 一致；归档证明也当前有效 | 经真实 daemon 请求 register、archive 及各自已提交重放 | 首写前完成同一准入；时序事实不足时 register 拒绝；沿用原事务/journal；重放不重复准入，不产生第二条交付事实 |
| TC-TAC-010 | SC-TAC-010 | P0 | register/archive 使用缺失、跨 project、跨根复制、改一字来源、坏 key、错 scope、旧 head 或撤销证明 | 逐项请求首次 register/archive，并补同名 CR/图路径/env/sidecar 混淆样本 | 全部拒绝；不占 registration key，不建 CR/worktree/registry，不写 archive journal/交付记录/Git/index/task；他 project 签名不授予归属 |

## 三、真实验证方式与证据要求

### 3.1 CP 执行方式

BUILD 创建测试后，从 T 仓逐条执行 agent YAML 的 10 个 action。每条必须保存完整 TAP、exit code、实际选中数和测试文件 SHA-256；测试内部还须输出业务前后快照差异。三个拟新增文件的全量运行与现有相关回归只能作为额外回归，不替代逐 TC CP。

| TC-ID | CP-ID | 测试文件（均相对 T 仓） |
|---|---|---|
| TC-TAC-001 | CP-TAC-001 | `skills/shared/crctl/scripts/test/trust-anchor-chain.test.mjs` |
| TC-TAC-002 | CP-TAC-002 | `skills/shared/crctl/scripts/test/trust-anchor-chain.test.mjs` |
| TC-TAC-003 | CP-TAC-003 | `skills/shared/crctl/scripts/test/trust-anchor-chain.test.mjs` |
| TC-TAC-004 | CP-TAC-004 | `skills/shared/crctl/scripts/test/trust-anchor-chain.test.mjs` |
| TC-TAC-005 | CP-TAC-005 | `skills/shared/crctl/scripts/test/trust-anchor-chain.test.mjs` |
| TC-TAC-006 | CP-TAC-006 | `skills/shared/crctl/scripts/test/trust-anchor-chain.test.mjs` |
| TC-TAC-007 | CP-TAC-007 | `skills/shared/crctl/scripts/test/repair-trust-anchor-chain.test.mjs` |
| TC-TAC-008 | CP-TAC-008 | `skills/shared/crctl/scripts/test/repair-trust-anchor-chain.test.mjs` |
| TC-TAC-009 | CP-TAC-009 | `skills/shared/crctl/scripts/test/delivery-trust-anchor-chain.test.mjs` |
| TC-TAC-010 | CP-TAC-010 | `skills/shared/crctl/scripts/test/delivery-trust-anchor-chain.test.mjs` |

真实 M 闭环使用一次性 PostgreSQL、仓内既有 migration、真实服务路由和 daemon，不使用共享数据库。固定源码/配置 digest、DB/project/claim 身份与测试键 ID；证据分别标记“组件 CP”与“真实链补充”，二者都满足才可登记相应 ADJ 场景完成。

证据登记分级如下（是判定规则，不是当前通过状态）：TC-TAC-001～003、006～010 的目标为整条，仍须各自 THEN/AND 全部实跑通过；TC-TAC-004/005 的本地机械 CP PASS 只能登记条款级，不得以 TAP 绿色代替外部事实。

| TC-ID | 机械 CP PASS 的登记等级 | 整条通过另需的决定性证据；缺席时 |
|---|---|---|
| TC-TAC-004 | **条款级**：本地原 bytes/digest、来源结构与 json-pointer 拒绝、零副作用 | 真实 M 签发 route 与 DB 行证明独立提取及结构、映射、认证 actor/机器凭据、跨 DB project 拒签，并关联真实 daemon/T 篡改准入拒绝与零副作用；缺席则保持条款级，不得登记 SC-TAC-004 整条通过，新合同失败关闭 |
| TC-TAC-005 | **条款级**：本地公钥写尝试编排、拒绝结果与 digest 组件断言 | 每个拟启用平台的不同 daemon/agent 身份真实覆盖/替换/追加、内核错误及前后 SHA-256；任一平台缺席则保持条款级，不得登记 SC-TAC-005 整条通过或启用新合同 |

外部证据不得塞进上述本地 CP action，也不得以模拟 route/DB、模拟权限错误、skip 或 `# skipped 0` 代替。

### 3.2 ADJ-001 / ADJ-002 真实链

- 在同一真实 M 签名服务下建立 project A/B 与两个物理安装根。采集有效 B 证明，替换/复制到 A 后执行五个首次控制写入口；除错误码外，必须给出所有业务 write-set、消费与任务数为空的证据。
- 通过真实结构化人类请求 route 签发，核对平台而不是 Agent 生成 `source_event_id`、原 bytes SHA-256 和逐字段 json-pointer；分别注入机器凭据/错误 actor 与跨 DB project 归属，断言各自拒签、DB 无新增签发记录且零业务副作用。另将 `accepted_rules` 改一个字符而保留签名，经真实 daemon/T 链验证拒绝。
- M 的 route/DB/daemon 测试与 T CLI 输出须能由同一 grant/source/project 标识关联；静态源码检查、直接调用签名函数或只测 `readExecutionSource` 不足。

### 3.3 ADJ-003 目标 OS 内核证据

每个拟启用平台单独形成一份证据，至少含：OS 与版本、daemon/agent UID 或 Windows SID/服务身份、trust root 与 key 路径、agent 实际执行的覆盖/替换/追加命令、真实 exit code 与内核错误、写前后公钥 SHA-256、后续只读验签结果。

- **Linux**：daemon 与 agent 必须为不同 UID；以 agent UID 实际执行写系统调用，采集 `EACCES`/`EPERM`。`id`/`stat` 只是身份与配置旁证，决定性证据是真实写失败。
- **Windows**：daemon service 与 agent 使用不同用户/服务身份；以 agent 身份实际执行覆盖，采集 Access Denied 与 digest 不变。`icacls` 只是 ACL 旁证，不替代真实写尝试。
- 同 UID 的 `0700/0600`、路径 pin、硬链接发布、组件校验、容器路径检查均不能单独关闭 ADJ-003。任何拟启用平台缺证据，结论只能是该平台未验证且不得启用。

## 四、测试执行矩阵

| 功能模块 | 单元/组件 | CLI/Git集成 | 真实跨端/OS | 状态 |
|----------|-----------|-------------|-------------|------|
| 根归属、来源与公钥链 | digest/json-pointer/schema/dev-ino窄边界 | TC-TAC-001～004、006 | 真实M/daemon；TC-TAC-005内核证据 | 待实现 |
| repair/resume | 原预算/停止规则回归 | TC-TAC-007～008 | 当前claim/head与真实daemon正例 | 待实现 |
| register/archive | 原事务/journal回归 | TC-TAC-009～010 | 预分配CR/claim与真实daemon正例 | 待实现 |
| 普通读与已提交恢复 | 现有只读/事务测试 | TC-TAC-006、007、009 | 平台失联与恢复负例 | 待实现 |

## 五、回归风险矩阵

| 风险区域 | 本 change 改动 | 已有回归保护 | 风险等级 |
|----------|----------------|--------------|----------|
| grant/source/key读取与原bytes | 五入口统一trustRoot和独立验源 | execution-authorization、execution-binding既有测试＋TC-TAC-001/003/004 | 高 |
| 当前claim/head/scope与根绑定 | 共用准入、锁内复核、operation白名单 | execution-control/binding测试＋TC-TAC-002/006 | 高 |
| repair额度、origin、停止与恢复 | 在既有裁决前新增同一信任缝 | repair-governance与durable事务测试＋TC-TAC-007/008 | 高 |
| register候选CR与事务时序 | 首写前核平台CR/claim/registration key | register-tx/idempotent测试＋TC-TAC-009/010 | 高 |
| archive首写与已提交恢复 | 新业务写入接准入，journal重放不重复 | archive-tx与恢复测试＋TC-TAC-009/010 | 高 |
| 普通读与legacy兼容 | 不新增读路径信任要求，不自动升级legacy | status/next/gate/crctl回归＋TC-TAC-006 | 中 |
| 部署身份与启用边界 | 新合同以真实身份隔离为前置 | 每目标OS内核证据＋TC-TAC-005 | 高 |

## 六、建议补充顺序

1. **第一优先 P0**：TC-TAC-001～005、007～010。先建立真实来源/key/root正例，再逐一加入跨project、复制、篡改、撤销与零副作用；同步取得目标OS身份证据。
2. **第二优先 P1**：TC-TAC-006。集中验证普通读、只读check、旧head/撤销/失联与已提交恢复兼容。
3. **第三优先 P2**：本 change 无 P2；任何新增语义不得以“后续补”为由绕过上述 P0/P1。
4. 最后运行既有相关回归与项目实际质量入口，区分历史失败、新失败和基础设施阻断；本 SPEC 阶段未执行耗时全量套件。

## 七、当前不可验证项与明确边界

- **实现与全部10个TC当前不可验证**：测试文件和实现属于 BUILD，本阶段未创建、未执行；Canon/YAML检查通过不等于行为通过。
- **真实M控制面闭环当前未验证**：本阶段未启动一次性DB、真实route/daemon，也未执行五个写入口，故ADJ-001/002不能关闭。
- **真实OS身份隔离当前未验证**：本阶段没有目标部署清单、不同UID/Windows身份的公钥覆盖输出，故ADJ-003不能关闭；不得从现有trustRoot缝推导。
- **生产启用、真实CR、存量迁移、共享DB与真实部署版本不可由本方案证明**：它们需要各自授权和部署证据。
- **自由文本、comment、附件、issue_source_context**不是本期授权来源；本方案不验证也不开放这些路径。
- **未列出的普通读、legacy写、repair-assess/outcome、extend/migrate/sensitive-action**不获得本 change 的新信任语义；其既有行为不属于本10个TC的新增覆盖。
- **可信组件自身被攻破**不在保证范围内：平台签名服务、DB、daemon与实际部署控制工具属于信任基；本方案不声称防御其被接管。
