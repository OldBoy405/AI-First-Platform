# upstream-sync 证据：**已补齐**（CR-2026-073 TASK-04 / AC-7 上游同步部分）

**更新（2026-09-30）**：Ray 在 AIFI-38 对 B-C2 的裁决为「选 2」——在既有三个提交上重跑同条件全量、
保留未截断原始日志与基线对照；**不执行 merge/rebase、不改 multica 代码**。本轮已按此执行完成。
本文件先前的「原始日志在本机不存在、按 plan §5 处理为未闭合」结论**已被本次实测取代**；
两轮检索的原始记录见本文件末尾「历史说明」，并可从 git 历史取回。

## 本轮实际取得（入口）

| 项 | 位置 |
|---|---|
| 对照报告（机器生成，含全部条数与逐项名单） | `rerun/COMPARISON.md` |
| 索引与复现说明 | `rerun/README.md` |
| 三提交 × 两条件共 6 份未截断套件原始日志 + 迁移日志 + 元数据 | `rerun/cond-a-tasktmp/*`、`rerun/cond-b-shorttmp/*` |
| 逐包条数 / 失败项清单 | `rerun/counts.tsv`、`rerun/counts.json`、`rerun/failure-sets/*` |
| 25 项定向复核（合并前树） | `rerun/cond-b-shorttmp/premerge/03-targeted-merged-only-tests.log` |
| 作废尝试留档（不计入数字） | `rerun/_preflight-aborted-attempt/` |
| 复跑与再生成脚本 | `rerun/scripts/` |

## 对 AC-7 上游同步部分的结论

1. **全量原始日志已具备**：`merged`（`820bb5a11`，第七次同步合并结果）、`premerge`（`95da7c9d7`，合并前 fork 树）、
   `upstream`（`4736a85d4`，纯上游树）各跑一次全量带库 Go 套件（`cd server && go run ./cmd/migrate up`；
   `bash scripts/test-go.sh`，无 `--race`——本机无 gcc），两组临时根条件各一轮；日志未截断，
   每份含命令、cwd、提交 SHA、起止时间、exit code、日志字节数与 sha256（见各 `00-meta.txt`）。
2. **基线与逐项对照已具备**：合并前/纯上游基线与合并结果树**同批同条件**实测，
   并与 `multica/CUSTOM.md`《已知测试失败基线》第七次同步行逐包对照（`rerun/COMPARISON.md` §3），
   与三树同批差集逐项对照（§4）。已知失败**没有**被改成绿色 cmd，也**没有**以子集测试替代全量。
3. **fork 归因**：`merged − upstream = 0`——合并结果树相对纯上游树没有任何额外失败项；
   仅在纯上游树出现的 2 项、仅在合并前树出现的 5 项均为时序/临时目录/任务环境类（§4.2、§4.3、§4.6），
   同类项在两棵 pre-merge 树上各自复现。
4. **未观察面（不得据此声称任何全绿）**：
   - `./pkg/agent/...` 半程未执行：`scripts/test-go.sh` 为 `set -eu`，regular 半程失败即退出——记录中的第七次同步同构，
     故 `pkg/agent` 不在本证据面内；
   - 合并前树的 `cmd/multica` 失败清单**不完整**：该包两次被 10 分钟包超时中止
     （`TestRunDaemonDiskUsageJSONSurvivesServerFailure` 9m53s / 定向复跑 `TestRunDaemonDiskUsageAllProfilesUsesPerProfileToken` 5m0s），
     清单只含中止前已打印的项；合并结果树与纯上游树上这些用例快速失败而非挂起；
   - 本次为**空库**起步，记录那次在累计状态的共享测试库上跑，绝对条数因此有差（`COMPARISON.md` §2、§3 逐条列出来源）。
5. 本目录自始至终**不**声称「上游全量绿色」；plan §5 亦明确本 CR 的普通定向验收不要求上游全量绿色，
   `cmd-08` 只证明保留该规则的文字合同。

## 历史说明（为什么曾经登记为「未闭合」）

2026-09-30 早先两轮检索（`C:\Users\GOBAO\Downloads\AI` 与 `.multica` 深度 6、>100 KB 日志、PowerShell 命令历史、
2026-09-29 之后的 agent 会话记录）确实找不到第七次同步原始全量日志，`CUSTOM.md` 摘要不足以按 plan §5 宣称通过，
故当时按未闭合登记并给出三条补取路径。本轮即其中的路径 2，已执行完毕。
