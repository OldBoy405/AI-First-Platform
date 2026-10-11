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
