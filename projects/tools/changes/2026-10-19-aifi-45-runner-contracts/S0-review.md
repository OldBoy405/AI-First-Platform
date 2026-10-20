# S0 两轴独立审查（最终diff已通过；全量复测已通过）

## 基准与范围

- 固定基准：tools HEAD `a5ecb5783fd8f7b5fa1d0d3b328b704199bbe011`；审查未提交diff，未自动提交。
- 首轮范围：crctl.mjs、test/crctl.test.mjs、test/caller-contract.test.mjs；均位于skills/shared/crctl/scripts/。
- 既有.gitignore改动不属于S0，不计入审查、不得覆盖。
- Spec：canonical/specs/code/test-execution-reliability.yaml，尤其SC-T-TEST-005/006；未将全量或其余AIFI-45能力预判通过。

## Standards

- 独立reviewer结论：无硬规范违规。共享根修复、原fixture安全断言、锚定非可执行提及的白名单均符合既有规则。
- 可选维护性建议：三个新测试重复既有binding三元组，可复用bind3；属轻微主观建议，不因这条建议增加helper或顺手重构。
- reviewer未运行测试，不能把其结论当独立GREEN证据。

## Spec

- 首轮发现1个P2正确性问题：共享authorityWorkspace直接fail/process.exit可能跳过事务清理。修复后两轴均重新审查最终四文件diff，**P2已关闭，无新增硬问题**；不代表全量测试已通过。
- 路径：cmdWritebackPrdSdd将preflightAdvance作为validateBaselineAdvance交给baseline-writeback；旧journal无statusTransition的恢复分支会在lib/workspace-transactions.mjs持锁区再次调用它。若authority此时失效，共享helper直接exit会跳过finally lock.release。
- 这不是放宽信任的理由；要求保留异常栈展开，在安全CLI边界后格式化原分类。未知异常、无绑定容忍、显式override、零业务写入仍须原样保留。
- 修复采用私有WeakSet标记原本要逃逸的真authority TxError后重抛，事务先finally释放锁，再由原适配器或只识别私有来源的CLI末端格式化；无宽泛code/class透传。新增真实journal恢复回归先RED于残留锁，GREEN验证即时解锁、零业务/journal/HEAD/index变化及随后恢复成功。细化记录ADJ-T-001，不改权限/签名/隔离或原错误语义。
- 其余fixture与caller白名单未发现缺失、scope creep或安全断言弱化。最终全量仍pending，不作为本阶段“遗漏缺陷”凑数。

## 进入全量复测的前置

- [x] 修复持锁回调退出边界，补实际恢复/锁释放回归。
- [x] 两轴复核最终四文件diff，阻塞P2关闭，均无新增硬问题；未要求可选bind3重构。
- [x] 主会话独立运行cleanup及非authority错误信任回归：2case/2pass、exit0、11.522s、0skip/cancelled/todo；持久原始证据C:/Users/GOBAO/AppData/Local/Temp/aifi45-s0-main-cj2lod0q/。
- [x] 原完整35文件及新增回归跑完。后台单次调用aifi45-s0-final-run1在209.5738s被0xC000013A终止（用户确认非主动停止，发起方仍未证明），不计通过；改用5个前台顺序批次（同35文件、无过滤/排除）合计875/875 pass、0 fail/skip/todo/cancelled，证据aifi45-s0-run2/b{1..5}.log。详S0-final-report.md、ADJ-T-002。

首轮11/11等是历史定向结果，不能消除当时退出边界问题。修复后的作者结果为定向13/13、writeback8/8、authority34/34、caller16/16、contract83/83；主会话另独立跑关键cleanup/trust两例为2/2。最终全量复测已通过（875/875）；但只能标S0切片完成，四阶段合同/T01–T05与multica消费仍未开工，不禁hook、未连DB、未提交。
