# AIFI-45 strong resume4 — 仅 A1 / B1 / B2 修复复核

## 三项结论

| 原 finding | 本轮判定 | 限定含义 |
|---|---|---|
| A1/P2：签发上限不是硬上限 | **OPEN** | 新锁在同一事务内且 key 对齐，但 RR snapshot 在取锁前已建立，等待锁不刷新 count 的视图；不同 challenge 仍可越过 256。不是只因缺少动态测试而拒绝关闭。 |
| B1/P2：cp 缺源也被算作被防护 | **CLOSED（原根因、静态范围）** | 先创建 evil.pub，原 ENOENT 假阴性消除；deny 极性正确，新增 EROFS 与终态摘要断言加强了组合证据。但不等于九个命令逐个失败原因均已证明为 EROFS。 |
| B2/P2：空工作卷/路径可见性证明可假阳性 | **PARTIAL** | 旧 ls pipeline 和 ../ 别名误分类已去除；但实际只有 !test -d，不是完整路径不存在断言；报告仍写“空卷”“/control* 全 absent”及普遍无控制通道，未与窄检查对齐。 |

**新增 P0/P1：无确证新增。** A1 是原 P2 未修复，不重复计数；B2 是原 P2 的剩余，不另计。B1 的逐工具原因不足是证据边界/加强建议，不因它重新打开已修好的“cp 源不存在”根因。本轮未确认新增独立 P2。

## 范围、方法、版本

只读复核以上三项及必要直接 SQL/验证 helper、指定报告和作者运行元数据；不重开首次 CR 来源、其他业务门禁或全量锁序。**没有 DB 访问，没有运行 Node/Podman/probe/测试/vet/编译/生成器，没有修改产品源码/测试，没有子代理。** 另一代理 DB 单权保持。动态调度、实际锁等待、真实 agent/容器运行未验证；下述并发反例是静态控制流与 PostgreSQL RR 语义推演，不冒充实测。

M 根：`C:/Users/GOBAO/Downloads/AI/multica`；源码行号相对此根。validation 根：`C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/`。

本轮源码 pin：`binding-issue-20261025T081500Z-issuelimit-green3-source-manifest.json`（2026-10-25T08:57:36.451Z），三文件当前 raw SHA-256 均匹配：handler 21,674 bytes / `0ecfa77d6600bdabfbba012e9122c1a4124f491c043a955157b79698b6610ce4`；主 test 40,141 / `0fb6e4bcbff69d29afbfeeab5d422d87ddd3c22bd398f1472647a7322595f3f5`；probe 9,184 / `50c9079efd3d49d53a62174e6586779ed0b153a28f5070558ee0fce8a7627e6f`。

B 的最新作者 JSON 是 **`trust-root-20261025T085700Z-probe.json`**（08:57:25.462Z，9 checks），不是旧的 T084600Z JSON。T084600Z-report.md 已引用新 JSON；本报告不把旧运行当新修复证据。JSON 本身没有逐命令 stderr/状态/原始 inspect/脚本执行 hash，green3 manifest 的 probe freeze 不等于 JSON 内建的运行身份链。配置模型沿用 strong；actual backend unknown。

## A1 — OPEN：锁串行化了动作，没有串行化 RR 的可见快照

### 1. 足以反驳硬上限的现有代码路径

`server/internal/governance/execution_binding_issue.go`：

- **:141**：`BeginTx(... IsoLevel: pgx.RepeatableRead)`。
- **:149–152,162–164**：先读 claim、head；普通查询已建立该事务的 RR snapshot。
- **:222–231**：查已有 challenge；命中直接 envelope/changed=false，仍在锁之前。这个顺序未回退。
- **:241–245**：在同一 tx 上等待 `pg_advisory_xact_lock(hashtextextended($1,0))`。
- **:246–257**：用同一 tx 的普通 count 读 W/CR/head，再判断 >=256。
- **:278–282,301–305**：INSERT 并提交。表没有按 head 的数量 CHECK/slot/counter 约束。

反例（同 W/CR/G、两个不同 challenge C1/C2，未执行）：

1. 已有 255 条，T1、T2 在 T1 提交前分别读 claim/head，均建立可见 255 的 snapshot。
2. T1 拿锁；T2 到达取锁处等待。
3. T1 count=255，插入 C1，commit，释放事务锁；最新 committed 总量 256。
4. T2 此时确实获得同一把锁，**但它的 RR snapshot 仍旧**；count 仍为 255。
5. T2 插入不同唯一键 C2 并 commit，最终 257。

advisory 锁不更新任何保护行，没有“读到并发修改保护行→强制 RR abort”的机制；不同 challenge 的 INSERT 不争用相同唯一键，所以不能指望唯一冲突/40001 必然替代硬限额。PostgreSQL REPEATABLE READ 也不因本例普通 count 读集自动获得 SERIALIZABLE 的谓词冲突保护。

因此 **:238–240 “serialises ... so the bound is hard” 注释不成立**。并发数较大时多个持有旧 snapshot 的事务仍可逐个拿锁、逐个越限。真实 DB 是否在某次调度表现为超额、具体等待/取消/响应码，本轮未验证；不影响这个静态反例成立。

建议必须解决“容量检查可见性与写约束”本身：例如合理设计的原子受限写/容量槽位、或能确保检查看到前一 writer 提交且保持其他验证一致性的事务协议。单纯在这个 RR 事务更早放一条取锁 SELECT，也不能未经分析就签字：SELECT 自身也可能在等待前建立 snapshot。改成 READ COMMITTED 虽能让后续 count statement 取新快照，但会改变原 claim/head 一致性，不能不审这些影响就机械替换。本轮不实现方案，不增加授权消费预算或总账。

### 2. key 三元组、拼接、hash 的核查结果

- **:104–105** 的 key 是 `execution-binding:` + workspaceID + `:` + crID + `:` + head.GrantDigest；**:242,:248–251** 锁/count 用的是同一组逻辑值。count 的 workspaceUUID 由同一个 workspaceID 解析。
- **:120–127** 验证 canonical lowercase UUID 与 CR 格式；`execution_authorization.go:88–90` 的 UUID、CR 正则不允许冒号，CR 也无任意自由文本。head 的 digest 经已验签 head helper 从 ExecutionGrantDigest 得出（`execution_authorization_head.go:183–190`），不是未经验证的 body 文本。
- 在这些输入约束下，文本拼接没有冒号分段歧义；同一个三元组不会因大小写/UUID 别名产生不同 key。锁粒度是 W/CR/grant，不含 task、runtime、challenge，符合 count 聚合粒度。
- **不能保证不同文本的 64-bit hash 绝不碰撞**。`hashtextextended` 是有限宽度 hash；文本前缀避免明显命名冲突，不是互斥的 hash namespace。不同三元组乃至其他 single-bigint advisory 使用者理论上可撞到同一锁号，带来额外串行/等待；这不是拆成不同锁号后误并行的原因，也不能修复 stale snapshot。
- `hashtextextended(text,bigint)` 返回 signed bigint，可为负。`pg_advisory_xact_lock(bigint)` 接受整个有符号范围；当前 SQL 直接传数据库结果，没有 Go uint/int 转换、abs、截断或业务整数算术，**负值不构成错误，也没有此处的应用层溢出问题**。本轮未执行 DB 取负值样例。

### 3. 持锁时间、锁序与死锁边界

- tx.Exec 是本事务同一连接上的调用，确实为事务级锁，不是池中另一连接/会话锁。普通成功路径 **:301** commit 释放；错误/429/replay 的 defer rollback 在 **:146**，唯一冲突分支 **:287** 显式 rollback 先释放再池外重读。自动释放生命周期正确。
- 持锁覆盖 count、本地签名/封装、INSERT、commit/rollback；正常成功回复在 commit 之后。错误/429 会先 writeJSON 再 return/defer rollback，故可能连响应写入耗时也包含在持锁期；不要把它描述成只有瞬间 count。未测慢客户端/锁超时/跨实例饥饿。
- 该事务的 claim 是普通 SELECT（`server/pkg/db/queries/execution_binding.sql:7–18`），head 是普通 JOIN SELECT（`queries/approval.sql:25–35`），不是 chat session/maturity/task 的 FOR UPDATE。新路径只拿这一把 head advisory，再 INSERT 独立 ledger；migration 643 没有 FK，也无 INSERT trigger 扩展到那些业务行。
- **在本次直接路径内未发现反向获取 chat session→maturity advisory→task 链的新增边**，因此未确认新增死锁 P0/P1。但不将“未见边”说成全局无死锁：hash 碰撞/其他锁族/DDL/外部调用组合与实际 waits 未跑，也未审整个旧链。**旧 claim 锁序仍 INCOMPLETE。** 本结论不能借新锁给旧锁序补签。

### 4. 唯一冲突重读是不是额外绕过点？

**:284–297** 只有 INSERT 已失败后 rollback，再按 W/CR/G/challenge SELECT winner 并返回 changed=false；不会再 INSERT，也不会新签第二个证明来返回。它确实不重新 count，但这是回已有行，不是新增容量路径。已有 256 条时可重放本来就是需求，不把它当作计数绕过。

定向检索 `CreateExecutionBindingIssue(` / `INSERT INTO cr_execution_binding_issue`：本轮只见此生产 handler、SQL/生成包装及 fixture 预填；未确认第二条生产新签发路径。advisory 锁是协作机制，不是数据库写入权限/数量约束；手工 DML、旧版本混部或未来绕过 helper 的 writer 不会被它自动挡住，但未在本片确认这些实际生产路径。**当前已知绕过仍是 A1 的 RR snapshot，不需要借假设隐藏 writer 才成立。**

### 5. 作者 GREEN 不能证明这个竞态关闭

`issuelimit-green3.meta.json` 08:57:58.631Z 记载 **25 RUN / 25 PASS / 0 FAIL / 0 SKIP，22 leaf**，exit 0，以及原库不变/资源清理等；是作者材料，本评审未运行/核验 DB。

主 test hash 与上一轮完全相同；`:1010–1110` 原 limit leaf 仍为预填 256、顺序 reject/replay/另 head 正常签发，没有本次新增的“两个事务先建立旧 snapshot，再依次得锁”确定性交错证据。总数 GREEN 不否认 A1。

## B1 — CLOSED 原缺源根因；不签每个命令都只因 RO 失败

**位置：`scripts/aifi45-isolation/trust-root-probe.mjs:73–100,126–140,148`。**

- **:75–76** 在 set -eu 下先创建 /tmp/evil.pub 与 evil.json；cp 的源现在存在，原“缺源也算防护成功”输入缺陷已消除。其路径在新的 writable /tmp tmpfs 内（create 参数 :104–105）；不是从 RO 目标读到空输入。
- **:80–83**：`out=$(sh -c "$1" 2>&1) && { echo "BYPASS:$2"; return 0; }; echo "denied:$2"`。赋值语句承接 child exit status；成功分支 return 使它不再落入 denied，失败分支才 denied。if/AND-list 中不被 set -e 提前终止是预期行为。**极性正确，没把成功写入算成拒绝。** JS **:128–134** 要九标签齐全且无 BYPASS。
- **:95,:135–137** 给一个新路径 touch 单独要求 `Read-only file system`。这比只看任意非零强，且不把目标已存在误当 EROFS；提供新 JSON 记载此 check。
- **:96,:138–140** 在全部尝试之后核对 key hash，**:148** 还读回宿主 key。是整组结束后的终态摘要，不是每一条命令后逐次采样。它能检测这组尝试留下的 key 内容改变，不单靠工具 exit code。

**对用户问的“三层是否足以证明 9 个向量都是 RO 原因”：否，不能做逐命令唯一归因。** 它们足以把可签结论加强为：inspect 显示 RO bind；九个准备好的命令没有成功；新路径至少有一个明确 EROFS；最终 key 内容未变。当前 `out` 并未输出/保存，所以 cp/ln 若实际以 File exists 失败，会被正确记为“该命令未成功”，不会错误报 BYPASS，**但仍没有证明该条的失败原因就是 EROFS**。仅由已有 JSON 不能确认那次 cp/ln 的具体错误文本；本文不猜 BusyBox 内部实际走到哪一步。

作者报告 **:19** 已明确承认 File exists 不等于 EROFS；三层组合说明不应再被改写成“九项逐个均由只读挂载拒绝、排除了所有其他错误”。脚本 **:78–79** 的 each denial must be readonly 原因注释、**:129–131** 的措辞仍比实际检查强，建议收窄或逐项保留 stderr/status，并在相同 uid/permissions 的 writable 对照上证明这些命令本来能成功。保留该建议不等于重新打开已修复的 ENOENT 根因，也不是生产隔离域签字。

## B2 — PARTIAL：旧算法已改，报告/断言精度仍有残留

**源码：probe :97–100,109–121,141–147,158–163；报告：`trust-root-20261025T084600Z-report.md:13–25,30–39`。**

已修复：

- 去掉了旧的 `ls -A /work | wc -l`；不再把 ls 失败的 pipeline 输出当空目录。
- 不再使用 `/work/../control-ro` 或 /tmp/../... 类别名作为控制通道；当前五候选是 `/run/podman/podman.sock`、`/var/run/docker.sock`、`/control`、`/control-channel`、`/control-ro/socket`。
- **报告 :25** 确实明示同 UID 可改 key 是其声明的当前产品状态、daemon 未将 agent 放进该容器、本 probe 未测 cgroup/持续新鲜度/CR/T 消费，消费继续关闭。此披露清楚；不借作者引用另一个 cgroup probe 作本评审签字。

剩余原 finding 范围：

1. **:97 的代码不是 test 路径“不存在”，而是 test -d 为 false。** 普通文件、某些不可达/坏链接路径也不是目录，都会打印 work-volume:absent。若要字面断言不存在，应显式检验路径存在/链接/错误条件；若只需证明没暴露工作目录，应如实命名为“/work 不是可见目录”。当前固定 Alpine 场景可合理预期没有 /work，但本轮没有动态 stat 去确认，不能把预期当实测。
2. **报告 :14 仍直接写“/work 空卷”**，与新“非目录/absent”算法不符；用户说“已改不存在”不能替代当前落盘文本。inspect 唯一 host bind 为 /control-ro 是额外、较强的“没有另一个宿主 workspace bind”证据，但不把一个未挂载/不见的路径变成受检空卷。
3. **报告 :13 的 `/control* 全 absent` 不准确**：/control-ro 正是存在且 key 可读的 host trust bind；脚本只枚举五个具体候选，并未扫描 glob。**报告 :23** “没有可达控制通道”与 probe/JSON **:163** 的 blanket claim 仍超出有限路径 test -e。不可见的候选不等于任意路径、FD/abstract socket/daemon 协议都已排除，也没测 challenge 冒充。check **:147** 的“no ... host directory”若按字面理解也过强，因为 /control-ro 就是有意暴露的宿主目录。

应把结论写成“本次 mount inventory 只有受检 RO trust-root bind，/work 未见为目录，列出的五个控制路径未见存在；未验证其他通道及真实 daemon/agent 隔离”，而不是签普遍隔离。

### 同一报告的既有歧义（不新增计数，不扩大实施范围）

- **:19** grant “公开材料”仍应限定为允许被授权 verifier 只读的非私钥材料，不等于租户 goal/路径/身份等对任意人公开；本 probe 的 stand-in 也没有单独 grant 可读性/保密性测试。
- **:30** 仍写 7 项，但新 JSON 是 9 checks（:35 已写对）；**:33** 仍写源码 create argv 没有的 --http-proxy=false、按名清理却称 OID 级；**:39** unresolved:false 与仍未关闭语义相反。这些上一轮已指出，未据此推导 P0/P1 或关闭 major。
- admission_enabled=false/consumption_enabled=false 是 **probe :161–162** 写死标签，不是探测产品运行开关。same UID 也是 stand-in owner 的动作，不是本轮实际启动 agent。保留产品风险/消费关闭陈述，不把它们当已执行的生产测量。

## 最终边界

A1 **OPEN**（原 P2 仍在）；B1 **CLOSED 原缺源根因**（每向量 RO 唯一归因未验证、不承诺）；B2 **PARTIAL**（旧 pipeline/别名消除，路径/文案剩余仍在）。**无确证新增 P0/P1，无新增独立 P2。** 动态并发、锁等待/死锁、当前容器每命令 errno、真实 daemon/agent 执行与完整控制可达性未验证。静态切片审阅已完成，不把整个工作仅因没跑动态就标为 INCOMPLETE。

**不签消费/准入/activation/隔离域/全局 C1/Gate3；旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 major 未关闭；消费 closed/off。**

## 发布前身份复核

UTC：`2026-10-25T09:07:39.686906+00:00`。以下五份本轮主要输入再次无漂移；只读 hash/解析，不访问 DB 或执行 probe。

| 文件 | bytes | raw SHA-256 |
|---|---:|---|
| server/internal/governance/execution_binding_issue.go | 21674 | 0ecfa77d6600bdabfbba012e9122c1a4124f491c043a955157b79698b6610ce4 |
| server/internal/governance/execution_binding_issue_test.go | 40141 | 0fb6e4bcbff69d29afbfeeab5d422d87ddd3c22bd398f1472647a7322595f3f5 |
| scripts/aifi45-isolation/trust-root-probe.mjs | 9184 | 50c9079efd3d49d53a62174e6586779ed0b153a28f5070558ee0fce8a7627e6f |
| validation/trust-root-20261025T084600Z-report.md | 4779 | f7a87ad2e14dbda5a3b350d68f920ba4ff68c4c3c78f7678b5e148d94bdc03df |
| validation/trust-root-20261025T085700Z-probe.json | 1079 | e75bedc8e407c5a5f607749ec06655eb7dde5585438d26148b616949b45796da |

必要直接 helper/SQL 发布时样本（不是运行证明或主 manifest 历史 pin 的扩展）：

- `server/pkg/db/queries/execution_binding.sql` — 1646 bytes；raw SHA-256 `2305fc71d51b7c761e5d7c85a2771e04e6b3b30d17c6381aad7bc9863886fd72`。
- `server/pkg/db/queries/approval.sql` — 9911 bytes；raw SHA-256 `9575a40a3db5468d41edfc628b751887a2130e8e155d0fa51f9c4d3814374445`。
- `server/internal/governance/execution_authorization.go` — 44721 bytes；raw SHA-256 `0c68aca15dd2a57e8a407e5f76a98df264ceec52b31a38433a618cf4ba96a074`。
- `server/internal/governance/execution_authorization_head.go` — 10791 bytes；raw SHA-256 `710a709793df4cb1079f95db517f3eeb5d0f724f6764a3df551a3ec9e3260512`。
- `server/migrations/643_cr_execution_binding_issue.up.sql` — 1632 bytes；raw SHA-256 `495ec3c0ee54d1a29b3ad376a2f7d0cbd5844960c9035685a7821fb612cfcbbe`。
