# AIFI-45 admission-task-binding 任务清单

## 1. 任务与代次准入及受保护动作（P0，切片 1）

- [x] 1.1 为 `--only` 选择参数写 RED 测试并以最小实现通过；新增本片 TC 的选择。（RED：缺名称和重名均失败；GREEN：Node 5/5，0 skip；atb-001～007 已登记，其余随切片 2 测试加入。）
- [x] 1.2 实现 TC-ATB-001～004：锚点合法性、task/CR/generation 错配、可信链校验及正例；收紧共享 `DecideAdmission`。
- [x] 1.3 实现 TC-ATB-005～007：完成动作（含 retry 子用例）、source fallback、人工门、两条派发；迁移共用 gate 的调用方。
- [x] 1.4 更新受影响既有 fixture（含 TC-RUN-003），保留断言；登记真实 change 至 `CUSTOM.md`。
- [x] 1.5 执行本片 TC、产出物核对及全量 selections，满足 B3.4 才登记切片完成。

## 2. 真实 consumption 与发现（P0，切片 2）

- [x] 2.1 实现 TC-ATB-008：架构和需求真实路由 → 无唤醒 → 两次真实发现，不重复派发。
- [x] 2.2 实现 TC-ATB-009：节点任务运行中经真实路由消费、完成后经发现才推进。
- [x] 2.3 实现 TC-ATB-010：重放及同任务新 generation 不新增 effect 链。
- [x] 2.4 新增 atb-008～010 三个独立 selection，执行本片 TC、产出物核对及全量 selections，满足 B3.4 才登记切片完成。

## 3. 质量验证（P0）

> 以下任务已在返修前执行；SC-ATB-005 修复及受审文档勘误后，需针对当前输入重新核对，历史结果见 test-report.md。

- [x] 3.1 完成三路独立技术评审并处理问题。
- [x] 3.2 执行同次证据计划、全部选择、构建与适用质量检查；只操作本次 supervisor 创建的一次性资源。（返修后全量 292 PASS；当前同次证据 11/11、CI 9 PASS / 1 WARN，详见 test-report.md。）
- [x] 3.3 逐文件审查 diff，执行失败模式检查，登记必要经验与设计偏离。（此前完整评审，加返修聚焦评审及当前 diff/新测试扫描；未验证的真实跨系统边界见 test-report.md。）
- [x] 3.4 写 `test-report.md` 并如实报告上线前真实 daemon + agent 验证前置条件；Gate 3 已于 2026-11-11 19:42:19 由用户重新确认。

## 4. 交付范围与规范处理

- 用户原话：“采纳你的建议，完成当前change所有待完成项，包括 归档、提交、分支合并、推送、清理合并的分支以及过程临时产物。”其中采纳的规范处理方案是：本次 canonical 原样保存在变更归档中，对现有 Human View 主规范做保留历史的语义合并。
- 项目级 canonical 基线当前不存在；本次不重建，也不声称已完成项目级 canonical 合并。这与现行 DELIVER Skill 的项目级 canonical 合并要求有差异；如后续需要集中式机器基线，须单独回溯并校验相关历史。
- 归档前当前证据校验为 11/11；原始 `validation/tc-evidence.json` 保留活动 `changes/` 路径，当前证据校验器不接受归档路径，故归档后不能用该校验器直接复验该记录。未修改原始证据；归档后 Gate 1～3 的锁定输入均经允许归档路径的校验确认为 current。
