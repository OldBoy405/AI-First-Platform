# P1 后续修复只读复核：限定接受防误连修补，原 BLOCK 不变

**结论：上一报告 P1 的直接路径——显式 URL 误指普通共享库，TestMain 仍先清理 fixture——在本次五文件快照中已封堵。可限定接受这一修补。**  
但常规 CI 的运行契约尚未适配，不能据此认定所有集成测试兼容、整体安全隔离成立或允许合入。

本轮仅阅读源码、解析已有证据和计算文件 SHA；**未运行测试、未连接数据库、未改文件、未操作 CR**。作者执行不等于复审人实跑。原 BLOCK、非 Gate3、非全项目验收均保持不变。

## 1. 起止 SHA

清单：`validation/testmain-recheck-20261028/source-manifest.json`，位于本 change 根目录下。

**开始、结束均为 5/5 匹配，无漂移；清单本身亦未变。**

以下路径相对 `../multica/`：

| 文件 | 起止一致的 SHA256 |
|---|---|
| `server/cmd/server/integration_test.go` | `899f8ddf7d6ef3328bc11a144295b44635bbc0e79c5e6eb838ae7e2adf83eb21` |
| `server/cmd/server/execution_run_003_test.go` | `ce969f52c4f194baa07d95f43d45dc23d5d687ca71e3f3586ed16c8577b3477e` |
| `scripts/aifi45-db/run.mjs` | `c85721e4959300f15074d02253ab1873b587872637c57d348185dae4808797a5` |
| `scripts/aifi45-db/run.test.mjs` | `12f40625f08f50dfc4cc65ae560308eca11d63673fa7e248508bcb624fd0bb97` |
| `scripts/aifi45-db/README.md` | `48ccb6a67b55eb8f9f2748765bf184c43d13a5fafa9e77e9b1105b81f943eaa2` |

清单 SHA：`f1adc2eac84ac8a3b9a24461f54c74efc588489cac680d4f2897fc8ff7392518`。

这仅固定五文件，不是整个工作树或历史运行的身份认证。

## 2. 门禁位置与检查内容正确

`server/cmd/server/integration_test.go`：

- `:64–68`：连接、Ping 后执行门禁；失败关闭 pool 并 `os.Exit(1)`，**不调用 fixture cleanup**。
- `:70–71`：门禁通过后才发布 `testPool`、执行 setup。
- `:187–189`：setup 仍首先 cleanup，但此时已经通过门禁。
- `:97–99`：测试执行及退出 cleanup 均在初始门禁之后。

`verifyDisposableTestDatabase`（`:110–133`）不是解析 URL 自说自话，而是查询实际连接：

| 项目 | 实现 |
|---|---|
| nonce | 恰好 16 位小写十六进制；非法立即拒绝 |
| 实际数据库 | `current_database()` 必须精确匹配 `aifi45_tmp_<nonce>` |
| 当前、会话用户 | `current_user` 必须匹配对应 role；`session_user` 必须相同 |
| DB owner | `d.datdba = r.oid` 必须为真 |
| 两 marker | DB 与 role 注释均精确等于 `AIFI45_DISPOSABLE:<nonce>`；NULL 转空串后拒绝 |
| 角色属性 | 拒绝 superuser、CREATEDB、CREATEROLE、BYPASSRLS |
| 查询／Scan 错误 | 返回错误，TestMain 拒绝 |

因此，仅提供可连接共享库 URL、仅设置 nonce，或者仅把 URL 写成临时库风格，均不足以通过。

**注意：这是启动时一次检查。退出 cleanup 前没有再次查询身份，也没有逐个验证 pool 后续新建的物理连接。**不能表述成“每次 cleanup／每条连接都重新验证”。

## 3. Harness 的 nonce 不能被普通继承值覆盖

`scripts/aifi45-db/run.mjs`：

- `:76–79`：由 `randomBytes(8)` 生成本次 nonce、数据库名和角色名，不从环境选取目标。
- `:28–40`：先复制继承环境、删除数据库相关配置，再赋值新 `DATABASE_URL`，并在 `:36` **覆盖** `AIFI45_DISPOSABLE_NONCE`。
- `:129–138`：建立受限角色、其拥有的 DB、两 marker，并核对资源身份。
- `:163–173`：核对实际登录和空业务表、验证原 audit 表访问被拒绝，再用上述环境启动 Go。
- `:204–221`：清理前核对 OID／owner／marker，清理后检查两个精确名称均不存在。

`run.test.mjs:27–40` 确有继承 nonce 为 `wrong`、最终必须等于新 nonce 的断言，也覆盖旧数据库配置清除和目标名配对拒绝。**本轮只是静态检查这些 Node 测试，没有执行它们；指定的七组 Go 记录不证明这条 Node 断言被运行。**

Harness 的固定容器／端口、资源创建和清理核对，与 TestMain 门禁是两层控制；不能只凭 TestMain marker 就宣称已经通过 harness。

## 4. 七组作者证据核对

证据位于本 change 的 `validation/todo-a-20261026/`。已对照 stdout、meta、events，重新统计测试事件：

| 证据前缀 | exit | run/pass/fail/skip |
|---|---:|---:|
| `testmain-nonce-red-20261028T085719Z` | 1 | 1/0/1/0 |
| `testmain-nonce-green-20261028T085817Z` | 0 | 2/2/0/0 |
| `testmain-nonce-mut-20261028T085916Z` | 1 | 1/0/1/0 |
| `testmain-nonce-after-mut-20261028T085959Z` | 0 | 2/2/0/0 |
| `testmain-marker-green-20261028T090101Z` | 0 | 3/3/0/0 |
| `testmain-marker-mut-20261028T090215Z` | 1 | 1/0/1/0 |
| `testmain-marker-after-mut-20261028T090310Z` | 0 | 3/3/0/0 |

### RED／变异不是编译失败或未匹配测试

- nonce RED 和 nonce 变异均到达目标断言：
  `wrong nonce reached setup: err=<nil> workspace=false user=false`。
- 子进程故意使用 `-test.run=^$`；其“no tests to run / PASS”**正是旧 TestMain 即使零测试仍清理 fixture 的反例**，不是外层证据未运行测试。
- marker 变异到达：
  `database marker mismatch accepted`，不是 COMMENT 或 setup 失败。

GREEN／恢复后记录均命中预期测试；包含 RUN003 正控，支持门禁没有简单地拒绝一切正常执行。

### 原库与清理：记录一致，但仍是作者自报

七组均：
- 自报 `original_unchanged:true`、原库其他 session／advisory lock 为 0；
- 记录原 audit 表访问拒绝；
- 记录 DB、role 删除及最终均不存在；
- 自报 `owned_resources_cleaned:true`；
- 保存的 **7/7 before/after 文件字节相同**，stderr 均为空。

我确认的是文件内容和记录内部一致性，**不是现场确认原库或资源状态**。这些证据不在五文件 manifest 内；meta 固定迁移 SHA，但没有完整源码／变异补丁／构建产物绑定。因此“变异只改了某条件、随后精确恢复”的历史过程仍依赖作者记录，不能独立认证。

## 5. 已测与仅静态检查必须分开

- **nonce：**`integration_test.go:135–168` 用真实测试二进制子进程，检查非零退出、门禁错误文字及父 fixture 原 ID 仍存在。能发现门禁移到初次 cleanup／setup 之后。
- **DB marker：**`:170–185` 在真实事务内改变 DB 注释，再调用同一 verifier，最后 rollback。它证明该 helper 的拒绝能力，**不是错误 marker 的 TestMain 子进程测试**。
- **仅静态逐字段核查：**role marker、owner、current/session 用户不一致、四项权限、缺失／非法 nonce，以及查询错误路径，未见指定证据逐项动态反例。
- marker 用例接受“任意非 nil 错误”，未先在同一事务验证正常身份，也未限定错误类别；当前源码和变异记录支持目标归因，但测试仍可加强。

RUN003 仍使用固定 `run003-store`（`:348`），并明确保留 append-only 行、依赖每次一次性 DB（`:528–530`）。本次门禁落实了这一前提的一部分，没有将 RUN003 升级成真实 producer／端到端验收。

## 6. 残余阻断与最小后续修复

### P2：常规 CI 尚不兼容，阻断按现状合入

门禁作用于 **整个 `cmd/server` 测试二进制**，不只 RUN003：纯内存测试、零匹配测试也先进入 TestMain。

只读抽查发现：
- `.github/workflows/ci.yml:383` 仍提供普通 `multica` 数据库身份，没有本次 nonce／marker provisioning；
- `scripts/test-go.sh:42–52` 的 regular 包集合包含 `cmd/server`。

按当前配置，该包会在门禁处失败。这是安全收紧带来的确定性兼容代价，不应通过放宽检查、添加裸 `ALLOW_TEST=1`，或给共享库补 marker 来解决。

**最小修复：**为常规 CI／本地集成入口提供同等受控的一次性 DB provisioning，注入新 nonce、受限 owner 和两 marker；必要时将 `cmd/server` 单独运行。固定到本次实验容器的 harness 不能直接冒充通用 CI 方案。

此外，旁证 `testmain-cmd-full-20261028T091336Z` 为 **659/656/3/0、exit 1**：失败是 readiness 父测试及两个 503 子例，不是三个独立业务失败。不能宣称全包绿；也不能仅据此认定是本次门禁新引入。Harness 的 schema-only 克隆不带完整迁移账本，而 readiness 读取该账本，应建立与实际 schema／迁移相符的初始化契约，不能盲填“全已迁移”或改测试接受 503。

### 防误连边界，不是恶意隔离

- nonce 和 marker 不是秘密或不可伪造凭据。能控制数据库／角色元数据和进程环境的操作者，或完整复制身份的克隆库，可以满足这些检查。
- TestMain 没有验证本次资源 OID、创建新鲜度或服务端身份；复用仍存在的旧临时库身份也可能通过。
- 它检查上述四个权限属性，**没有完整验证 replication、inheritance、角色成员关系及有效权限集合**；harness 创建时的限制更强，不能把两者混为一谈。
- 当前单端点、可信 harness 下，未确认新的同等级 P1 绕过。但若未来加入多主机／代理切换、新 pool，或在 package init／门禁前执行写入，现有一次检查不足。届时最小强化是对每条新连接校验，并在破坏性 cleanup 前重核；需要资源实例绑定时再加入期望 OID。

建议补齐逐字段独立负例，尤其 role marker、owner、session 用户和权限；DB marker 用例增加同事务正控与明确错误断言。这些是覆盖补强，不能倒称为当前已测。

## 最终限定判定

**P1 防普通误连修补：限定接受；常规 CI 适配仍待修，完整隔离与全包通过未获证明。**  
旧报告 BLOCK 不变；F2、生产信任边界等不在本轮重审范围，不因本次结论关闭。**非 Gate3、非全项目验收、非生产 PASS。**

遵从本轮禁止改文件要求，报告仅以本最终消息输出，未另写文件副本。