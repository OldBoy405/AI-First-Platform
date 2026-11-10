# AIFI-45 本轮 STDD 模型分层核验

## 有效配置（2026-10-30 历史快照，非当前配置）

用户提醒后，分别在 `multica`、`tools` 根目录运行原生 `stdd config models --format json`：两次均 exit 0、`schema_version=1`、`kind=configured`，三档及其来源一致：

| 档位 | 配置 model | effort | 来源 |
|---|---|---|---|
| strong | `GBClaude/claude-opus-5-5` | `high` | user |
| balanced | `OpenAIPersonal/gpt-6.1-terra` | `high` | user |
| economy | `step/step-5-preview` | `max` | user |

两仓 `model_tiers.design` 和 `retry` 均为 strong。主会话环境报告 provider/model 为 `OpenAIPersonal/gpt-6.1-terra`、reasoning 为 `xhigh`；与配置的 balanced `high` 并非完全同档，不据此宣称命中 model+effort 同档跳过。

## 后续用户纠正

用户明确指出 STDD strong 模型已修改，不再是 Opus；上表和下文 outcome-binding 的配置、会话仅是当时快照，不能当作当前有效配置。本次核实新配置前，误用 plan profile 默认 `GBClaude/claude-opus-5-5:high` 请求了两个只读调查：`01a199c8-f3d6-7468-8217-4d62c9523626`（远端恢复）、`01a199c8-f3c2-7468-8217-4d60f2c1b2b6`（repair）；实际后端均无独立回执，记 `unknown`，不计为当前 strong 档审查或 Gate 证据。两个会话已结束，其意见仅供待核对照，不自动重跑或采纳。当时 strong 的 model/effort 尚未取得有效配置回执；不能再使用旧快照。当前重新核验见下。

## 2026-11-02 当前配置与独立复核请求

用户配置三仓及用户模型分层文件读取后，宿主 `ctx_execute_file` 已分别读到三仓公开文件和用户模型文件（不输出其原文）。使用经预检的 STDD 源仓正式 `python -m stdd config models --format json`，分别以 multica 与 tools 为 cwd：两次均 exit 0、stderr 空、schema 1、kind configured，project_root 对应各仓；两侧有效配置一致，model 与 effort 的来源均为 user：

| 档位 | model | effort |
|---|---|---|
| strong | `OpenAIPersonal/gpt-6.1-sol` | `high` |
| balanced | `OpenAIPersonal/gpt-6.1-terra` | `high` |
| economy | `step/step-5-preview` | `high` |

该调用通过已授权的 STDD 仓 `stdd/__main__.py`，不读取或执行被宿主拒绝的 `C:/Users/GOBAO/bin/stdd.cmd`。环境禁用 Python 用户 site/字节码写入和 Git 全局/系统配置，配置命令调用 Git 只读识别记录根；无生成器、测试、数据库或网络操作。主会话当前 `PI_MODEL` 和 `PI_THINKING_LEVEL` 均未暴露，不声称与某档完全匹配或命中同档跳过。

针对本轮 merge scope 与 repair epoch 组件，按 C1 职责分别请求只读独立复核：strong `01a19a23-0fc1-7468-8217-4d7b923fbbec`，balanced `01a19a23-0fd0-7468-8217-4d7c1d922594`，economy `01a19a23-0fdc-7468-8217-4d7fd5be408f`。请求 model/effort 分别取上表，**请求不等于后端实际模型回执；无回执时 actual=unknown**。完成状态、finding 与复核结果须另核，不能凭启动就标 PASS 或关闭 Gate。

## 本轮偏差及处理

本轮核验前，有只读盘点或草稿作者会话请求了 `OpenAIPersonal/gpt-6.1-sol:high`，不在上述配置的三档，属于流程偏差；不能把这些请求表述为配置的 balanced 或 economy。核验前请求的独立 strong 安全/设计复核使用 `GBClaude/claude-opus-5-5:high`，与两仓 strong 配置一致。以上均是 harness **请求**记录；没有独立 backend 回执，实际 backend 记为 unknown。

已完成的子任务不为凑齐档位重跑；其结论和草稿继续按真实证据及必要的独立 strong 复核处理，不因此视为批准。后续按各任务的 STDD 触发条件选择配置中的档位，不静默改用其他模型；配置档不可用则如实报告或按既定流程处理。普通实现不为凑三档强制委派；人类 Gate 和安全边界不变。

## outcome-binding SPEC 的本次委派

用户确认两侧采用 `thorough`；派发前分别在两个业务根重跑 `stdd config models --format json`，均为 exit 0、schema_version 1、kind configured，design=strong=`GBClaude/claude-opus-5-5:high`，与 balanced 不同。主会话当前无法从可用的 PI 模型/effort 环境字段再次确认 strong，不能按同档跳过。按各 change 各派一个只读 design planner，分别负责 multica 和 tools；请求同为 strong/high：会话 `01a18b6c-b66e-7020-aecc-d4cbbef725c9`（multica）、`01a18b6c-b67e-7020-aecc-d4cd356aa107`（tools）。请求参数不等于后端回执，actual 未证实时为 unknown；不把草案视为 Gate2 批准。
