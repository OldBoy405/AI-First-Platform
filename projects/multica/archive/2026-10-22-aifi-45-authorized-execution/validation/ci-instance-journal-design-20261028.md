# 独占实例 intent journal：设计与平台阻塞

**状态：设计草稿，不是实现或真实操作授权。** 原 lifecycle 审查 BLOCK、CI BLOCK、TC-RUN-003 与 Gate3 NO-GO 不变。新容器尚未创建。方法论按 `ci-disposable-db-implementation-plan-20261028.md` 任务 1 执行；新模式只能由 `scripts/aifi45-db/run.mjs` 接入，不接受外部实例 ID、URL 或任意命令。

## 需要保证的最小合同

- 在 `engine.create` 前，可信调用方产生固定引擎、批准 image ID、随机 nonce、精确实例名与时间窗；对实例目录执行排他创建，已有目录一律拒绝复用。调用方把与预期配置相关的允许值从固定镜像和显式参数构造，而非从候选 inspect 抄录。
- 意图确认必须意味着完整、不可覆盖的记录已同步，并且承载其目录项已经完成相应的持久化操作；同步返回字面量 `true` 前不能创建容器。同步 `true` 本身只是接口承诺，不是持久性的证明。
- 不保存 `expectedEnv`、target、密码或编码变体，失败只存约束枚举错误码，不持久化任意异常消息/stack。普通日志和引擎 argv 的 secret 防护仍需独立设计与验证。
- 每一事件使用带版本、长度、终止标志及 SHA-256 的不可变记录，严格检查完整 UTF-8 与 EOF；hash 只检测损坏，不建立来源或授权。后续 created/cleaned 记录包括完整 ID 和名称。未知或损坏状态、写失败、已存在目标均不可重试 create 或自动删文件；保留现场并使 writer 永久失败。
- 安全依赖**预先建立且可信**的存储 root 及其祖先不可被不可信主体替换；需按平台验证 owner、权限、ACL/DACL 与链接约束。`lstat`/`realpath` 不能消除同权限并发的 TOCTOU。并发执行使用排他创建、不可覆盖发布和固定身份，不以单纯「先检查再写」替代原子性。

## 拟定写入顺序

1. 在已经持久化且受保护的 root 中排他创建本次目录；对 root 做已验证的目录持久化。
2. 在运行目录排他建立临时记录，验证为预期普通文件；循环完整写入，零进展/非法计数/异常均硬失败；文件 fsync、close 均须成功。
3. 以不覆盖已有目标的原子方式发布（例如已验证的 hard-link no-replace，而非覆盖式 rename），再持久化运行目录。若保留临时硬链接作为现场，不再对其内容写入。
4. 仅所有步骤确认成功时同步返回 `true`；异常点保留已出现的文件，不把不明结果伪装成成功。后续事件也须满足同等合同。

该顺序是待实现并独立审查的设计；是否满足具体文件系统/网络卷及操作系统崩溃一致性，必须分别证明，不能只从 Node API 名称推断。需要真实 `record` 适配 lifecycle，明确后续事件持久化失败时的保留/清理策略。丢失 create 回执需要独立的可信候选发现与身份复核，journal 单独不能证明容器归属或缺席。

## 本机只读临时文件探针（作者）

当前 Node `process.platform=win32`，在系统临时目录下新建独占空目录后，用 `openSync(dir,'r')` + `fsyncSync(fd)` 尝试目录 fsync，结果 **`EPERM: operation not permitted, fsync`**；关闭 fd 并删除该次空目录。未创建容器、未连接数据库、未访问保留库。

**后续纠正与正向对照**：同一主机 `node v26.3.0` 对新建临时空目录的 `openSync(dir,'r+')` 成功；`fstatSync(fd).isDirectory()` 为 true，`fsyncSync(fd)` 也成功，随后关闭 fd 并删除该目录。同一轮对比 `r` 返回 EPERM、`r+` 返回成功。因此先前结果**只证明只读打开的这一调用失败，不能宣称本机 Node 不支持目录 fsync**。两次探针未断电、未验证目录项及祖先链的崩溃持久性、ACL、受保护 root，也未使用真实 journal。

Microsoft 的 [`FlushFileBuffers` 文档](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers) 说明传入文件句柄须具有 `GENERIC_WRITE`，并描述文件缓冲刷新；该页面没有提供本设计所需的独立目录项及祖先目录断电持久性合同。不能据此把 Windows `r+` 的成功扩大解释为完整命名空间 durability 保证，也不能声称绝对无法实现。

因此**不能将忽略目录 fsync 或仅 fsync 普通文件当成持久确认**。Windows 后端须基于真实目录打开权限、受保护 root、操作顺序及相应持久化合同实现并独立验证，否则严格模式 fail-closed；Linux 上的能力亦需在实际文件系统验证。不能将成功返回或文件读回当成断电证明。

## 最小验证与剩余风险

- fake I/O 逐次覆盖短写、零写、ENOSPC/EIO、同步/关闭/link/目录同步失败、目标已存在、并发竞争、污染、异常中断及 writer 后续禁止确认；每项必须独立负例，避免前一个失败遮蔽后续分支。
- 真实文件层需覆盖受保护目录、独占、不覆盖、链接拒绝、权限和进程中断；进程 kill 不是断电测试。目录 fsync 与平台后端要分别记录支持和不可证明项。
- 仿真 crash 区分可见状态和已持久化状态，确保仅在完全确认后允许 create；验证文件中不含 secret 或派生编码。随后冻结源码、独立只读审查，不将作者 fake 结果升级为真实生命周期验收。
- 容器引擎 pinning、inspect 结构、进程树结束、明确 not-found、精确 ID 非 force stop/rm、丢回执 reconciliation、正式迁移与 CI 接线仍未实现。
