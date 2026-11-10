# 2026-10-29-trusted-verdict-outcome-binding — BUILD 测试报告

> 2026-11-10，长程模式 BUILD（S1 tools / S2 multica）。以下数字均为本轮实测；凡未执行的一律标注「未执行」，不把编译通过写成测试通过。

## 一、结论

| 项 | 状态 |
|---|---|
| S1（T 侧 v2 签发 + 共享向量） | ✅ 完成，测试通过 |
| S2（M 侧单一验签点 + 准入拒绝） | ✅ 完成，组件级测试通过 |
| C4（隔离 PostgreSQL 端到端） | ⏸ 未执行（归 AIFI-45，需要 DATABASE_URL） |
| 生产可用性 | ⛔ 未达成：M 侧仍无生产 producer（`ControlWorker` 未接线），准入保持 `WAIT_TRUSTED_T_COMMIT` |

**只有把「组件级合同 + 拒绝路径」当成目标时，本 change 才算完成。**「新 effect 能被正确放行」这一端到端能力仍缺 S3（单写入者接线，AIFI-45）。

## 二、切片状态

| 切片 | 交付物 | 证据 |
|---|---|---|
| S1 | `verdictPayloadV2`、verdict 12 键闭集校验、`execution-control-verdict/v2`、重算的 `control-vectors.json` | `node --test` 4 个文件 **61 tests / 61 pass** |
| S2 | `VerifyTrustedVerdictEffect`、`DecideAdmission` 追加校验并失败关闭、v2 常量与闭集校验 | `go build ./...` OK；`crosslang_test` OK；无 DB 表驱动测试 3 个 Test / 41 subtests 全通过 |

## 三、TC 覆盖（planned → actual）

| TC | 内容 | 结果 |
|---|---|---|
| TC-VM-003/004/005 | v1 拒绝、effect 非闭集、缺 `command_digest`、多余键、`previous_verdict_digest: null`、digest 与冻结命令不符、scope 不匹配 | ✅ 无 DB 测试覆盖 |
| TC-VM-018 | 准入状态表驱动（可信 effect 通过；其余失败关闭） | ✅ 纯函数层覆盖；SQL 接线只经人工评审 |
| TC-VM-014 | Node/Go 同一向量复现同一 digest | ✅ `crosslang_test/TestSharedControlVectorVerdictParity`（无 DB），digest `7939c063…` 两侧一致 |
| TC-VT-004 | 旧 v1 已签载荷、effect 非闭集、缺键、多余键、非 hex 与大写 digest、scope 不匹配、非安全整数 | ✅ Node 覆盖 |
| TC-VT-007 | v2 构造→签发→验签往返，且与向量逐字节一致 | ✅ Node 覆盖 |
| TC-VM-006/008/010/012（C4） | 单写入者、多入口负例、撤销竞争、重放幂等 | ⏸ 未执行；归 AIFI-45 |
| 上线就绪清单（VM-017/019 运维部分、VT-002/012/015） | key 生命周期、回滚机制、升级在途、签发权威 | ⏸ 未执行；负责人未指定 |

## 四、执行过的命令与真实结果

multica（`server/`）：
- `go build ./...` → exit 0
- `go vet ./internal/governance/ ./internal/daemon/ ./cmd/server/` → exit 0
- `gofmt -l`（改动文件）→ 无输出
- `AIFI45_TOOLS_ROOT=<tools> go test ./internal/governance/crosslang_test -count=1` → ok
- `go test execution_control_protocol.go execution_verdict_trust.go execution_verdict_trust_test.go -run 'TestVerifyTrustedVerdictEffect|TestControlProtocol'` → ok（3 Test / 41 subtests）
- `go test -c` 编译 `./cmd/server`、`./internal/daemon`、`./internal/governance` → 均成功
- **未执行**：任何需要 `DATABASE_URL` 的用例（`TestMain` 直接失败，不跳过），含 `TestTC_RUN_003`、`TestVerdictWriterVerifiesAttestation`、daemon worker/recovery

tools：
- `node --test execution-control-protocol.test.mjs control-operation-domain.test.mjs control-payload-decode-limit.test.mjs control-json-duplicate-keys.test.mjs` → **61 pass / 0 fail**
- 全量 `node --test --test-reporter=tap skills/shared/crctl/scripts/test/*.test.mjs` → 2238 tests / 2078 pass / 40 fail / 120 skipped。
  逐条读取失败名后，40 项全部集中在三类平台门控用例：`isolation 需要真实受限身份`（需 `AIFI45_ISOLATION_PROFILE`）、`memory harness requires VM modules` / `readHash memory tests require VM modules`（需 node:vm 特定能力）、`write-set …` 的 EACCES/EPERM/EIO 注入（Windows 上无法制造这些 errno）。
  本 change 的直接依赖面只有 4 个文件 import `execution-control-protocol`，加上经 store/worker 间接依赖的 7 个文件共 11 个 / 232 例，除上面的 isolation 用例外全绿。**残余不确定**：没有做改动前基线对比，故「这 40 项是既有失败」是按失败名与环境条件推断，不是逐项复现。

## 五、设计偏离

见 `pending-adjustments.yaml`（3 条，均 unresolved）与 `design-adjustments.yaml` 的 REV-1/REV-2/REV-3。最关键的是 REV-3：design 的 v2 字段表（8 键）与既有写入端 subject 绑定冲突，按实现事实改为 12 键。

## 六、已知缺口（逐项）

1. **generation 绑定未实现（G1 部分成立）**
   - 名称：准入为 CR 级判定，未绑定被准入的那一代任务
   - 原因：`AdmissionRequest` 只有 workspace/CR/intent，没有 task/runtime/generation；补上要改接口与调用方
   - 影响：一个较旧的、已通过 v2 校验的 effect 可以让新代次通过准入。该缺口在本次改动前就存在（原查询同样按 CR 聚合），本次只收紧、未放松
   - 补完计划：随 AIFI-45 的 M005（单写入者 + 代次绑定）一起做
2. **准入端不复验签名**
   - 由 `AppendVerdictFrameTx` 在写入时对同一批不可变字节验签；前提是 manifest 来源可信，而 manifest 的可信来源仍属上线就绪清单
3. **隔离数据库证据缺失**
   - 无 `DATABASE_URL`，C4 与 RUN-003 的真实行为未跑；`execution_run_003_test.go` 的夹具已改为经 `ApplyControlCommandTx` 冻结命令并按该字节算 digest，但只在编译层验证过
4. **全量 Node 套件基线缺失**
   - 40 个失败项未逐项归因；不排除其中含与本 change 无关的既有失败
5. **上线就绪清单无负责人**
   - 生产 signer/私钥、manifest pin、隔离重新出证、key 生命周期、升级与回滚策略均未落实；在落实前 M 侧保持失败关闭

## 七、Gate 3 需要的判断

1. 12 键 wire 是否即为目标合同（REV-3）
2. 接受「签名验证在写入端、准入端只做语义与绑定」的分层（REV-1）
3. 接受以 epoch/sequence 代表代次（REV-2）
4. 是否接受在 generation 绑定缺口存在的前提下把本 change 记为 BUILD 完成（缺口已如实记录，且当前失败关闭）

## 八、`stdd validate` 的已知不通过（如实记录）

`stdd validate` 报 `TC 案例数 (N) 少于 Spec Scenario 数 (M)`，两侧各差 1。原因：`specs/trusted-merge-gate/spec.md`
有 3 个 Scenario（SC-MG-015/016/017），而沿用的 AIFI-45 验收只有 TC-MG-015 / TC-MG-016 两例；校验器按
「每个 Scenario 一个 TC」计数，差额正好是 SC-MG-017 没有独立 TC。已把 TCs 归属写入 test-plan §六。
**没有为凑数新建 TC-MG-017**：design 明确「沿用原编号、不增加验收分母」，编一个新 ID 会伪造验收范围。
如需消除该校验错误，应由 AIFI-45 决定是否给 SC-MG-017 单列用例。

另：本 change 的 `test_functions` 只统计本轮新增/改写的测试函数（M 5、T 2），不含既有回归套件。
