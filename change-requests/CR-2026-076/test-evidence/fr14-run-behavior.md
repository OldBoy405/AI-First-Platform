# FR-14 run 目标行为证据（plan.md §5.4 第 5 项落点）

来源 run 在**安装环境**留下的目标行为事实：启动绑定归一（FR-01／SDD §4.1）与 Git trust 叠加面（FR-02／D-01）的现场结果。

> **落盘口径**（plan.md §5.4 第 5 行「执行者提供原样事实，dev-agent 原样落盘（不加工、不改写）」）：
> 以下内容为受控采集 run 的**原样回执逐字转录**，未加工、未改写、未判优劣；判定由人工与 `review-code` 消费。
>
> - 来源评论：`01a128dd-e63f-7cba-a31e-f8bec61cc6e5`（Issue AIFI-62 `01a120c6-4681-7c18-ae40-e13067c94ed6`）
> - 采集指令原文：`01a128d7-0ad6-7763-ac2d-df83af0e7ec6`（plan.md §5.4 第 4、5 项受控采集 run）
> - 采集执行者署名（原样）：执行者：`cr-coordinator-agent` `87ca2271-f4d8-4865-aef1-9a24523e1a20` · runtime `dfdfbb04-15da-4235-bf55-9e9935f8e903`（`multica runtime list` 原样：name=`Qoder (DESKTOP-OT18TRG)`，provider=`qoder`，status=online）· model 字段原样 `qfmodel`（`multica agent get 87ca2271-f4d8-4865-aef1-9a24523e1a20 --output json` → `"model": "qfmodel"`，`runtime_mode: local`，`runtime_bound: true`）
> - 落盘：`CR-2026-076` TASK-17；该来源评论的其余段（`## 验收项原样回报`）仍留在上述评论内，本文件不重复。

## 3. 本 run 实际收到的 CR 绑定投影

```
$ echo "$CRCTL_OPERATIONAL_WORKSPACE"
（空行，无字符输出）

$ printenv CRCTL_OPERATIONAL_WORKSPACE; echo "exit=$?"
exit=1
```

`CRCTL_OPERATIONAL_WORKSPACE`：不存在。

绑定三元组逐项探测：

```
$ printenv CRCTL_TASK_AUDIT_ROOT; echo "exit=$?"
exit=1
$ printenv MULTICA_TASK_ID
01a128d7-0b06-70ec-b42c-ad319ffe8316
```

`cr_id`（task 自身关联）：不存在。task 上下文文件全文如下，无 `cr_id` 字段。

```
$ cat .multica/daemon_task_context.json
{
  "managed_by": "multica-daemon-task",
  "agent_id": "87ca2271-f4d8-4865-aef1-9a24523e1a20",
  "issue_id": "01a120c6-4681-7c18-ae40-e13067c94ed6"
}
```

```
$ find "$MULTICA_TASK_CONFIG_ROOT" -maxdepth 3
C:\Users\GOBAO\multica_workspaces_desktop-localhost-8080\ai-first-f33387fe2294\aifi-62-ad319ffe8316\multica-config
$ grep -riE '"(cr_id|cr_ids|issue_cr_ids|operational_workspace|workspace)"' "$MULTICA_TASK_CONFIG_ROOT"
（无输出）
```

`MULTICA_TASK_CONFIG_ROOT` 目录内无任何文件。

`issue_cr_ids`（来源 Issue 关联）：不存在。探测命令与相关原样字段：

```
$ multica issue get 01a120c6-4681-7c18-ae40-e13067c94ed6 --output json
（issue 记录中 cr 相关字段：无；"metadata": {}；"parent_issue_id": null；"status": "blocked"）
```

进程环境全量探测（`env | grep -iE 'CRCTL|CR_ID|MULTICA|GIT_|WORKSPACE|OPERATIONAL'` 命中的全部键，无任何 CR 绑定键）：

```
GIT_EDITOR=true
GIT_PAGER=cat
MULTICA_AGENT_ID=87ca2271-f4d8-4865-aef1-9a24523e1a20
MULTICA_AGENT_NAME=cr-coordinator-agent
MULTICA_DAEMON_PORT=19544
MULTICA_SERVER_URL=http://localhost:8080
MULTICA_TASK_CONFIG_ROOT=C:\Users\GOBAO\multica_workspaces_desktop-localhost-8080\ai-first-f33387fe2294\aifi-62-ad319ffe8316\multica-config
MULTICA_TASK_ID=01a128d7-0b06-70ec-b42c-ad319ffe8316
MULTICA_TASK_SLOT=0
MULTICA_TASK_WORKSPACES_ROOT=C:\Users\GOBAO\multica_workspaces_desktop-localhost-8080
MULTICA_WORKSPACE_ID=30641781-762e-401b-b541-f33387fe2294
PWD=/c/Users/GOBAO/multica_workspaces_desktop-localhost-8080/ai-first-f33387fe2294/aifi-62-ad319ffe8316/workdir
```

命中的判定分支：2d（无关联，普通任务行为不变）。据以判定的原样证据：本 run 的 `cr_id` 与 `issue_cr_ids` 均不存在（上方 task 上下文文件全文、issue 记录无 CR 字段、env 无 `CRCTL_*`）；`CRCTL_TASK_AUDIT_ROOT` 亦不存在，仅 `MULTICA_TASK_ID` 存在。

2d 的直接后果，原样（绑定归一未生效 → `--workspace` 仍必填）：

```
$ node .qoder/skills/crctl/scripts/crctl.mjs status CR-2026-076
{
  "error": {
    "code": "WORKSPACE_REQUIRED",
    "message": "子命令 status 需要显式非空 --workspace <path>（CR-2026-072 起不再接受 CRCTL_WORKSPACE 环境变量或 cwd 隐式根选择）"
  }
}
exit=1

$ node .qoder/skills/crctl/scripts/crctl.mjs next CR-2026-076
{
  "error": {
    "code": "WORKSPACE_REQUIRED",
    "message": "子命令 next 需要显式非空 --workspace <path>（CR-2026-072 起不再接受 CRCTL_WORKSPACE 环境变量或 cwd 隐式根选择）"
  }
}
exit=1
```

`crctl` 不在 PATH 上，crctl 的可执行入口为本 run 已发现的 skill 副本：

```
$ which crctl
which: no crctl in (...)
$ ls .qoder/skills/crctl/scripts/
check-agents-contract.mjs  check-skill-matrix.mjs  crctl.mjs  lib/  lint-prompts.mjs  test/
$ node --version
v24.15.0
```

## 4. Git trust 叠加面

```
$ echo "$GIT_CONFIG_GLOBAL"
（空行，无字符输出）

$ printenv GIT_CONFIG_GLOBAL; echo "exit=$?"
exit=1
```

`GIT_CONFIG_GLOBAL`：不存在。

叠加文件本体：不存在（无 `GIT_CONFIG_GLOBAL` 指向，故无 `[safe] directory=<CR root>` + `directory=<operational>` + `[include] path=...` 三段形状可采）。探测命令原样：

```
$ printenv GIT_CONFIG_GLOBAL; echo "exit=$?"
exit=1
```

git 二进制实际解析（本 run shell 为 Git Bash）：

```
$ which git
/mingw64/bin/git
```

task bin 下存在受控包装器，但不在 `which git` 的命中位置：

```
$ cat "C:/Users/GOBAO/multica_workspaces_desktop-localhost-8080/ai-first-f33387fe2294/aifi-62-ad319ffe8316/bin/git"
#!/bin/sh
exec "D:/Program Files (x86)/multica/resources/app.asar.unpacked/resources/bin/multica.exe" gitguard-exec "C:/Program Files/Git/cmd/git.exe" "cr-coordinator-agent" "$@"
```

用户全局配置本体全文（未被改写，无 `[include]` 段）：

```
$ cat ~/.gitconfig
[user]
	name = OldBoy405
	email = 403562935@qq.com
[core]
	hooksPath = C:\\Users\\GOBAO\\.config\\git\\hooks
[credential "https://gh-proxy.com"]
	provider = generic
[safe]
	directory = C:/
```

```
$ git config --global --list
user.name=OldBoy405
user.email=403562935@qq.com
core.hookspath=C:\Users\GOBAO\.config\git\hooks
credential.https://gh-proxy.com.provider=generic
safe.directory=C:/

$ git config --get user.name
OldBoy405

$ git config --get user.email
403562935@qq.com

$ git rev-parse --git-dir
fatal: not a git repository (or any of the parent directories): .git
```

本 run 当前 cwd：

```
$ pwd
C:/Users/GOBAO/multica_workspaces_desktop-localhost-8080/ai-first-f33387fe2294/aifi-62-ad319ffe8316/workdir
```

## 5. 不存在项汇总（含探测命令）

| 项 | 状态 | 探测命令原样 |
|---|---|---|
| `CRCTL_OPERATIONAL_WORKSPACE` | 不存在 | `printenv CRCTL_OPERATIONAL_WORKSPACE; echo "exit=$?"` → `exit=1` |
| `CRCTL_TASK_AUDIT_ROOT` | 不存在 | `printenv CRCTL_TASK_AUDIT_ROOT; echo "exit=$?"` → `exit=1` |
| task `cr_id` | 不存在 | `cat .multica/daemon_task_context.json` → 仅 `managed_by`/`agent_id`/`issue_id` |
| `issue_cr_ids` | 不存在 | `multica issue get 01a120c6-4681-7c18-ae40-e13067c94ed6 --output json` → 无 CR 相关字段，`metadata: {}` |
| `GIT_CONFIG_GLOBAL` | 不存在 | `printenv GIT_CONFIG_GLOBAL; echo "exit=$?"` → `exit=1` |
| trust 叠加文件 | 不存在（无 `GIT_CONFIG_GLOBAL` 指向） | 同上；`cat ~/.gitconfig` 为本体、无 `[include]` |
| `crctl`（PATH 入口） | 不存在 | `which crctl` → `command not found`；实际入口 `node .qoder/skills/crctl/scripts/crctl.mjs` |
| `git rev-parse --git-dir`（workdir） | 不存在 git 仓库 | `fatal: not a git repository (or any of the parent directories): .git` |

---

# 切换后窗口（2026-10-12）：绑定三元组注入、省略 `--workspace` 的归一、Git trust 叠加

> **本窗口落盘口径**：以下为切换后窗口内两次真实 run 的**原样观测逐字转录**，未加工、未改写、未判优劣；判定由人工与 `review-code` 消费。切换前窗口的既有正文（上方 §3～§5，来源评论 `01a128dd-e63f-7cba-a31e-f8bec61cc6e5`）原样保留，未被覆盖或改写。
>
> - **授权依据**：Ray 选 B——「选 B，接受本次受控采集与原样落盘的角色合并；关于绑定根的，按照当前已通过的方式处理。」由 Issue AIFI-62 评论 `01a12df0-d4e9-7904-8400-2150b1c4b9a9`（2026-10-12T02:28:40Z）逐字转述；本次解除 TASK-17 对**本次事实提供方**的单一角色限制（执行者 = 落盘者），不合并作者与独立评审角色。
> - **采集来源 1（受控采集 run）**：task `01a12dd9-b2be-73ea-b693-42b2ee5a6cdb`（`dev-agent`），原样回执评论 `01a12de2-57af-741a-9bb0-44efb90bab3c`（发布时刻 2026-10-12T02:12:50Z）：该 run 的 `CRCTL_OPERATIONAL_WORKSPACE` = 绑定 CR worktree、显式 `--workspace <绑定根>` 被接受（exit=0）、`workspace inspect --detail` 三仓 `healthy`／`dirty=false`／`operationalWorkspaceError: null`、无 `STATUS_DIVERGED`。
> - **采集来源 2（本续接任务补采的只读观测）**：task `01a12df0-d4f9-73c1-8abe-68da53302132`（`dev-agent`），原始观测时刻 2026-10-12T02:32:36Z–02:33:09Z（UTC）；原始命令与输出逐字转录于 §A～§D。
> - **原始采集时刻 ≠ 落盘时刻**：本节落盘于 2026-10-12T02:34Z（本续接 run 执行窗口内，UTC）。

## A. 本 run 实际收到的 CR 绑定投影（对应上方 §3）

```text
$ pwd
/c/Users/GOBAO/multica_workspaces_desktop-localhost-8080/ai-first-f33387fe2294/aifi-62-68da53302132/worktree

$ printenv CRCTL_OPERATIONAL_WORKSPACE CRCTL_TASK_AUDIT_ROOT CRCTL_TRIGGER_COMMENT_ID CRCTL_TRIGGER_AUTHOR_TYPE CRCTL_TRIGGER_ACTOR_ID MULTICA_TASK_ID MULTICA_AGENT_NAME
C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-076
C:\Users\GOBAO\Downloads\AI\AI First Platform
01a12df0-d4e9-7904-8400-2150b1c4b9a9
agent
a0e71a32-509d-4ee9-aea4-d086a5b1ff93
01a12df0-d4f9-73c1-8abe-68da53302132
dev-agent

$ cat .multica/daemon_task_context.json
{
  "managed_by": "multica-daemon-task",
  "agent_id": "ff6fcbb6-6bb6-42fb-9d88-03493c771411",
  "issue_id": "01a120c6-4681-7c18-ae40-e13067c94ed6"
}
```

触发评论对应关系（原样值，不判归因）：

| 变量 | 本 run 取值 | 与本 run 真实触发评论的关系 |
|---|---|---|
| `CRCTL_TRIGGER_COMMENT_ID` | `01a12df0-d4e9-7904-8400-2150b1c4b9a9` | 与本 run 平台逐 turn 投影给出的触发评论 ID 逐字相同（该评论创建于 2026-10-12T02:28:40Z，作者 `通用智能体`／`cr-coordinator-agent`，内容代为转述 Ray 的选 B 原话） |
| 采集来源 1 的同一变量 | `01a12dd9-b2b1-721f-9dac-d33ee88cecc9` | 与来源 run 的触发评论 ID 逐字相同（原样回执评论 `01a12de2-…` §一自述） |
| `CRCTL_TRIGGER_AUTHOR_TYPE` | `agent` | = 评论作者类型 |
| `CRCTL_TRIGGER_ACTOR_ID` | `a0e71a32-509d-4ee9-aea4-d086a5b1ff93` | = Ray 的成员 ID（该评论系代其发布） |

对照切换前窗口（上方 §3）：`CRCTL_OPERATIONAL_WORKSPACE` 与 `CRCTL_TASK_AUDIT_ROOT` 均**不存在**（`printenv` → `exit=1`），无 `CRCTL_TRIGGER_*`；本窗口三者均存在且值如上。两个窗口的 task 上下文文件**均无 `cr_id` 字段**，来源 Issue 记录均无 CR 关联字段（本窗口现查 `metadata={}`、`parent_issue_id=null`）。

## B. 省略 `--workspace` 的归一行为（对应上方 §3 的 2d 分支）

非 CR 目录之一：task scratch（本 run cwd），原始时刻 2026-10-12T02:32:37Z：

```text
$ crctl status CR-2026-076   # 省略 --workspace，cwd=task scratch worktree（非 CR worktree）
{
  "cr": "CR-2026-076",
  "status": "developing",
  "source": {
    "backlog": "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\knowledge-base\\requirement\\CR-2026-076\\change-requests\\_backlog.yml",
    "backlogSha256": "c837a7de6dc8",
    "crMd": "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\knowledge-base\\requirement\\CR-2026-076\\change-requests\\CR-2026-076\\cr.md",
    "stateMachine": "C:\\Users\\GOBAO\\Downloads\\AI\\tools\\dir-graph.yaml"
  },
  "legalNext": [
    {
      "to": "developing",
      "trigger": "write-test-report:block -> implement-code"
    },
    {
      "to": "developing",
      "trigger": "review-code:block -> implement-code"
    },
    {
      "to": "tech-design-reviewed",
      "trigger": "review-code:plan-blocker -> write-dev-plan"
    },
    {
      "to": "code-reviewing",
      "trigger": "review-code"
    },
    {
      "to": "rejected",
      "trigger": "cr-review-record:reject"
    },
    {
      "to": "withdrawn",
      "trigger": "cr-review-record:withdraw"
    }
  ],
  "reviewLoops": {
    "review-requirement": {
      "current": 1,
      "max": 3
    },
    "review-tech-design": {
      "current": 3,
      "max": 3
    },
    "write-test-report": {
      "current": 2,
      "max": 3
    },
    "review-code": {
      "current": 2,
      "max": 3
    },
    "review-dev-plan": {
      "current": 1,
      "max": 3
    }
  },
  "gateBlockers": {
    "code-reviewing": [
      "code"
    ]
  }
}
exit=0

$ crctl next CR-2026-076
{
  "cr": "CR-2026-076",
  "status": "developing",
  "next": "implement-code",
  "humanApproval": false,
  "why": "代码评审未通过（blockers=4 条），按 blocker 回修后重跑测试再重审"
}
exit=0
```

非 CR 目录之二：项目主 checkout，原始时刻 2026-10-12T02:32:38Z（同形调用，输出除无 `exit` 行外与上段逐字相同）:

```text
$ pwd
/c/Users/GOBAO/Downloads/AI/AI First Platform

$ crctl status CR-2026-076   # 省略 --workspace
（`source.backlog`／`source.crMd` 同上，均指向 KB CR worktree；`stateMachine` = `C:\\Users\\GOBAO\\Downloads\\AI\\tools\\dir-graph.yaml`；`status=developing`；`legalNext`、`reviewLoops`、`gateBlockers` 三段与上段逐字相同）
exit=0
```

`workspace inspect --detail`（原始时刻 2026-10-12T02:32:37Z，节选关键字段原样）：

```text
$ crctl workspace inspect CR-2026-076 --detail
…（三仓 `classification: "healthy"`、`dirty: false`；`changed: false`；`operationalWorkspaceError: null`）
  "operationalWorkspace": "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\knowledge-base\\requirement\\CR-2026-076"
…
exit=0
```

对照切换前窗口（上方 §3）：同形调用（`node .qoder/skills/crctl/scripts/crctl.mjs status CR-2026-076`，省略 `--workspace`）→ `WORKSPACE_REQUIRED`、`exit=1`（2d 分支，绑定归一未生效）；本窗口同形调用 → `exit=0` 且落在绑定 CR worktree 的权威视图。**注：两窗口的 `crctl` 可执行入口不是同一个文件**（切换前 = 该 run 发现的本地 skill 副本 `.qoder/skills/crctl/scripts/crctl.mjs`；本窗口 = task bin shim → 安装态 tools 根副本，见 §C）——本文件只记录两段原样输出，不把差异单独归因于消费者切换或副本差异（两者在本窗口同时变了）。

## C. 本 run 实际执行的 `crctl` 副本与 B-02 消费面（只读实测，原始时刻 2026-10-12T02:32:37Z–02:33:09Z）

```text
$ which crctl
/c/Users/GOBAO/multica_workspaces_desktop-localhost-8080/ai-first-f33387fe2294/aifi-62-68da53302132/bin/crctl

$ cat "$(dirname "$(which crctl)")/crctl"
#!/bin/sh
exec "D:/Program Files (x86)/nodejs/node.exe" "C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts/crctl.mjs" "$@"
```

即本 run 的 `crctl` 实际执行文件 = **安装态 tools 根** `C:\Users\GOBAO\Downloads\AI\tools\skills\shared\crctl\scripts\crctl.mjs`。两侧现查对照（sha256 均为 `\r\n → \n` 归一后内容哈希）：

| 项 | 安装态 tools 根 `C:\Users\GOBAO\Downloads\AI\tools` | tools CR worktree `.rayai-worktrees\tools\requirement\CR-2026-076` |
|---|---|---|
| `git -C <root> rev-parse --short HEAD` | `0f5690f` | `909dfee` |
| `skills/shared/crctl/scripts/crctl.mjs` sha256 | `d6c12c3748cac38e6c42469276e58d3e67745773950d88a5db43b7333d99eec6` | `8798592deb551c9a35449d1baec6ec392f71035f087201345f06fdc7c4d1fc81` |
| 该文件中 `CRCTL_TRIGGER_COMMENT_ID` | 命中 0（不存在） | 存在 |
| 该文件中 `--continue-reason` | 命中 0（不存在） | 存在 |
| `dir-graph.yaml` sha256 | `d93ee4e3895f76d15f1bd5518fb78297276d935a65ef0b2a06b7da6c9f8bc1d3` | `a3bc77efe433086b1256318faaf52417b57592c73eccc8ec58964cdc6b74f392` |
| `dir-graph.yaml` 中 `write-dev-tasks:finalize` | 不存在 | 存在 |
| 工作区状态 | `git status --porcelain`：仅 4 个文件被就地修改（`agent-skill-matrix.yml`、`pipeline-templates/code-implementation.pipeline.json`、`skills/_index.yml`、`skills/develop/review-code/SKILL.md`；`git diff --stat` = 33 insertions(+), 7 deletions(-)），HEAD 仍为 `0f5690f`；四者内容与 tools CR worktree 现有版本**均不相等**；其中 `skills/develop/review-code/SKILL.md` 的内容也不等于触碰该文件的 28 个 CR 分支历史版本中的任何一个（其余三个文件未逐版本比对） | clean（`dirty=false`） |

两份 `dir-graph.yaml` 的全量 `diff` 只差 1 行（`- { from: task-breakdown, to: developing, trigger: "write-dev-tasks:finalize" }`）；本次 `crctl status` 报 `source.stateMachine` = 安装态根 `dir-graph.yaml`，而 CR-2026-076 当前 `status=developing`（已在该转换之后）——**同窗口用两份 `crctl.mjs`（安装态副本与 tools CR worktree 副本）分别执行 `status`，`status`／`legalNext`／`reviewLoops`／`gateBlockers` 四段逐字相同**（两条原样输出已分别核对），故该行差异对本窗口的 `next`／门禁读数无可见影响。

事实层次（不合并，不把未发生的消费写成成功）：

1. 安装态 CLI／daemon 为 `v0.6.1-cr076`（§1、§2 of `fr14-launch-receipt.md`）；
2. 正确 CR 根绑定生效，且省略 `--workspace` 的归一落在绑定 CR worktree（§A、§B）；
3. `CRCTL_TRIGGER_COMMENT_ID` 注入与真实触发评论 ID 逐字对应（§A）；
4. **变量注入不等于安装态 `crctl` 已消费新实现**：本 run 实际执行的副本（安装态根，上行第一列）不含 `CRCTL_TRIGGER_COMMENT_ID`（命中 0）；该变量的唯一消费分支另需 `CRCTL_TRIGGER_AUTHOR_TYPE=member` 且对应 loop 已耗尽，本窗口无合法触达路径（不得为取证执行 `review-loop reset`／`bump`）——本窗口与来源 run 窗口内**均未发生任何 `reset` 消费事件**，所存记录不得被视为该分支成功。

## D. Git trust 叠加面（对应上方 §4，原始时刻 2026-10-12T02:33:09Z）

```text
$ printenv GIT_CONFIG_GLOBAL; echo "exit=$?"
C:\Users\GOBAO\Downloads\AI\AI First Platform\.crctl\task-gitconfig
exit=0

$ which git
/mingw64/bin/git

$ cat <task bin>/git
#!/bin/sh
exec "D:/Program Files (x86)/multica/resources/app.asar.unpacked/resources/bin/multica.exe" gitguard-exec "C:/Program Files/Git/cmd/git.exe" "dev-agent" "$@"

$ git config --global --list
safe.directory=C:/Users/GOBAO/Downloads/AI/AI First Platform
safe.directory=C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/knowledge-base/requirement/CR-2026-076
include.path=C:/Users/GOBAO/.gitconfig

$ git config --get user.name; git config --get user.email
OldBoy405
403562935@qq.com
```

`GIT_CONFIG_GLOBAL` 指向的叠加文件本体（原样全文，5 行）：

```text
[safe]
	directory = C:/Users/GOBAO/Downloads/AI/AI First Platform
	directory = C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/knowledge-base/requirement/CR-2026-076
[include]
	path = C:/Users/GOBAO/.gitconfig
```

用户全局配置本体未被改写（与本文件上方 §4 逐字相同，无 `[include]` 段）：

```text
$ cat ~/.gitconfig
[user]
	name = OldBoy405
	email = 403562935@qq.com
[core]
	hooksPath = C:\\Users\\GOBAO\\.config\\git\\hooks
[credential "https://gh-proxy.com"]
	provider = generic
[safe]
	directory = C:/
```

对照切换前窗口（上方 §4）：`GIT_CONFIG_GLOBAL` 不存在（`printenv` → `exit=1`），叠加文件本体不存在、无 `[safe] directory=… + directory=… + [include] path=…` 三段形状可采；本窗口该变量存在，且指向的文件正是该三段形状（`<审计根>`／`<操作根>`／用户既有 `~/.gitconfig`）。`which git` 两窗口相同；task bin 下的受控包装器两窗口均在（写入方签名由 `cr-coordinator-agent` 变为 `dev-agent`，系本 run 的 agent 身份），均**不在** `which git` 的命中位置。

## E. 不存在项与存在项汇总（本窗口，对应上方 §5）

| 项 | 切换前窗口（上方 §5） | 本窗口 | 本窗口探测命令原样 |
|---|---|---|---|
| `CRCTL_OPERATIONAL_WORKSPACE` | 不存在 | 存在（= 绑定 CR worktree） | `printenv CRCTL_OPERATIONAL_WORKSPACE` → 路径，`exit=0` |
| `CRCTL_TASK_AUDIT_ROOT` | 不存在 | 存在（= `C:\Users\GOBAO\Downloads\AI\AI First Platform`） | `printenv CRCTL_TASK_AUDIT_ROOT` → 路径，`exit=0` |
| task `cr_id` | 不存在 | 仍**不存在** | `cat .multica/daemon_task_context.json` → 仅 `managed_by`/`agent_id`/`issue_id` |
| `issue_cr_ids` | 不存在 | 仍**不存在** | `multica issue get 01a120c6-…` → `metadata={}`、`parent_issue_id=null` |
| `GIT_CONFIG_GLOBAL` | 不存在 | 存在 | `printenv GIT_CONFIG_GLOBAL; echo "exit=$?"` → 路径，`exit=0` |
| trust 叠加文件 | 不存在 | 存在（三段形状，全文见 §D） | `cat "$GIT_CONFIG_GLOBAL"` |
| `crctl`（PATH 入口） | 不存在 | 存在（task bin shim → 安装态 tools 根，见 §C） | `which crctl` |

> **未决范围，本文件不裁定**：安装态 tools 根（含其 `crctl.mjs`／`dir-graph.yaml`／就地修改的 4 个文件）是否纳入本 CR 交付面，属 owner 裁定事项；上表与 §C 只记录本窗口的只读实测值，不视为新增交付项、不视为豁免项、也不视为已验收通过。

