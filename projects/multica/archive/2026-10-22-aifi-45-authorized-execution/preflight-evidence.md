# BUILD 组件证据：daemon 调用真实 crctl（非准入）

change：`2026-10-22-aifi-45-authorized-execution`；普通 BUILD；本轮不推进真实 CR、不 commit/push、不部署、不启用模型请求。**完整业务 TC 仍 0/49；major 均未解决。**

## 1. STDD 分工与模型参数

派发前核对 `projects/{tools,multica}/config.d/quality.yaml`：三路 `review.agents` 均存在，但没有 `tier` 或 `model_tiers` 映射。资源包 `stdd/.stdd/config.d/quality.yaml` 的三档 model/effort 也均为空，不能作为项目已配置映射。

遵循 `stdd/.stdd/skills/build.md#C1`：保留代码、测试/配置、文档/Skills 三路独立派发；不传未配置的 model/effort，使用平台默认。**未按型号猜档位、未声称 strong/balanced/economy 已生效、未改用户配置。实际运行模型未取得可核记录，标为 unknown(default)。**

| 职责 | 会话 | 范围与所有权 |
|---|---|---|
| 主线程 | 当前会话 | 安全边界、T 单源合同、生产接线、RED/GREEN、集成验收、全部 CUSTOM 与记录文件 |
| code | `01a167a0-c088-75ce-a57c-1c88116761d2` | 只读代码安全评审；首轮回合耗尽/incomplete，补跑读到源码后给出发现；不据零发现放行 |
| test_config | `01a167a0-f8ee-75ce-a57c-1c8afa2feffd` | 只读测试/配置评审；主线程逐项核实建议，不把建议自动当事实 |
| docs_skills | `01a167a1-2e7c-75ce-a57c-1c8d361f8f1f` | 只读文档一致性；首轮 incomplete，精确路径补跑发现新旧顶层说明矛盾 |

本记录不是 Gate 3/C1–C7 全量完成报告；子代理完成一次回复不等于其全部审查范围已覆盖。

## 2. 本轮运行路径

`daemon.handleTask` 在任何 Agent 启动前调用：

```text
prepareClaimedPipelineTask
  → 原 preparePipelineTask（根/项目归属，legacy 行为保留）
  → 对声明新合同的任务拉取冻结授权，安装到 daemon HOME 的 trust root
  → Client.InstallExecutionAuthorization(ctx, store, crID, workspace)
  → verifyInstalledExecutionGrant（现有 controlled-shell resolver → 真实 node/crctl）
  → authorization-bind --check --trust-root …
  → 对照 op/CR/check_only/bound/current_head_verified/source_verified/digest/文件身份
  → EXECUTION_CONSUMPTION_REQUIRED（不启动 Agent、不写 receipt）
```

只读核验不是授权消费：没有把 `--check`、0700、MDT 持有、进程父子关系或 env 声明当成可信 claim。触发文本合同仍可删除，**不可删除激活 guard 未完成**；旧任务不追溯阻断不代表允许新合同靠删字段降级。

新增真实认证测试使用实际 Auth + workspace membership 签发授权、DB-backed `mdt_` + DaemonAuth 拉取，生产和测试共用 `MountDaemonExecutionAuthorizationRoute`。没有注入 daemon context 或预置 auth cache。由生产 Client 自行运行真实 crctl；原有注入 context 的组件用例仍保留但不冒充完整链路。

## 3. 实际 RED 与根因

| 反例 | 修复前实际结果 | 修复 |
|---|---|---|
| `TestDaemonInstallRequiresRealCrctlContractCheck`：合法签名但 `repair_limit=-1` | 1 RUN / 1 FAIL / exit1，安装返回 nil | 安装方法必须调用真实 crctl，合同无效拒绝返回成功 |
| `TestDaemonInstallRefusesForeignOrForgedRecord/tampered_source_sidecar` | 父子 2 RUN / 2 FAIL / exit1，source digest 不同仍返回 nil | 落盘前比对 source format/digest/bindings，原 bytes canonical base64 与 SHA256 |
| `TestDaemonExecutionDeliveryRejectsOversizedResponse`：有效包外加 4MiB padding | 1 RUN / 1 FAIL / exit1，客户端忽略 padding 后返回 nil | HTTP body 有界读取，超限 `EXECUTION_RESPONSE_TOO_LARGE`，不跟随重定向；既有安装文件先核类型/大小 |
| `TestExecutionTrustRefusesReplacedRoot`：目录改名再同路径 mkdir | 1 RUN / 1 FAIL / exit1，替换根仍被写入 | 记录打开句柄取得的目录身份，安装前复查 |
| `TestClaimedExecutionTaskCannotStartOnRootAttributionAlone`：只有根归属、没有授权 client | 1 RUN / 1 FAIL / exit1，原准备流程返回 nil | 生产 claimed-task 包装入口拒绝缺 client；静态验证通过亦不准入 |
| `TestExecutionVerifierRequiresExplicitNegativeFacts`：verifier 漏发 bound | 1 RUN / 1 FAIL / exit1，缺字段被零值 false 接受 | 三个否定事实用 `*bool`，缺失/null 不等于显式 false；这是响应解析单元检查 |
| 先装首次 POST 记录，再经真实认证 GET 重投同一记录 | 旧 GET 返回 `EXECUTION_TRUST_CONFLICT: …execution-source.json already installed with different content` | JSONB 会重排运输包装；固定 envelope/source 包装编码，原签名 payload bytes 与原人类请求 bytes 保持不变 |
| record 包装重复 schema，最后一个值合法 | 旧安装器返回 nil；和上一反例联合选择 RUN3/FAIL3/exit1 | 复用既有 token scanner，拒重复键、非 UTF-8、多文档；包装固定化前对原/编码对象深比，拒大小写别名或未定义字段；修复后同组合 RUN7/PASS7/0F/0S |

### Windows 根身份调试（失败不改写）

第一次修复保存 `os.Stat(root)` 并稍后 `os.SameFile`，换根负例仍 FAIL。核本机 Go `src/os/types_windows.go` / `stat_windows.go`：路径版 Stat 的 file ID 是在 SameFile 时按路径惰性读取，两个 FileInfo 会读到替换后的同一路径。改为 `os.Open(root)→handle.Stat()→Close()`，先冻结句柄身份；同一真实换根用例 **20 轮 RUN20/PASS20/0F/0S/exit0**。没有依赖目录 symlink 权限，也没有把 directory junction 当成 file-symlink 测试。

目录 pin/包含校验是纵深检查，仍不能抵御同 UID 攻击者在每次检查后继续换路径；不是 OS 权限隔离证据。POSIX 发布后复用目录 fsync；Windows 该既有 helper 是 no-op，不声称获得 Windows 掉电恢复证明。

## 4. 本轮回归（最新，不覆盖历史）

逐测试 RUN/PASS/FAIL/SKIP 事件、完整参数存于 [`preflight-regression.json`](preflight-regression.json)，只保留测试名/动作，未写入凭据或环境。文件文本 SHA256（LF）：`a97d2a7ac06e1c411534f6e88865bfd683ec236e1f5d4347cc20336285b487c4`。

| 范围 | 真实选择参数 | 实际结果 |
|---|---|---|
| governance 扩大 | `-run . -skip '^TestReconcileLiveGitHub$' -shuffle=45045 -count=1 -json` | RUN606/PASS606/FAIL0/SKIP0/exit0 |
| cmd/server 路由 | `-run '^TestMaintenanceRoutesAreAbsentFromPublicServer$|Execution' -count=1 -json` | RUN6/PASS6/FAIL0/SKIP0/exit0 |
| daemon 相关 | `-run '^(TestExecution|TestClaimedExecution|TestMKey|TestGrant)' -count=1 -json` | RUN36/PASS35/FAIL0/SKIP1/exit0；唯一 SKIP 为 Windows 目录 symlink 权限 |

606 是原 598 加本轮 8 个实际事件（真实认证顶层及 4 子例、无效合同、超大响应、source 反例）；daemon 36 是原 33 加换根、claimed preflight、显式否定事实三例。真实认证成功还断言精确授权文件身份，并覆盖缺 verifier 时不得成功；这批新增断言直接 GREEN，不冒称额外业务 RED。早期 588、598 是不同代码/批次，581=578P/3F 为保留的历史失败；不把它们混成同一批次或抹掉失败。动态 table-driven 测试会生成多例，不能用静态 `func Test` / `t.Run` 文本个数反推以上结果。

每次 governance/cmd 测试先复核专用容器 ID `666bfec52ac3…`、change label、127.0.0.1:55432、DB/user，并实际查询 `stdd_aifi45_20261022|stdd`；`DATABASE_URL` 和密码仅在内存，`GOPROXY=off`。

## 5. 评审处置与保留缺口

- 采纳：source 关联、HTTP 有界读取/拒重定向、目录身份与 fsync、真实认证测试、修正过时顶层文档；增量代码审查发现 verifier 缺字段可当 false，已实际 RED→GREEN。增量测试审查要求真实认证成功核精确身份、缺 verifier 拒绝，已补。
- 保留边界：路径 pin 不能解决同 UID TOCTOU；当前不准入，真正权限隔离未解决。测试与生产复用 route helper/DaemonAuth，未启动完整 app 路由图/后台 runner。跨 workspace 负例会检测移除 SQL workspace 条件（会错误取回原记录），但不冒称全部同名 CR/迁移组合已覆盖。
- 不采纳将 T `--check` 的 `source_verified` 改 true：T 单源明定该调用只验静态 grant，daemon 的 source hash 对照不是 T 完整来源验证；继续要求其显式 false。也不采纳假设 `--check` 会输出全部 bindings 导致大包误拒的论断：固定返回形状不回显 bindings。当前 CommandContext/WaitDelay 不是完整孙进程树清理或资源限额证明。
- `go vet ./internal/daemon ./internal/governance ./cmd/server` 与 `go build ./cmd/server ./internal/daemon` 实际 exit0，命令已记入 JSON artifact。
- 不采纳：仅凭静态标题数撤回实际动态事件计数；把必需 DB 测试改为 skip；目录 hardlink 代替 symlink；因只在知识库目录查不到就断言 sibling `multica/CUSTOM.md` 不存在。
- 文档第三轮在其读取版本/指定范围内未见矛盾，不构成 Gate3/C1–C7 通过。之后主线程新增 POST/JSONB 重投与重复包装键两个实际反例，复用 `ValidateExecutionJSON` 收口；最终 regression 包含该修复，但该增量不冒称又经独立代码审查。
- 完整多文件崩溃恢复、历史签名 key 轮换可取回等仍未完成；T 的严格语义/来源读取和消费拒绝保持。
- **仍阻断**：真实 Agent/daemon 隔离运行时未接产品路径，Podman PoC `resourceLimitsEnforced:false`；不可删除 activation、当前授权 head/撤销、真实 DB claim 与各 repo 当前身份回读、独立域 binding 签发、T 消费事务、永久派发/wake/TaskService。
- 本轮未提供任意 nonce 代签端点、未假造隔离能力标志、未配置 manifest/上线开关。后续依顺序实现当前状态回读，但在可信 claim/隔离通道缺失前不能签发绑定或开启消费；major 保持 `resolved:false`。

## 6. 原生记录与工程检查

- 从 sibling `tools/`、`multica/` 的 `.stdd/binding.yaml` 入口运行：两仓 `stdd validate <change>` 均 exit0；原有文件级 AND 警告 T2/M1 保留，不能据此消除 SC/TC 门禁；两仓 `stdd canon verify <change>` 均2/2。第一次误从知识库记录子目录运行得到 `找不到 change`/exit1，是 cwd 错误，不是业务 RED，未改记录路径绕过。
- 三仓 `git diff --check` 均0；变更/新增28个 Go 文件最终 gofmt 无剩余。检查曾发现 `crevents.go` 字段未对齐，以及 `daemon.go` CRLF/导入排序，格式化后重新 go vet/build 均0；这些不记行为 RED。
- 严格 YAML loader 拒重复键：两仓 pending 分别3/2项，每项8字段，全为 major/resolved:false。`.stdd.yaml` 仍 current_phase=build，phases.build.status=in_progress，long_range.enabled=false/mode=normal；未改 Gate1/Gate2 evidence。顶层 status=active 不是阶段状态。
- artifact 事件重计与记录 hash 相符；没有 `server/server.exe` 残留，没有 commit/push、生产启用或真实 CR 变更。`multica/CUSTOM.md` 已登记 #162，M11 为15行（#53、#55–#57、#118、#150、#154–#162）。
