# pi 运行环境资源清单

- 核对日期：**2026-09-20**
- 主机配置目录：`C:\Users\GOBAO\.pi\agent`（可用环境变量 `PI_CODING_AGENT_DIR` 覆盖）
- 核对方式：`pi --version` / `pi list` / `~/.agents/.skill-lock.json` / 逐来源仓库 `git fetch --depth=1 --filter=blob:none` + `git rev-parse FETCH_HEAD:<skillDir>` 与 lock 中 `skillFolderHash` 比对 / 本地文件按 git blob 逐文件比对
- 口径说明：本文件只记录**本机实际安装**的资源及其来源仓库；"未升级 / 账实不符 / 待决"统一列在第 9 节，不与安装事实混写

---

## 1. pi 本体与外壳

| 组件 | 版本 | 来源仓库 | 说明 |
|---|---|---|---|
| `@earendil-works/pi-coding-agent` | **0.86.0** | https://github.com/earendil-works/pi | pi 本体；npm 全局安装于 `D:\tools\npm-global`；monorepo 子包 `packages/coding-agent` |
| `@agegr/pi-web` | 0.9.0 | https://github.com/agegr/pi-web | Web UI 外壳（当前会话即跑在其构建产物上） |

- 版本变动记录：本会话开始时为 0.85.1，会话期间（`pi update --extensions` 链路）磁盘版本变为 0.86.0。
- pi 相关文档（扩展 / skills / 主题 / prompt 模板 / SDK / 模型）随本体包发布：`D:\tools\npm-global\node_modules\@earendil-works\pi-coding-agent\docs\`

## 2. pi 包（`~/.pi/agent/settings.json#packages`）

实体目录 `~/.pi/agent/npm/node_modules/`，由 `~/.pi/agent/npm/package.json` 管理（该目录 `.npmrc` 设 `legacy-peer-deps=true`）。

| 包 | 版本 | 来源仓库 | 提供的能力 |
|---|---|---|---|
| `pi-subagents` | **0.70.0** | https://github.com/nicobailon/pi-subagents | 工具 `subagent` / `subagent_supervisor` / `bg_wait`；12 个 agent 定义（`agents/`：`delegate`、`oracle`、`researcher`、`reviewer`、`scout`、`worker`、`codex-exec[-writer]`、`claude-code[-writer]`、`cursor-agent[-writer]`）；skill `council-mode`、`pi-subagents`；6 个 prompt 模板 |
| `pi-mcp-adapter` | **2.34.0** | https://github.com/nicobailon/pi-mcp-adapter | MCP 接入（stdio / HTTP、OAuth、elicitation、UI App、resources）；skill `mcp-scripting`；CLI `pi-mcp-adapter`（`init` / `token set\|status\|remove`）。⚠️ 包资源被 settings 过滤（`pi list` 标 `filtered`） |
| `pi-web-access` | **0.30.0** | https://github.com/nicobailon/pi-web-access | 工具 `web_search` / `fetch_content` / `source_check` / `get_search_content`，40+ 搜索与抓取 provider（Brave、Tavily、Exa、Firecrawl、Jina、Perplexity、Gemini、Kagi、xAI、Mistral、SearXNG、Bright Data…） |
| `context-mode` | 1.0.169 | https://github.com/mksglu/context-mode | 工具 `ctx_execute` / `ctx_execute_file` / `ctx_index` / `ctx_search` / `ctx_fetch_and_index` / `ctx_batch_execute` / `ctx_stats` / `ctx_doctor` / `ctx_upgrade` / `ctx_purge` / `ctx_insight`；8 个 `ctx-*` skill；hooks（含 pi 适配）；以 FTS5 存"已索引内容 + 会话记忆" |
| `pi-background-tasks` | 2.5.0 | https://github.com/ismailsaleekh/pi-background-tasks | extensions：`background-tasks.ts`、`delegate-child.ts`、`fusion-child.ts`、`anthropic-attribution.ts`。⚠️ 包资源被 settings 过滤 |

- 更新方式：`pi update --extensions`。实测该命令只落地了部分包（`package.json` 范围已更新但 node_modules 未装），必要时补 `npm update <pkg>` 于 `~/.pi/agent/npm`。
- 5 个包全部为 npm 发布物，来源仓库即上表 URL（`package.json#repository`）。

## 3. 本地扩展（非 npm，绝对路径挂载）

挂载点：`~/.pi/agent/settings.json#extensions`。

| 路径 | 版本控制 | 来源仓库 | 说明 |
|---|---|---|---|
| `~/.pi/agent/extensions/ponytail-always.ts` | 无 | —（本机自写） | `before_agent_start` 钩子：本地关键词启发式判定"本轮是否代码任务"，命中才注入 ponytail 全文（约 2K tokens/轮） |
| `C:\Users\GOBAO\Downloads\AI\tools\output-guard\adapters\pi` | 有 | https://github.com/OldBoy405/AI-First-tools | AI/tools 方法论包的 output-guard 适配层：`tool_call` 拒绝/改写 + `tool_result` 裁剪封顶 + `complete=false` trailer。2026-09-20 与 `origin/main` 完全同步（`3bf19dd`，0 ahead / 0 behind） |
| `C:\Users\GOBAO\Downloads\AI\pi-extensions` | 有（本地仓 = 远端：`main 9019d34`、tag `v1.0.1`；v1.0.0 = `ff83f71`） | https://github.com/OldBoy405/pi-extensions | shell 工具未显式传 `timeout` 时补 `300` 秒（**显式值优先**），并在**每进程首次注入**时写一行 stderr（`PI_SHELL_TIMEOUT_INJECTED seconds=300 tool=bash`）供 daemon 日志取证。**当前生效的就是这一份** —— 2026-09-20 已按 `pi install git:github.com/OldBoy405/pi-extensions@v1.0.1` 装入，pi 自己 clone 到 `~/.pi/agent/git/github.com/OldBoy405/pi-extensions`；新机器同一条命令即可。自检：`node ~/.pi/agent/git/github.com/OldBoy405/pi-extensions/extensions/pi-shell-timeout.ts --selfcheck`（13 项）。命名口径：仓名 `pi-extensions`（复数，可容纳后续扩展），包内 `name` 仍为 `pi-shell-timeout`、扩展文件仍是 `extensions/pi-shell-timeout.ts` —— git 安装的去重身份是**仓库 URL**，与包名无关（旧名 `pi-shell-timeout` 从未建仓，404） |

- **装载面更正**：本节的挂载点不止 `settings.json#extensions` —— pi 还会**自动加载发现目录** `~/.pi/agent/extensions/` 下的 `.ts`/`.js`。`ponytail-always.ts` 与 `pi-shell-timeout.ts` 都属于这一种（settings 里没有它们）。注意 `pi list` **只列 `packages`、不列散装扩展**，所以散装扩展“在不在”要靠文件存在 + 自检，不能靠 `pi list`。
- **不要双挂（已实测，非推测）**：pi 的作用域去重按身份 —— git 包认「仓库 URL（不含 ref）」、本地路径认「解析后的绝对路径」。散文件与 git 包**是两个身份**。2026-09-20 用可区分的加载标记实测：两份同时存在时 **两个标记同时出现**（双挂成立，第二次见 `timeout` 已设即跳过，无害但不整洁）；删掉散文件后只出现包标记（单挂可用）。因此**散文件已于 2026-09-20 删除**，备份留在 `C:\Users\GOBAO\fr2-artifacts\pi-shell-timeout.loose-backup.ts`（7064 B，sha256 `301f0541…`，与包内副本逐字节相同），需要时可恢复。
- 本地路径形态的 `pi install` 实测（2026-09-20）：写入 `settings.json#packages`（**不是 `extensions`**）并转成相对路径；`pi remove` 能清干净（内容逐条复原，仅重排 JSON 排版）。

## 4. MCP 服务器

- 当前**无**：原 `feishu-docs`（`https://ai.gobao.cn/mcp-servers/feishu-docs/mcp`，bearer，7 个工具 `search-doc`/`fetch-doc`/`list-docs`/`create-doc`/`update-doc`/`get-comments`/`add-comments`）已于 2026-09-20 从 `~/.pi/agent/mcp.json` 与探测缓存 `~/.pi/agent/mcp-cache.json` 中删除。
- 该网关 Key 同时作为 `models.json` 中两个 provider（`https://ai.gobao.cn/v1`、`https://ai.gobao.cn`）的 `apiKey`，故未一并清理。
- 其他 harness（Claude Code / Cursor / Codex / Gemini）均未挂载同一 server；`pi-mcp-adapter` 的 host-config 自动发现未开启。

## 5. 技能（62 个）

### 5.1 加载根与账本

- pi 的全局技能根（官方发现顺序）：`~/.pi/agent/skills/`（60 项）与 `~/.agents/skills/`（61 项）；前者绝大多数是指向后者的软链。
  - 只在 `~/.pi/agent/skills/`：`pdf`
  - 只在 `~/.agents/skills/`：`graphify`、`karpathy-guidelines`
- 全局账本：`~/.agents/.skill-lock.json`（`version: 3`，74 条记录）。项目级账本为 `skills-lock.json`（本机未使用）。
- 账本 74 条 = **61 条在装且与远端一致** + 12 条"有账无文件"（obra/superpowers）+ 1 条本地 fork（graphify）。

### 5.2 来源仓库 × 技能

| 来源仓库 | 数量 | 技能 |
|---|---|---|
| https://github.com/mattpocock/skills | 37 | `ask-matt`† `claude-handoff` `code-review` `codebase-design` `diagnosing-bugs` `domain-modeling` `git-guardrails-claude-code` `grill-me`† `grill-with-docs`† `grilling` `handoff` `implement`† `implement-spec`† `improve-codebase-architecture`† `loop-me`† `migrate-to-shoehorn` `prototype` `research` `resolving-merge-conflicts` `retro`† `scaffold-exercises` `setup-matt-pocock-skills`† `setup-pre-commit` `setup-ts-deep-modules`† `tdd` `teach`† `to-questionnaire`† `to-spec`† `to-tickets`† `triage`† `wait-what`† `wayfinder`† `wizard` `writing-beats`† `writing-for-agents` `writing-fragments`† `writing-shape`† |
| https://github.com/obra/superpowers | 14 | 在装 2：`systematic-debugging` `writing-plans`；账实不符 12（见第 9 节） |
| https://github.com/Leonxlnx/taste-skill | 13 | `brandkit`† `design-taste-frontend`† `design-taste-frontend-v1`† `full-output-enforcement`† `gpt-taste`† `high-end-visual-design`† `image-to-code`† `imagegen-frontend-mobile`† `imagegen-frontend-web`† `industrial-brutalist-ui`† `minimalist-ui`† `redesign-existing-projects`† `stitch-design-taste`† |
| https://github.com/DietrichGebert/ponytail | 6 | `ponytail` `ponytail-audit`† `ponytail-debt`† `ponytail-gain`† `ponytail-help`† `ponytail-review` |
| https://github.com/Graphify-Labs/graphify | 1 | `graphify`（本地为 Windows 改版 fork，见第 9 节） |
| https://github.com/multica-ai/andrej-karpathy-skills | 1 | `karpathy-guidelines` |
| https://github.com/tavily-ai/skills | 1 | `tavily-search`† |
| https://github.com/openai/skills | 1 | `pdf`† |

`†` = user-only（`disable-model-invocation: true`，只能 `/skill:<name>` 手动调用，不进模型可见列表）。

### 5.3 可见性口径

- 模型可见 **21** 个：`code-review` `codebase-design` `diagnosing-bugs` `domain-modeling` `git-guardrails-claude-code` `graphify` `grilling` `karpathy-guidelines` `migrate-to-shoehorn` `ponytail` `ponytail-review` `prototype` `research` `resolving-merge-conflicts` `scaffold-exercises` `setup-pre-commit` `systematic-debugging` `tdd` `wizard` `writing-for-agents` `writing-plans`
- user-only **41** 个（上表 `†`）。
- 其中 **19 个的关闭标记是本机加上去的**（由 pi-web 面板写入 frontmatter 首行，形如 `---` 后紧跟 `disable-model-invocation: true`），另 22 个是上游自带该标记。重装技能会抹掉这 19 个本机开关，更新后需重新插回。

## 6. 模型 provider

- 配置文件：`~/.pi/agent/models.json`（13 个 provider：`2xAPI-GPT0.08` `2xAPI-GPT0.1` `2xAPI-GPT0.18` `EC-Gpt0.1` `EC-Grok0.2` `OO-GPT0.09` `OO-Grok0.15` `OO-ZG0.4` `OpenAI` `Gobao` `GBClaude` `ATRIA` `GB-JP`）
- 默认：`GB-JP/deepseek-flash`，`defaultThinkingLevel: max`；`enabledModels` 13 组 glob
- 入口网关：`https://ai.gobao.cn`（自建，与已删除的 MCP 共用同一 Key）

## 7. 非 pi 的全局 npm CLI（附录，来源仓库备查）

| 包 | 版本 | 来源仓库 |
|---|---|---|
| `@earendil-works/pi-coding-agent` | 0.86.0 | https://github.com/earendil-works/pi |
| `@agegr/pi-web` | 0.9.0 | https://github.com/agegr/pi-web |
| `openwiki` | 0.3.3 | https://github.com/langchain-ai/openwiki |
| `tushare-mcp-server` | 1.0.2 | https://github.com/erwanjun/tushare-mcp-server |
| `zcode-acp-server` | 0.21.0 | https://github.com/william0wang/zcode-acp |
| `@alibaba-group/open-code-review` | 1.9.6 | https://github.com/alibaba/open-code-review |
| `@dbx-app/mcp-server` | 0.4.66 | https://github.com/t8y2/dbx |
| `@qoder-ai/qodercli` | 1.1.47 | 无公开仓库（产品页 https://qoder.com/cli） |
| `@tencent-ai/codebuddy-code` | 2.151.0 | https://cnb.cool/codebuddy/codebuddy-code（非 GitHub） |
| `pnpm` | 11.22.0 | https://github.com/pnpm/pnpm |

## 8. 更新与核对方法

```bash
# --- 技能：列出 / 更新（官方 skills CLI，skills.sh） ---
npx skills ls -g
npx skills update <skill...> -g -y      # 只更新指定技能，避免误伤本地 fork

# --- 技能：核对远端是否有新版（走 git 协议，不触发 GitHub API 限流） ---
T=$(mktemp -d) && git init --bare "$T"
git --git-dir="$T" fetch --depth=1 --filter=blob:none --no-tags \
    https://github.com/<owner>/<repo>.git HEAD
git --git-dir="$T" rev-parse FETCH_HEAD:<skillDir>   # 与 lock 的 skillFolderHash 比对

# --- pi 本体与包 ---
pi --version ; pi list
pi update --extensions                  # 必要时于 ~/.pi/agent/npm 补 npm update <pkg>
```

更新技能前必做的两件保护：

1. `tar` 备份 `~/.agents/skills` 与 `~/.agents/.skill-lock.json`（无 VCS 兜底），更新后按文件逐一 diff，确认只动了目标技能。
2. 记录本机插入的 `disable-model-invocation: true` 开关清单，重装后按原格式（frontmatter 首行）插回。

## 9. 已知偏差与待决

1. **graphify 是本地 fork**：本地 `SKILL.md` 为 Windows 改版（`name: graphify-windows`，653 行/34 KB，带 `.graphify_version: 0.8.39` 与 `references/` 7 篇），上游 `Graphify-Labs/graphify`（默认分支 `v8`）的 `graphify/skill.md` 为 714 行，且该路径是**整个 Python 包目录**。执行 `skills update` 会把 fork 替换成上游整包，因此账本中该条**故意不写 `skillFolderHash`**（`canCheckForUpdates=false`），也未纳入本轮更新。
2. **obra/superpowers 账实不符 12 条**：`brainstorming` `dispatching-parallel-agents` `executing-plans` `finishing-a-development-branch` `receiving-code-review` `requesting-code-review` `subagent-driven-development` `test-driven-development` `using-git-worktrees` `using-superpowers` `verification-before-completion` `writing-skills` —— lock 有账、磁盘无文件。重新安装会新增 12 个模型可见技能（每轮 prompt 变长），故未擅自安装；待定：装回 or 清账（`npx skills remove ... -g`）。
3. **pi 0.86.0 已落盘但当前会话进程仍运行旧代码**，需重开会话生效。
4. **依赖告警**：`~/.pi/agent/npm` 有 1 个 high（`fast-uri` 间接依赖，SSRF/IDN 类，`npm audit fix` 无法自动修复，需 `--force` 破坏性升级），未处理。
5. `pi-mcp-adapter` 与 `pi-background-tasks` 的包资源被 `settings.json#packages[].{extensions,skills,prompts,themes}` 过滤，`pi list` 标 `filtered`；如需启用其自带 skill/prompt，用 `pi config` 打开。
6. **pi 本体是打过本地补丁的 `0.86.0`，与上游同名同版本但字节不同（账实不符）**：`pi-coding-agent` 的 `dist/core/tools/bash.js` 加了“未显式传 `timeout` 默认 300 秒”并改写 schema 文案（sha256 `2a51711b…cabbd`）；`pi-agent-core` 多了 `shell-defaults` 导出入口（`DEFAULT_SHELL_TIMEOUT_SECONDS = 300`）、`dist/shell-defaults.js`，以及 `dist/harness/tools/bash.js` 的工具层解析。上游提案 `earendil-works/pi#9798`（`untriaged`，关联 `#9785`/`#9770`）通过前，这份补丁需跟着每次升级重放；可移植件 `C:\Users\GOBAO\fr2-artifacts\fr2-both-commits.patch`（`git am` 实测能逐字节还原）。**被 `pi update --extensions`、`npm update -g`、`npm i -g @…@latest` 静默冲掉**。验证：`node C:\Users\GOBAO\fr2-artifacts\fr2-verify.mjs` → `FR-2 PRESENT`。免补丁的等价路径见 §3 的 `pi-shell-timeout` 扩展。**覆盖面**：补丁与扩展都只覆盖 **CLI 路径**；harness 路径（pi-server／pi-chat／Gondolin 等 embedder）当前从本机运行时不可达，是否处理及三条不改上游的手段见第 8 条。
7. **`pi-shell-timeout` 扩展：加载已实测；效果取值已就位、待下一个任务。** 2026-09-20 用临时加载标记（注入后按字节复原，sha256 未变）实测：扩展在 pi **启动时被调用**，且两种状态都验过 —— 散文件与 git 包同时挂载时**两个标记同时出现**（双挂成立），删掉散文件后只出现包标记（单挂可用）；自检 13/13（含“一次一报”断言）。**效果本身尚无观测值**：真实 bash 调用是否真被注入 `timeout: 300`。试过 `multica issue run-messages <task-id>`（chat 任务不带 `--issue` 也能读）—— `tool_use` 行的 `content` 为空，**该 CLI 不暴露工具入参**，这条路验不了。为此 v1.0.1 已加“每进程首次注入写一行 stderr”（`PI_SHELL_TIMEOUT_INJECTED seconds=300 tool=bash`）——装完后**下一个任务**即可从 daemon 日志取值：`Select-String -Path "$env:USERPROFILE\.multica\profiles\desktop-localhost-8080\daemon.log" -Pattern PI_SHELL_TIMEOUT_INJECTED`（daemon 把 pi 的 stderr 捕获为 `pi:stderr`）；出现该行即效果闭环，不出现则说明扩展未生效。因为“加载失败只记日志、agent 继续”，升级 pi 后应复跑自检并查扩展加载错误。
8. **harness 路径的 timeout：当前判定「不动手」（2026-09-20 实测）。** 补丁与 §3 的扩展都只覆盖 **CLI 路径**。harness（`packages/agent/src/harness/**`，服务 pi-server／pi-chat／Gondolin 等 embedder）的 shell 工具把 `timeout` 交给 `ExecutionEnv`，而 `NodeExecutionEnv` 对 `undefined` 返回 `undefined`（不挂 timer）；契约文本本身就是 “Defaults to no timeout”。**该路径从本机运行时不可达**，四条证据：Multica 用 `pi -p --mode json --session <path>` 一次性调用；`cli/args.ts` 的 `case "…"` 子命令列表为空、无任何 flag 能进 harness；`modes/rpc/{rpc-mode,rpc-client}.ts` 对 harness 提及 0；非 `experimental/` 源码里唯一 harness 字样是 `core/system-prompt.ts:147` 的提示词文本。bundle 中出现的 `AgentHarness` 只是 barrel（`export * from "./harness/agent-harness.ts"`）拖进的死重量（消费方 micro／mini／session-worker 均不在 bundle 内）。真要覆盖时，**三条路都不改上游代码**：① 在构造点注入有界 `ExecutionEnv` —— `class X extends NodeExecutionEnv { override async exec }`（上游自己的测试就是同形，共 6 个子类），接缝在调用方（`createMicroTools(env)` 这类接口本就接收 env，`NodeExecutionEnv` 与 `ExecutionEnv` 均公开导出）；② 把上界放在**进程／沙箱层**（microvm 额度就是天然上界；本机 run 另有 daemon 的 2 小时 idle/tool watchdog 兜底，粒度粗但不会无界）；③ **上游修** —— 即第 6 条补丁的第二半，把默认值放在**工具层**所以每一种 `ExecutionEnv` 实现（含别人的 embedder）都会收到真实数字。**动手触发条件**（不是“总觉得不放心”）：开始跑 pi-chat／pi-server／任何 harness host；或 `pi` 出现能进 harness 的子命令；或某台机器上 `fr2-verify.mjs` 类判据不再适用。在此之前不为不可达路径加 guard 或立 CR —— 那只会增加永久维护面。

---

最后核对：**2026-09-20**（技能 74 条账实比对 + 4 个技能更新 + 5 个 pi 包升级 + feishu-docs MCP 下线后的状态）
