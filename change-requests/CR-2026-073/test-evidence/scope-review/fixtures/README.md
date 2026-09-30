# U / S / P 快照版本化夹具（CR-2026-073 TASK-04、plan.md §5）

本目录是 plan.md §5「C 项实际评审取证」的**夹具定义**：同一份 SDD/AC（`shared/`），分别以三种证据范围写法提交 `review-dev-plan` 评审。

> ⚠️ 本目录只定义夹具与构建器；**夹具产出的真实 verdict 才是 AC-6/AC-7 的证据**。夹具本身不构成证据。

## 三案

| 案 | CR-ID | 快照内容（相对 `shared/` 只替换 `plan.md` + `tasks/TASK-01.md`） | 期望 `review-dev-plan` |
|---|---|---|---|
| U | `CR-2026-901` | 无已批准全量要求，却把全仓 `make test` 设为关键 `cmd-01`，TASK 完成标志附加全仓绿色 | `verdict=block` + 具体 FR/AC、`cmd-01`、`repair-target=write-dev-plan` |
| S | `CR-2026-902` | 关键 `cmd-NN` 只跑两个定向用例，plan §5 与 TASK 却声称「全量测试通过」 | `verdict=block` + 具体 FR/AC、`cmd-NN`、`repair-target=write-dev-plan` |
| P | `CR-2026-903` | 定向 `cmd-NN` 覆盖 FR/AC，§5 与 TASK 注明「两个定向用例（子集）」且不附加全量 | 不因缺全仓测试被 block |

三案共用同一 SDD/AC（`shared/sdd.md`、`shared/prd.md`），因此三案结论的差异只可能来自证据范围口径。判据来源：`tools` 仓 `skills/develop/review-dev-plan/SKILL.md`「证据范围与定向口径（CR-2026-073 FR-6/FR-7）」一节。

## 构建

```bash
node build-snapshots.mjs --install-root <空目录或已构建的夹具根>
```

- `<install-root>` 必须是**独立目录**（不指向任何业务工作区）：构建器在其中建一个 KB 夹具仓（=`installRoot`，含 `dir-graph.yaml`）与一个 `tools` 夹具仓（`tools-fixture/`），再为三个 CR 各建 worktree（`<root>/.rayai-worktrees/{knowledge-base,tools}/requirement/CR-2026-9xx`）。
- 构建器只做 `git init / add / commit / worktree add` 与文件写入；不触碰任何业务仓、不调用 crctl、不产生平台事件。
- 重复执行等价于重建（先删 `<install-root>` 再跑）。
- 快照 SHA 由构建器输出，随证据一并登记。

## 取证边界（不得省略）

- 快照必须交给**新的独立 `quality-reviewer-agent` task/run** 按 `review-dev-plan` 评审，取证入口为该测试 CR 的 canonical `review-annotations/dev-plan.yml`、`review-loop.yml`、`crctl next` 返回与对应 issue 评论。
- **夹具状态是版本化夹具写出的**（`cr.md` 初始 `status: tech-design-reviewed`，经 `crctl advance --to task-breakdown --trigger write-dev-tasks` 建立可评审状态）；不手改任何业务 CR 的受控 status 或 canonical review。
- 不得拿 CR-2026-073 自身的 plan 评审充当 U/S 案例。
