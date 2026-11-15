# AIFI-45 续建：签名 revoke / 前驱 CAS / T 严格验证

本记录接续 [initial-head 恢复记录](resume-tiered-build-20261024.md)。普通 BUILD / in_progress，不变更既有 Gate/质量配置/绑定，也没有 commit/push/部署/真实业务 CR 授权。完整业务 TC **0/49**、五 major **unresolved**。

## 1. 模型分层执行纠正

用户提醒：同档普通任务不应为展示分层额外外包。按母本规则先判断平台/会话可靠提供的 model+effort；planner/修复升档命中跳过条件时不另派，未知档位不臆测。独立审核与升档是不同判断，非作者 strong 代码、balanced 测试、economy 文档审核仍保留。

早先实际 strong 作者委派是已发生历史，不回改成未派；已让该作者在原子测试/事务安全结束后停止新增开发，保留成果/失败证据并释放 DB。其交接在 M `validation/revoke-report.md`。随后 **T 数字精度 P2 由主会话实现修复**，未另派 strong 作者；当前 strong 子会话仅独立审核。项目恢复 Skill 已同步此纠正。

两仓多次真实 native `config models --format json` 均 exit0/schema_version1/kind=configured；最新模型读取见各仓 `validation/revoke-p2-models.json` 与独立复验 `revoke-independent2-{tools,multica}-models.json`。strong=`OpenAIPersonal/gpt-6.1-sol/high`，balanced=`Gobao/deepseek-flash/max`，economy=`GB-JP/deepseek-flash/high`；参数六项 user 来源，review/design/retry 不改。requested 与各子会话 harness 三键对应；没有后端身份回执，actual 均 unknown。

## 2. 本片实现与协议

唯一合同 [wire §3.2](wire-contract.md)：五键人类 revoke 请求、21键 purpose-specific payload；initial scope/来源 profile 不全局变 optional。§1 是字段词汇非统一必填集，§2 明确 initial14/revoke5 profile；§3.1 标为 initial 第一段快照，不与新段争“当前”。

M：真实 Auth owner/admin、严格 raw JSON/Unicode reason；原 source/payload bytes 签名冻结；CR 行锁内追加 `execution/reject` 历史并以独立前驱 record-ID CAS head，同事务失败回滚。exact actor+raw 已提交 replay 先于新前驱要求，返回原包/时间/UUID，不补 head；不同 actor/raw 冲突。终止 revoke 历史阻止损坏指针回退后重新签发。head 用 repeatable-read 只读快照核 revoke 与所引 initial 签名/source/项目/lineage/revision/部署合同；旧 initial 历史 GET/replay 不复活。

T：严格按 purpose 验 initial/revoke；`authorization-bind --check` 仍只静态检查，显式 `--check --check-source` 才核原 source bytes/digest/对应 profile。输出 purpose，`bound=false,current_head_verified=false`；非 check revoke 在 challenge/写入前 `EXECUTION_AUTHORIZATION_REVOKED`。初始任务仍 `EXECUTION_CONSUMPTION_REQUIRED`，没有 nonce/claim/receipt/Agent 激活新增。

M 生产安装仍取冻结 initial 历史；revoke 互操作仅将真实 HTTP record 安装到**测试临时 trust root**调用真实 Node CLI，不宣称生产 daemon revoke 安装或隔离闭环。

源码：M 语义增量13文件（旧23中7改+6新，联合29），T本片3文件；P2只再改T lib/test，CLI不变。独立快照另含未变的 `execution-transaction.test.mjs`、`durable-tx.test.mjs`，所以T核验5文件不是5份本片改动。精确摘要见 M `validation/revoke-source-manifest.json`、T `validation/revoke-main-static-source-check.json`。CUSTOM **#165 / M11 18行**登记；旧 #163/164 不覆盖。sqlc 附带12份原本 clean 的生成物只有 EOL 差异，另有 `revoke-generated-rewrites.json`，未冒充语义增量、未恢复覆盖其余既有脏改。

## 3. 真实 RED/GREEN 与 P2

M 首条公开真实 Auth HTTP 为 **404→201**，另含严格输入/actor、单 CR 行锁并发、历史插入/head UPDATE 故障、精确 CAS miss 后整事务回滚、丢响应原包重投、损坏前驱与终止历史；原 raw/meta 和中间失败全部保留。丢响应仍只是提交后 `io.ErrClosedPipe`，不是 TCP 断线、进程 kill 或分布式 exactly-once 证明。

T 起初四类公开 CLI RED/GREEN及151/151作者检查见 [作者报告](validation/revoke-tools-author-report.md)。独立审核随后发现数字先舍入/下溢的 P2：`2.0000000000000001`/`1.99999999999999999` 变2，`-1e-1000` 变 -0 再误当0；原151/209绿色不覆盖该反例。

主会话先留 **6 RUN / 0P / 6F / exit1**（全部旧 CLI exit0 错接受），再复用原 token walk 核字符串外数字原 token为十进制安全整数，保留合法 -0，不改 raw、不另写 JSON parser。最小 GREEN **8/8** 含旧 -0 正例；扩展真实 binding 分数 PID/revision 拒绝、MAX_SAFE_INTEGER/数值样字符串后 **11/11**。详见 [P2报告](validation/revoke-integer-token-report.md)，不将重叠用例相加。

## 4. 独立复核与真实复跑

- T strong 非作者 `01a16e02-2ae3-77b9-a3c5-0eb53a155075`：先报 P2，主会话修后 **PASS / F1关闭**；核全部 parser 调用者与 binding 错误包装。其 parser232/232、验签/来源11/11、binding4/4为独立内存组件反例/正例，不是run/pass/fail三元组，也不冒充公开CLI或完整业务TC。
- M strong 非作者 `01a16e14-6c7f-77b9-a3c5-0ebd23d9b646`：**限定本片静态 PASS，0实质 finding**；补核安装/daemon prepare-error立即返回、后续runner/StartTask不可达、新合同不消费、legacy未全阻断；核SQL/Scan/RowsAffected与测试清理。无DB/Go test，不拿作者550作凭据。
- balanced 非作者 `01a16def-4de5-77b9-a3c5-0ead91183bc1`：P2后完整真实复跑，见 [独立报告](validation/revoke-independent2-report.md)、[索引](validation/revoke-independent2-index.json)。

| 范围 | 实际结果 | 限定 |
|---|---|---|
| T auth / transaction / durable-tx 三文件 | **218 RUN / 217P / 0F / 1S / exit0** | 唯一 Windows file-symlink EPERM；不是218/218 |
| M governance组合、shuffle/count2 | **550/550，exit0，0skip** | 包含父子与重复事件，不累计业务TC |
| M 实际 router | **14/14，exit0，0skip** | count2，与其他组重叠 |
| M daemon 拒消费 | **2/2，exit0，0skip** | 不证明已可消费 |
| M真实HTTP→当前T Node CLI | **3/3，exit0，0skip** | 静态check/source-check及revoke拒绑定；不是生产安装/claim |

第一轮 balanced 的209=208P/1S与 M 作者旧T快照互操作均保留，只作历史证据，不取代此轮。economy 非作者 `01a16def-90ee-77b9-a3c5-0eae81150c33` 对 purpose/source profile 消歧及最终整批增量文档均 **PASS，无阻塞性矛盾**；其关于未变两测试、内存检查计数和测试临时 trust root 的非阻塞澄清已采纳。reason词汇和check-source initial14/revoke5亦已补正。

## 5. DB、静态检查及保护

唯一批准专用容器 `666bfec52ac3…a774e823` / `stdd.change=2026-10-22-aifi-45-authorized-execution` / `127.0.0.1:55432` / DB `stdd_aifi45_20261022` / user `stdd`；runner hash/身份在独立 meta。凭据只在内存，GOPROXY off，清无关 tokens，无依赖安装/共享库/生产操作。

完整 history **83→83**，全量ID+内容 hash 前后 identical，missing/added/changed=0/0/0；旧42条 baseline 也未删。未用 created_at 判新增，所有新 revoke 历史按 exact owned id 清理；旧 initial-head fixture仍有其既有 scope 清理，不宣称所有历史测试全改 exact-ID。balanced **13:28:09Z** 确认锁0/其他client0并释放，随后主会话仅运行静态命令，未再连DB。M release见 `validation/revoke-independent2-release.md`。

主会话 static：`go vet ./internal/governance ./cmd/server` exit0；sqlc **v1.31.1** 离线 repeat generate exit0，**78份生成物前后 raw/LF 摘要全部不变**；26份有界Go源码 gofmt无输出，T三源码 `node --check` exit0，scoped git diff-check exit0（含未跟踪源码另做语法/gofmt，不将git diff冒称覆盖未跟踪）。见 M `validation/revoke-main-static-index.json` 与 T `validation/revoke-main-static-source-check.json`。

四份 quality/binding 原bytes hash保持前次值；M29 manifest匹配、T5测试快照稳定；两仓 main/原 HEAD、staged0。未全量重跑 M suite/race、未证明覆盖率/资源隔离、未发布或实跑业务CR。

两仓本段 native `validate` / `canon verify` 四命令均exit0；canon各2/2只是proposal结构核验，不代完整TC。原AND warnings保持T2/M1，见各仓 `validation/revoke-final-{validate,canon}.*`。

## 6. 接续与仍未闭合

本片只补签名撤销链与静态来源判据。可信 DB task claim、每repo当前身份、受保护控制通道/真实隔离、不可删 activation、legacy新合同防降级、T既有消费事务、永久 logical_dispatch_key/adoption/wake/TaskService恢复仍待接通；extend/migrate/sensitive/repair-resume仍拒绝。不因本片绿色关闭任一完整TC/major/slice或进入Gate3。

下一步由主会话核真实 task-claim 数据结构与信任边界，先细化可验证合同/公开 seam；不能提供任意 nonce 代签 oracle，不能把 mdt 持有人或同UID目录权限当可信隔离。实际需要人类审批/权限的节点另行提出；当前不重复索要已批准 BUILD 方向确认。

## 7. 已到达人类环境权限边界：资源隔离

> 本节为配置授权前预检。用户随后已允许配置委派／管理器；最新状态见§8，不能再把配置本身当作未获授权。VM重启仍需单独确认。

本轮在继续前做真实环境预检，不把历史 `resourceLimitsEnforced:false` 当作已修。`podman info` 与保留当前连接配置的 `docker info` 均返回 Podman 风格 `host/store/version` JSON：Linux/amd64、rootless、cgroup v2、manager=cgroupfs、delegated controllers=[]；不能误按 Docker 大写字段读取空值来判断能力。机器列表唯一默认运行环境为 WSL `podman-machine-default`。只读 machine SSH 确认 PID1=systemd、VM根有cpu/memory/pids，但当前用户进程处在non-systemd子树，不能由此推断已委派。

进一步使用已锁定本地 Alpine image、无网络/host挂载/凭据/模型请求、UID1000、只读rootfs、cap-drop/no-new-privileges的**合成资源探针**：指定64MiB、0.25CPU、16pids。`create` exit0且HostConfig显示请求值，实际 `start` **exit125**：`crun: open memory.max for writing: No such file or directory`。因此配置被接受不等于内核强制执行；没有取得内核limit正例，不算业务RED或隔离PASS。仅按本次随机nonce label核所有权后精确删除探针，rm exit0，无镜像pull/VM权限/配置/重启或真实DB操作。

证据：`validation/revoke-next-runtime-preflight.json`、`revoke-next-runtime-docker-schema.json`、`revoke-next-machines.json`、`revoke-next-cgroup-diagnostic.json`、`revoke-next-cgroup-enforcement-probe.json`。要证明真正资源隔离，需人类允许配置当前WSL/Podman的rootless cgroup委派/管理器，或提供其他符合限制的隔离执行环境；不能自行改VM权限、切rootful或重启影响其他容器。这是环境权限请求，不是再次索要已批准业务方向/Gate，也不把其它纯代码工作一并宣称不可继续。消费继续关闭。

## 8. 用户已允许配置；仅重启窗口待确认

配置授权已接受。主会话实测 `--cgroup-manager=systemd` 参数（不落盘）仍 create0/start125，memory.max不存在；systemd及Delegate声明本已存在，真正缺口在上游cgroup。`/non-systemd` 为domain，直属9条PID记录全部为0、当前namespace无法定位，不能当空或盲目迁移上游进程。未触碰全局controller或其他distro。

已经独立于Podman API验证原生WSL入口，并对3份VM配置制作root-owned 0700目录/0600副本；没有修改生效配置或启动任何rootful引擎。当前3容器原ID/StartedAt保持、两库原数据卷保持，未停机、未运行DB SQL。稳妥的下一步是取得本机维护窗口后调整启动层并仅重启`podman-machine-default`，包括API启动异常时的配置回退和必要的再次重启；不做全局`wsl --shutdown`或删卷/删机。

详情、具体3容器影响清单、私有备份路径与原始证据：[授权后诊断与重启边界](validation/cgroup-authorized-20261024T141533Z-report.md)。这不是“资源隔离修复完成”；业务0/49、5major及消费关闭边界不变。

## 9. 维护窗口已执行：内核限额已真实强制

用户已授权该窗口。已按原ID温和停止3容器（exit0、exited、未删、卷保留）→ 写入唯一配置变更 `/etc/wsl.conf` 追加 `[boot] systemd=true`（sha `8a037d60…`→`97fa04e3…`）→ 重启 → 按原ID恢复。`podman machine start` 两次 exit125（第二次另报状态文件 rename Access denied），按预案用原生 `wsl.exe --terminate` 后发行版本体与API已可用。

重启后变量链成立：root `subtree_control=cpuset cpu io memory pids`，`user@1000.service` 有效控制器 `cpu io memory pids`（非“声明”而是实测）。专用库83行、聚合md5 `ced5ac21…`、逐行摘要sha `e39534a2…`，锁0/其它会话0，与维护前一致；3容器running、两库数据卷保留。

生产形态（默认cgroupfs）下的内核强制证据：`cpu.max=25000 100000`、`pids.max=16`（第16个进程 `can't fork: Resource temporarily unavailable`，exit2）、`memory.max=32m` 下写200MiB被SIGKILL（exit137），而 `memory.max=512m` 正例对照同一写操作 exit0 且 `memory.events` oom_kill=0。探针均锁定本地镜像、无网/无host挂载/无凭据，按nonce label精确清理。

**未关闭**：`podman machine list` 仍显示 `Running:false` 且就绪检查报 `ssh error`；容器无自动重启策略，重启后需 `wsl.exe -d podman-machine-default` + `podman start <原ID>` 逐个恢复（本次已走通）。不声称该CLI已修复。资源隔离仅从“环境阻塞”转为“已实证”，业务0/49、5major、消费、Gate3边界不变。详见 [维护结果](validation/cgroup-authorized-20261024T141533Z-maintenance-result.md)。
