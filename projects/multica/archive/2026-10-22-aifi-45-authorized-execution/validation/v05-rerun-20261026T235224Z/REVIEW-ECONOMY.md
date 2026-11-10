## 方案裁决：BLOCK（economy lane 补充完成）
**实现/动态验收：未执行，不作通过裁决。** 本路未修改任何文件/测试/DB，未运行任何命令性验证（仅只读 grep/read），未看其他 lane 输出，未委派。requested `GB-JP/deepseek-flash:high`；actual 无后端回执 → **unknown**。输入漂移按父会话结论视为无。

---

### 1. 本轮补读证据（仅补三处，未重读已读文档）
| 证据 | 结论 |
|---|---|
| `implement-code/SKILL.md` Step 4.6（:88）、触发条件（:90）、命令（:94）、失败口径（:96）、非闸门声明（:98）、Step 5 输出项（:112） | **与方案/Goal v0.5 完全一致，Skill 侧闭环** |
| `lib/change-scope.mjs` 导出 4 个：`evaluateChangeScope`(:24)、`collectChangedPaths`(:80)、`symlinkEscapes`(:114)、`checkChangeScope`(:158) | **纯判定函数确实存在且无副作用；方案“复用 + 新写收集”判断成立** |
| `crctl.mjs` CLI 失败映射（:1873/:1883/:1884）+ :1878–1880 注释 | **顶层失败码与方案闭集前 3 个逐字相等** |
| `m001-m002-evidence-gap-ledger-20261026.md` G1/G5 行、§2 锁图、§3 步骤 2/3 | **B2 已修说法成立；残余是 G1/G5 扩展，非“B2 未合入”** |

**Skill 一致性（原 INCOMPLETE 项，现 closed）**：Step 4.6 的触发是 `cr.md` frontmatter 带 `execution-contract` **且** 安装根 `.crctl/grants/` 下存在该 grant 文件（:90）；命令为 `crctl authorization-scope <CR> --grant <file> --workspace <ws>`（:94）；:98 明写“本步是执行者自检，不是强制闸门；merge 侧的强制核对属于可信裁决通道（M003）范围”。方案的三个对应陈述（非强制闸门、merge 强制核对归 M003、`--grant`/工作区只定位不决定权威）**逐条对得上，无过度声明**。反过来也印证方案的正确性：Skill 的触发全是 agent 可写物（`cr.md` + 安装根 grant 文件），所以方案拒绝把它当 merge 权威来源，是**必要**而非多余。

**复用边界（原 INCOMPLETE 项，现 closed，判定合格）**：`evaluateChangeScope` 体内只有 Set/Array/String 操作，无 `spawnSync`/`fs`（:24–:57）→“纯判定”属实；git/fs 全在 `collectChangedPaths`(:80)/`symlinkEscapes`(:114)/`checkChangeScope`(:158)。且不复用 `collectChangedPaths` 的理由被源码证实：它有 `origin/${trunk}` 回退（:81）、混入工作区 diff `HEAD`(:92) 与 untracked(:105)，与“只核已发布提交区间”语义确有差异。→ **既不是“缺少已有纯函数”，也不是“强行复用不适用采集器”**。B17 四项亦静态复核成立：`-z` 无 trim（:62–:66）、rename 取源+目标两字段（:98–:100）、symlink 判不出返回 null→`escaped === null` 即拒（:48、:114–:127）、非数组变更 → `AUTH_SCOPE_INPUT_INVALID`（:35–:39）。

---

### 2. E08 更正（撤回，降为 minor 措辞问题）
**不进 findings 的顶层码**（`crctl.mjs`）：`EXECUTION_AUTHORIZATION_REVOKED`(:1874)、`AUTH_SCOPE_VIOLATION`(:1883)、`AUTH_SCOPE_UNVERIFIABLE`(:1884) —— 与方案 §3 闭集前三项**逐字一致**。
**仅为 finding 子码，被折叠进 `detail.findings`**（`evaluateChangeScope` :36 `INPUT_INVALID`、:44 `REPOSITORY_UNKNOWN`、:48 `PATH_ESCAPE`、:54 `PATH_NOT_ALLOWED`；`checkChangeScope` :166 `REPOSITORY_IDENTITY_MISMATCH`）。任何 findings>0 → 顶层统一 `AUTH_SCOPE_VIOLATION`。
**`EXECUTION_AUTHORIZATION_HEAD_MOVED` / `UNAVAILABLE`**：CLI 侧无对应码，是规划中的 merge 预检**新码**，方案已把它限定在 M003 merge 段、未声称 AIFI-45 自检会产出 → **不是接口缺陷**。

**E08′（minor，文档措辞）**：方案 §3“X7 已决”写“控制根每次文档改动都会 `AUTH_SCOPE_PATH_NOT_ALLOWED`”，把 finding 子码当作可观测顶层码。最小修订：改为“顶层 `AUTH_SCOPE_VIOLATION`，其 `detail.findings` 子码为 `AUTH_SCOPE_PATH_NOT_ALLOWED`”。**归属**：M003 方案（措辞）。我上一版的 E08 判断有误，此处更正并撤回。

---

### 3. E09 重核（B2 不是缺口，缺口是 G1/G5）
- **B1/B2/B3 已就地修**：台账 G2“部分已修（B1…）”、G4“部分已修（B3…）”；**不再**认定 B2 未合入，撤回该表述。
- **真正的 A 类残余**：`G1 未修`（读完 active generation 后暂停，另一事务取消/重领或改 runtime 归属并提交，原事务仍可写 receipt/activation；“三写端点共用完整校验事务 + 锁 task/runtime 归属行至提交 + `55P03` 探针”）；`G5 未修`（adopter 普通 SELECT → 另一事务标终态 → 无 `terminal_at IS NULL`/generation CAS 的 UPDATE 仍成功；“加锁 + RETURNING + 受影响行数为零即拒”）；另 `G2 残余`（签名 payload 仍不含 `dispatched_at`）、`G4 残余`（strict 全 tuple）。
- **E09′（major，跨文档归属/前置冲突）**：台账 G5 行把 B8 竞态本身判为 **A 类（不需要可信事实）**，并在 §3 步骤 2 要求 **AIFI-45 先做锁修复**；而 disposition §2.1 把 B8 整项并入 M003，方案 S1 又把 `root_adoption_terminal_race` 作为 **Channel 的 green leaf**。结果：该 leaf 的 green 实际前置是 AIFI-45 的 G5 锁修复（当前未修），方案 S1 未像 S6 那样显式声明前置。同理 S6 只声明“B1+B2 已合入”为前置，但 `claim_terminated_before_consume` 的真实前置是 **G1**（快照语义：读 claim 后转终态不得写消费）——B1/B2 已合入而 G1 未修时该 leaf 仍会 RED。**最小修订**：S1 增列“G5 已修”前置、S6 把前置从“B1/B2”改为“B1/B2/B3 + G1 + G2 残余”，并说明 Channel 只负责接线/探针、锁修复归 AIFI-45。**归属**：M003 方案 + AIFI-45 本地（台账已正确，只需方案对齐）。

---

### 4. 保留的原真 finding（重定级，区分“产品/设计阻断”与“记录级”）
| ID | 严重性（性质） | 位置 | 要点 |
|---|---|---|---|
| E01 | **blocker（验收完整性，非安全）** | 方案 §“验收证据检查”末段（约 :350–:356）vs S5 v0.5 补充（约 :296–:322） | 文本称“十条 Node leaf”，实际枚举 **17** 条；“head 撤销即拒”与“head 前移即拒”合写于一个 bullet/一个 mutation，违反“唯一全名 + 一一对应”。按十条冻结 `channel-test-expectations.json` 会漏 7 条仍判 green（假绿）。 |
| E02 | **blocker（产品设计，实质未定语义）** | 方案 §3 (a)/(b)（约 :118–:121）vs 修订记录 v0.5 二轮行（约 :455） | 正文仍“实现前二选一”，修订记录却称“核对对象必须等于实际发布对象”已定；S5 leaf“symlink 取自**批准树**”只在 (b) 成立，与 (a) 互斥 → 互斥未消解 + 记录过度声明闭环。 |
| E07 | **blocker（接口未定义，真实新需求）** | 方案 §3 ②/失败码（约 :127–:131）vs §6（约 :183–:186） | §6 只有 3 个写/取端点，无 typed-facts 只读端点；而源码注释（`crctl.mjs:1878–1880`、`change-scope.mjs:150–153`）明确“current platform 确认裸 CLI 做不到”，佐证这是**必需的新端点**。反例：实现者只能自造未审阅的信任边界。 |
| E04 | major（记录） | disposition §3（约 :92–:100） | 编号 1,2,3,4,5,6,7,**5** 重复；条目 5“strong 仍在跑”与条目 6“strong 已回 BLOCK”并矛盾。 |
| E05 | **major（可追溯性，非安全）** | 旧评审副本 `…v05-review-20261026.md` 结论表（约 :9–:11） | 三路 session 写成 `01a17797-…`，应为 `01a1796a-…`。**仅在记录侧更正并注明原误写**，不得改被审输入/冻结 SHA。不是安全阻断。 |
| E03 | minor（记录） | 方案文件头 v0.5 行（约 :6） | “未经复核”与修订记录（已两轮复核后修订）不符 → 读作“无复核输入”。 |
| E06 | minor（编辑） | 方案 Tech stack/§3 重试 | 全文无 X8/`inputDigest` 边界；建议补一句“旧摘要被交付 gate 拒绝 ≠ 已自动重测”。 |
| E10 | minor（新，精度） | 方案 §3“空集合四证明”+ 归属划分 | “仓集合完整（不因 graph 删项缩小）”未写死集合来源（grant 集 vs granted∪graph）；且现实现中 graph 内某仓缺 CR worktree 即 `problems`→UNVERIFIABLE（:175–:179），merge 侧新写 `collectCommittedPaths` 必须自己定义该情形，否则语义与自检不同。 |

---

### 5. 旧问题闭环状态（本轮更新）
| 旧问题 | 状态 | 依据 |
|---|---|---|
| ③ 来源为 agent 可写 `approval.yml` | **closed（文档层）** | §3 ③ 改 M 持久批准记录 + 逐字段相等 |
| 核对区间 < 发布区间 | **partial** | 改 `trunk...HEAD` 但 (a)/(b) 未定（E02） |
| leaf:mutation 非一一对应 | **open** | 10:10 声称 vs 实际 17 条（E01） |
| X7 字段语义 | **closed** | repo id + `allowed_paths[repo]` 分立、无豁免 |
| 修订记录“待决 X7” | **closed**；新回归 **open** | E03 |
| economy：merge 端点/失败码未定义 | **E07 open；E08 撤回** | §6 缺 facts 端点；顶层码实际一致 |
| economy：旧 session 前缀 | **open（major 记录）** | E05 |
| B8 归属 | **partial → E09′** | 落点已写，前置与 A 类归属冲突 |
| economy：Skill/复用边界（原 INCOMPLETE） | **closed** | SKILL.md:88–98/:112；4 个导出与纯函数实证 |
| B2 锁图 | **closed（已就地修）** | 台账 G2/G4；残余为 G1/G5（非 B2） |

**新问题**：E10（minor）。E08 由 finding 降为措辞项；E09 由“B2 未合入”改判为“G1/G5 前置未写”。

---

### 6. 阻断通过的最小集合
1. **E02**：定死 (a) 或 (b)，删另一支；统一“批准树”→“merge 实际发布源 tree”；修订记录措辞同步（产品设计阻断）。
2. **E01**：重算 leaf 数并写死 17 条清单；拆开 head 撤销/前移为两条唯一全名 + 各自 mutation；再更新修订记录“10:10”（验收完整性阻断）。
3. **E07**：§6 定义 typed-facts 只读端点（path/认证/入参/出参闭集/错误映射），或改为 M 内部服务调用不经 CLI（接口阻断）。
4. **E09′**：S1 增“G5 已修”前置，S6 前置改为 B1/B2/B3+G1+G2 残余；说明锁修复归 AIFI-45、Channel 只做接线与探针。
5. **E04/E05**：修 disposition 编号与“strong 仍在跑”；旧 session 前缀在记录侧更正（记录级，可并行，不阻断产品设计）。
6. **E03/E06/E08′/E10**：措辞与精度修订（可随任一版本一并改）。

**严重性口径**：真正阻断“计划可实施/可验证”的是 E02（设计未定）、E07（接口缺失）、E01（验收名单失真）；E04/E05 属记录级 major，须修但不构成安全阻断；E08 已撤回为 minor。**残余限制**：本路未重核冻结 SHA（父会话已核）、未读 `tc-coverage` 与 `lock-graph` 全文，故 41/49 与锁图单调性本路不作独立判断；本路结论仅覆盖 economy 轴（文档与 Skill/API 一致性），不代 balanced 的测试矩阵判定与 strong 的实施可行性判定。
