# AIFI-45 strong resume3 — 签发资源上限 / trust-root 探针限定复核

## A/B 判定摘要

**A：PARTIAL。** `executionBindingIssuanceLimit=256` 确实限制同一 W/CR/head 的串行新 challenge，并把可见的旧 challenge 重放置于计数之前；常量不新增 env 或可变 global。现有 daemon 分类也不把 HTTP 429 当永久 terminal 拒绝。但是 **count + INSERT 没有原子容量约束**，REPEATABLE READ 的同一快照不解决写偏斜：255 条时 N 个不同 challenge 并发可得到 255+N 条，故不能签“硬 256 上限”。固定有限并发下不能由此推导无限持续增长，但代码没有给出与并发规模无关的硬界。

**B：PARTIAL。** 提供 JSON 的 same_uid_rewrite_possible=true 支持“同一 owner/UID 下仅靠这组目录/文件权限挡不住自己写公钥”的窄事实；inspect 的只读 bind、非特权设置、部分有效写操作的失败和宿主 key hash 不变支持“该容器配置组合在所测场景阻断了写入”。**不足以支持报告的“9 类有效攻击均因 EROFS 被拒”“/work 是空卷”“没有任何可达控制通道”强表述**：存在缺源 cp 假阴性、pipeline 把 ls 失败变成 0、路径别名误分类，且错误原因被丢弃。报告明确承认 daemon 未把 agent 跑进容器、cgroup 未在本探针测、消费仍关闭，这些边界披露正确，不能因局部探针而解除。

**新增确证问题：A1/P2（并发超过宣称硬上限）、B1/P2（缺源复制也算被防护）、B2/P2（/work 空卷/路径可见性断言可假阳性）。** 没有确认新增 P0/P1 产品漏洞。另列文档过度表述及建议，不重复计数。

## 方法与身份

仅静态阅读 A 的增量/直接错误分类和 B 的完整小探针、指定 JSON/报告及 A 的三个新 leaf。**未访问 DB，未运行测试、Node、Podman、probe、vet、编译、生成器，未改源码/测试，未使用子代理。** 另一代理 DB 单权未被触碰。报告 wx 独占创建并回读验证。

M 根：`C:/Users/GOBAO/Downloads/AI/multica`；以下源码路径相对此根。validation 根：`C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/`。

A 主 pin：`binding-issue-20261025T081500Z-issuelimit-green2-source-manifest.json`，`2026-10-25T08:48:00.658Z`。handler 20,857 bytes / raw SHA-256 `785e322d09f8f9b1d11551085dae6cdd3b2adef0ae0a24df6eacfb47698ff164`；test 40,141 bytes / `0fb6e4bcbff69d29afbfeeab5d422d87ddd3c22bd398f1472647a7322595f3f5`，均匹配。B 脚本/JSON/报告只取本轮读取身份，提供 JSON 不含运行脚本 raw pin、逐命令 stderr 或完整 inspect，因此不冒充可独立重建的历史执行快照。模型背景沿用 configured strong；actual backend unknown。

## A. 签发上限

### A1 — P2：REPEATABLE READ 中先 count 后 INSERT，不构成 256 的并发硬上限

**位置**：`server/internal/governance/execution_binding_issue.go:135–141,231–241,263–269,286–290`。

claim/head/ledger lookup/count/insert 都在同一个读写 REPEATABLE READ 事务：q=db.New(tx)，count 直接 tx.QueryRow，insert 走 q。**同一快照是真，但并发容量约束不成立。** count 是普通 SELECT，没有按 head 的原子计数 CAS、唯一容量槽位或保证刷新计数的串行化机制；每个不同 challenge 插入不同的唯一键，不必发生唯一冲突，也不会仅因各自读了 count 就自动产生 RR serialization error。

静态交错（未执行）：

1. 同 `(W,CR,G)` 已有 255 条。
2. N 个请求在其他提交前建立快照，分别使用不同 challenge，都看到 issued=255。
3. 每个通过 `<256`，签发并 INSERT 不同 row；唯一键只排同 challenge，不能排这些不同 nonce。
4. 全部成功时最终为 **255+N**。例如 N=100 时是 355，不是 256。

**不能夸成固定并发可无休止增长**：没有删除/绕过/新 head 等条件时，实际 committed count 已达阈值后，新建立的快照会拒绝；超额主要来自阈值前已持有旧快照的在途事务。若系统对该 head 可能持有这类事务有已证明的有限上界 K，则在这些假设下可按约 256+K−1 考虑瞬时超额。代码没证明跨进程/实例的 K，更没有落实严格 256。无限增大 N 的数学反例不是说实际 DB 能提供无限连接。

修复方向：如果要求硬上限，应使用 head-scoped 原子受限计数/固定数量唯一槽位/可靠单写者等数据库机制。**不能只在已建立 RR snapshot 后再加一个普通 head 锁就声称修好**：等待锁不自动刷新旧 RR 的 count 视图；需相应事务/快照设计及失败重试/拒绝语义。保持它是资源限制，不偷偷引入授权消费总账/第二预算。本轮未设计或修改实现。

### 幂等优先：成立，但“重放永远可用”表述过强

- `execution_binding_issue.go:214–225` 先按 W/CR/head/challenge 查库；命中即返回存储 envelope、changed=false。之后才在 `:231–241` count/429，所以对当前快照中已存在的同 challenge，达到上限不额外扣额度、不拦回复；常规同 body 网络重试可复用。
- 仍先进行原有 claim/head/scope 校验；失效 claim/撤销或损坏 head 不因“重放”绕过。这不是新增限额导致的兼容破坏，也不能称所有旧回包永远 200。
- 并发提交的同 challenge 可能尚不在此 RR snapshot 可见；特别是已有超额在途签发时，新 request 的 snapshot 可见满额、却不见稍后提交的该 challenge，便会 429。顺序优先不等于重试对所有并发时间点线性化。
- 新 child/新的 requestExecutionBinding 产生新 nonce 是新签发，不是同 challenge 幂等重试；同一 head 汇总所有 run/process 的数量，并非“每 run 256”。256 是否足够覆盖正常长生命周期、多任务/重启/控制调用，未有业务容量证明。达到上限后 append-only 不随时间释放容量，不能靠普通等待保证同 head 恢复。

因此作者 `issuelimit-report.md` 的“重放永远可用”“单 head 增长钉死”应改为上述限定。没有发现 count 放在 replay 前的错误，但不能签无误伤所有正常重启/重试。

### 429 是否被 daemon 永久丢弃？

所读**现有分类不会**：

- `server/internal/daemon/client.go:1328–1344` 的 isTransientError 对 408/429 返回 true；后续 bounded retry helper 会按 schedule 尝试，而非 permanent 4xx 分支。
- `server/internal/daemon/terminal_report_queue.go:636–652` 只把 400/403、特定 task-not-found 404 归永久，429 走 false；`:844–848` 对非永久返回 false，留在 pending 而非触发 permanent quarantine。
- 这些是 generic retry/terminal outbox 分类，**不能把 terminal 的持久化保证移植成 binding 接口已有持久重试**。本轮定向检索 daemon 未见此 binding POST/错误码的生产 caller，私有 relay 仍未由本片接通；不能保证未来 binding caller 或整个任务生命周期绝不会丢失。
- 此限额是同 head 的持久满额，不是自然消退的速率窗口。用 429 不会在上述 classifier 中永久丢弃，但可能耗尽重试时长；需清楚区分永久满额语义、监控/恢复及避免忙重试。未据此确认新增独立丢任务缺陷。

### 常量与唯一键、位置

- `execution_binding_issue.go:37–39` 是编译期 const，不是新 env、可变 global、全局 feature switch 或授权预算；符合本 change“不新增 env/global 开关”的通常语义。它当然是 package 级常量名，不冒充“完全没有新增 package symbol”。
- 既有 UNIQUE(W,CR,grant_digest,challenge) **不是冗余 count 的替代**：只去重相同 challenge，不能限制不同 nonce 数量；hash nonce/按 challenge 去重同样不能限制基数。
- 资源保护应在保留 replay 优先后、昂贵签名/insert 前拒绝，当前串行位置合理；真正硬限额的约束需落在并发无法绕开的写边界。按 head 限制不等于全表/全租户存储总量有限，新 head/CR 仍增加历史行；不新增全局总账也不能据此宣称全库不会增长。

### A 的作者证据强度

只读 `issuelimit-green2.meta.json`/stdout：**4 RUN / 4 PASS / 0 FAIL / 0 SKIP，3 leaf**；元数据记载临时迁移/原库不变/清理，非本评审执行或 DB 核验。

`execution_binding_issue_test.go:1010–1110` 用 generate_series 一次填 256 条、测试满额新 nonce 429/no-row、满额 replay unchanged 和另一个空 head 正常签发。没有并发 N 请求的证据。

注意 `:1012–1026` 的 seed envelope 是 f.grant（initial authorization），不是 256 次真实有效 binding；`:1061–1099` 的 replay 只证明原存储字段回传，不能据此宣称达限回包已被 T 的 binding 验签接受。建议让 replay 对象来自一次真实绑定签发，再补足其余计数。此局限不否认源代码 replay-before-count，也不新增重复的产品 P2。

## B. trust-root 探针

### 哪些窄事实可接受，哪些不是它测到的

`scripts/aifi45-isolation/trust-root-probe.mjs:48–68` 在同一 Node/owner 上以 0700/0600 创建 stand-in key/grant，再 append、rename 替换 key 并读回。提供 JSON 的 same_uid_rewrite_possible=true 支持这次文件权限下 append/替换成功；**测的是 probe owner，不是执行了真实 agent 子进程/真实 installer**。它与“同 UID 下单靠这些 DAC 文件权限不隔离写入者”相符，不代表所有同 UID 且受额外 MAC/namespace/sandbox 约束的进程都可写。

`:91–109` 确实传 read-only bind、read-only rootfs、network none、cap drop、no-new-privileges、user 1000，并 inspect 断言唯一 host bind Destination/RW=false、非 privileged 等；`:115–116` 对容器读到的 key hash 作等值断言，`:131` 对宿主 key 存活/hash 作断言。JSON 有这组 checks。它们支持该组合的一定范围阻断，**没有独立分离只读挂载与 UID/DAC 的贡献**，也没有完整 kernel/container 逃逸审计。

### B1 — P2：replace_key 的 cp 输入根本不存在，任何非零都被当成防护拒绝

**位置**：`trust-root-probe.mjs:73–85,117–123`。

script 没有创建 `/tmp/evil.pub`，直接执行 `cp /tmp/evil.pub /control-ro/keys/<key>.pub`（`:79`）。/tmp 是新建 tmpfs，之前只有读 key；没有写 attacker 文件。因此该 cp 在进入目标写入前就会因缺源失败；即便换成可写目标，它也会失败。

`deny()`（`:76`）把任何非零状态标为 denied，stderr 又全重定向 /dev/null。后续只断言九个标签齐全、没有 BYPASS，**无法区分 ENOENT/语法/工具错误与 EROFS/EACCES**。报告“9 类真实写攻击均被容器拒绝”至少有这个反例。

纯 shell 极性**没有写反**：command 0 会输出 BYPASS，JS 见 BYPASS 就失败；`if sh -c ...; then/else` 使 set -e 不在预期失败处退出也是正常写法。问题是失败原因与攻击输入有效性，非“deny 会把成功写当 denied”。symlink 指向不存在文件本身可合法创建，不应把它与 cp 缺源混为一谈。

建议先在 /tmp 创建并读回非空 attacker 文件，验证同一 cp 在 writable /tmp 目标能成功，再对 RO 目标执行并记录具体错误；逐操作留 stdout/stderr/status，检查 key/grant 后态。无需为此使用真实生产 key。当前还有其他有效写尝试及 inspect RO 支撑窄组合结论，不将整个探针说成零证据。

### B2 — P2：/work “空卷”和路径可见性断言可由不存在/错误产生

**位置**：`trust-root-probe.mjs:74,86–95,124–130,143`。

1. create 参数没有创建/挂载 /work。
2. `echo "work-volume:$(ls -A /work | wc -l)"` 在未启 pipefail 的 shell 下，ls 若因目录不存在等错误退出，最后 wc 仍成功输出 0；外层 echo 也可成功。set -eu 不能保证识别该 pipeline 中间错误。
3. JS 只匹配 `/work-volume:0/`，由此设置 host_workspace_mounted=false，并声称 work volume empty。**缺失目录不等于“检查过一个空卷”**，路径读取错误也不能当作工作区内容不存在。
4. candidate `/work/../control-ro` 在 /work 不存在时 -e 为 false，哪怕 `/control-ro` 明明存在；若 /work 存在且可遍历，它反而会指向那个有意公开读取的 trust bind，从而标成 VISIBLE 并失败。这混淆只读数据根与私有控制通道，不是可靠的绕路探测。

唯一 host bind inspect 提供“本次没有额外 host workspace bind”的独立窄证据，故不据此声称实际已经泄露 workspace；但空卷及普遍不可达性断言的证明有缺陷。

建议：若要测试空工作卷，显式创建/挂载并先 test -d，再检查内容、检查每步状态；若根本不需要 work mount，就如实断言 mount inventory 中无 host workspace，不称“空卷”。不要把 `/control-ro` 的合法别名归为 engine/daemon 控制通道；分开检查数据路径与敏感 socket。

### 报告与证据的过度表述 / 可接受风险

- **EROFS 未被记录**：shell 逐条 stderr 已丢弃，JSON 只有布尔/标签，无法证明报告事实表的“全部 EROFS”。RO 与 user=1000 同时改变，chmod 等还可能被 DAC/ownership 拦住；需要 writable/RO 对照及 UID/GID/stat/errno 才能隔离原因。只读 bind 本来就应使写失败，不能据它证明 UID 差异本身有效，也不能证明所有拒绝来自 RO。
- **控制通道仅有限路径扫描**：四个 socket/目录的 -e 不命中，加 network none/无额外挂载，不能推出任意路径、abstract socket、已有 FD 等所有控制可达性都不存在。`/control* 全 absent` 也与有意存在的 `/control-ro` 不一致。未测试 challenge 冒充；不可写 key 不自动证明 challenge 不可被冒充。容器是本 probe 的一个候选技术，不证明它是唯一可能的隔离手段。
- **grant 不是一概公开数据**：公钥非秘密，授权包可以让被授权 agent 只读以便验签；但真实 grant 可含 goal、路径、租户/作者身份、敏感动作范围等，不等于对任意人公开。该 probe 用无效 PEM/简单 grant stand-in，适合测文件操作，不测密码学或隐私。脚本只 hash/read key，没有独立 read grant 断言；不要把“允许读公钥/授权材料”外推为保密已解决。
- **关闭标志是字面量**：`:144–145` 的 admission_enabled=false/consumption_enabled=false 是 probe 写死的描述，不是查询 daemon/执行消费负例得出的动态状态。消费关闭是本片既有约束，不能以这两个 literal 当生产开关测量。
- **报告确实披露未完成事项**：`trust-root-...-report.md` 的“没说明”明确写 daemon 尚未把 agent 跑进容器、cgroup 不在本 probe 测、未接任务/claim/准入/消费；末尾保留 TC/major/Gate3。此点合格。本轮不借其对另一个 cgroup probe 的陈述作独立签字。
- **复现参数/清理文字需更正**：该报告写 `--http-proxy=false`，当前 create argv 未带该 flag，实际只过滤了 toolEnv 的 proxy 变量；“OID 级”清理也不符合 `:153` 按随机 containerName rm 的代码（不是按 inspect ID 核身份后删）。随机 nonce/name、只删自己创建对象的意图合理，但不是已证明的 OID/不可替换清理。`unresolved:false` 与“仍未关闭”语义也应统一；本评审不据它关闭 major。
- **same UID 检查健壮性**：sameUIDRewrite 被写入 JSON，但没有独立 assert(true) 加到 checks；提供 JSON 确实 true，故本轮不推翻这次结果。建议断言以避免未来 false 时仍输出固定肯定 claim/成功 exit。

## 结论与执行证据边界

A 的提供证据是作者级 4/4，不是本评审运行；A1 并发交错为静态推演，没有假称实测。B 只有指定派生 JSON/报告及当前脚本，未给逐命令错误原因/原始输出/版本绑定；本评审未启动容器或检查宿主。不能因本轮未执行就把静态切片统称 INCOMPLETE，但硬上限与强隔离证据确实仅 PARTIAL。

**限定结论：A 串行限额与快照内 replay 优先成立、硬并发上限 PARTIAL；B 的同 owner 可写及容器组合有限阻断有支持，九类 EROFS/空卷/完整控制不可达性证据 PARTIAL；新增 A1/B1/B2 三项 P2。无消费/准入/activation/隔离域/全局 C1/Gate3 签字；进程身份/首次 CR 来源未因此验证；旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 major 未关闭；消费 closed/off。**

## 附：发布前文件身份

时间：`2026-10-25T08:55:43.661565+00:00`。A 两文件再次匹配 green2 raw pin；B 三文件再次匹配本轮读取样本，不构成历史运行身份证明。

| 文件 | bytes | raw SHA-256 |
|---|---:|---|
| server/internal/governance/execution_binding_issue.go | 20857 | 785e322d09f8f9b1d11551085dae6cdd3b2adef0ae0a24df6eacfb47698ff164 |
| server/internal/governance/execution_binding_issue_test.go | 40141 | 0fb6e4bcbff69d29afbfeeab5d422d87ddd3c22bd398f1472647a7322595f3f5 |
| C:/Users/GOBAO/Downloads/AI/multica/scripts/aifi45-isolation/trust-root-probe.mjs | 8177 | f2cbbfea24031224f824a064ae4c41f70e47dcb18c6b67bfe27dc5649ed3c82d |
| C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/trust-root-20261025T084600Z-probe.json | 952 | 6b35c762ba8c199ff44a5d3c253615107ad17c14e429bb9724e05f0adf666f2e |
| C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/trust-root-20261025T084600Z-report.md | 3756 | c27ae4df2cc5f4805aecf4e31fb5fda63025989dda5e88780fd543ac99a884bc |

直接 daemon helper 发布时采样（不是 A/B 测试执行 pin 的扩展）：

- `server/internal/daemon/client.go` — 61517 bytes，SHA-256 `916edf84ef90c6749d026a9de7ca478d9e6b788360ddf98ce0ccdbfb68eaa01d`。
- `server/internal/daemon/terminal_report_queue.go` — 37999 bytes，SHA-256 `da15ba13c4a9728613fe64ef75d30e356b0a5450c4676efe3e7b82feb2816f6f`。
