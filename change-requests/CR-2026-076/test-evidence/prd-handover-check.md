# CR-2026-076 PRD 交接完整性核对记录

- 任务：`CR-2026-076-TASK-16`（FR-SUP-09 本 CR 部分；AC-SUP-10）
- 执行时间：2026-10-10（本地）
- 执行环境：`ai-first-platform-docs` CR worktree 根（`cwd=.`，分支 `requirement/CR-2026-076`）
- 命令唯一事实源：本 CR `plan.md` §6.2 证据命令表 `cmd-13` 行（本记录不另写第二套命令，不新增 plan 未列命令）
- 原样输出：`change-requests/CR-2026-076/test-evidence/cmd-13.log`

## 1. 命令（逐字取自 plan §6.2 `cmd-13` 行）

```json
["-e","const fs=require('fs'),cp=require('crypto');const NL=String.fromCharCode(10),CR=String.fromCharCode(13);const LD=p=>fs.readFileSync(p,'utf8').split(CR+NL).join(NL);const bad=[];const B=LD('change-requests/_backlog.yml').split(NL);let inCr=false,prdPath='';for(const l of B){if(l.indexOf('  - id: CR-2026-076')===0){inCr=true;}else if(inCr&&l.indexOf('  - id: ')===0){inCr=false;}if(inCr&&l.indexOf('prd-path:')>=0){prdPath=l.split('prd-path:')[1].split(String.fromCharCode(34)).join('').trim();}}const okFile=prdPath?fs.existsSync(prdPath):false;if(!okFile){bad.push('prd-path 未指向分支内实际文件: '+prdPath);}else{console.log('prd-path='+prdPath+' sha256='+cp.createHash('sha256').update(LD(prdPath)).digest('hex'));}const prd=okFile?LD(prdPath):'';const ids=[];for(let i=1;i<=9;i++){ids.push('FR-SUP-0'+i);}for(let i=1;i<=10;i++){ids.push('AC-SUP-'+(i<10?'0'+i:String(i)));}const cnt=[];for(const id of ids){const n=prd.split(id).length-1;cnt.push(id+'='+n);if(n<1){bad.push('PRD 未见编号: '+id);}}console.log('编号出现次数: '+cnt.join(' '));const ann='change-requests/CR-2026-076/review-annotations/requirement.yml';const at=fs.existsSync(ann)?LD(ann).split(NL):[];if(!at.some(l=>l.trim()==='verdict: pass')){bad.push('需求评审 verdict 非 pass: '+ann);}if(bad.length){console.error(bad.join(NL));process.exit(1);}console.log('cmd-13 ok: prd-path 指向分支内实际文件；FR-SUP-01…09 与 AC-SUP-01…10 逐号存在；需求评审 verdict=pass（实质覆盖由独立需求评审判定，本命令不作正确性结论）");"]
```

- repo：`ai-first-platform-docs`；cwd：`.`；runtime：`node`；timeout：300s
- 行尾纪律：命令内 `LD()` 已做 `\r\n → \n` 归一后才计算哈希与切分（`AGENTS.md` 工程纪律 #1）

## 2. 原样输出（同 `cmd-13.log`）

```text
prd-path=change-requests/CR-2026-076/prd.md sha256=521746b36e53aab0bfc6419e8ee1c4b83292d16a342b00618a064948dbd574c6
编号出现次数: FR-SUP-01=9 FR-SUP-02=9 FR-SUP-03=5 FR-SUP-04=5 FR-SUP-05=7 FR-SUP-06=7 FR-SUP-07=6 FR-SUP-08=5 FR-SUP-09=6 AC-SUP-01=7 AC-SUP-02=1 AC-SUP-03=1 AC-SUP-04=1 AC-SUP-05=1 AC-SUP-06=6 AC-SUP-07=2 AC-SUP-08=3 AC-SUP-09=6 AC-SUP-10=10
cmd-13 ok: prd-path 指向分支内实际文件；FR-SUP-01…09 与 AC-SUP-01…10 逐号存在；需求评审 verdict=pass（实质覆盖由独立需求评审判定，本命令不作正确性结论）
```

- 退出码：**0**
- stderr：空

## 3. 机械事实逐项登记

| 核对项 | 来源字段 | 观测值 | 结论 |
|---|---|---|---|
| `_backlog.yml` 的 `CR-2026-076` 条目 `prd-path` | `change-requests/_backlog.yml` | `change-requests/CR-2026-076/prd.md` | 该路径在当前分支内**实际存在**（`fs.existsSync`=true） |
| PRD 文件摘要（`\r\n→\n` 归一后） | 上项文件 | `sha256=521746b36e53aab0bfc6419e8ee1c4b83292d16a342b00618a064948dbd574c6` | 已记录 |
| PRD 编号保留：`FR-SUP-01…FR-SUP-09` | `prd.md` 文本 | 逐号出现次数 9 / 9 / 5 / 5 / 7 / 7 / 6 / 5 / 6 | 九号**逐号均 ≥1**（未见缺失） |
| PRD 编号保留：`AC-SUP-01…AC-SUP-10` | `prd.md` 文本 | 逐号出现次数 7 / 1 / 1 / 1 / 1 / 6 / 2 / 3 / 6 / 10 | 十号**逐号均 ≥1**（未见缺失） |
| 需求评审判定 | `review-annotations/requirement.yml` | 存在 `verdict: pass` 行 | 该字段原样为 `pass` |

## 4. 边界声明（本记录不产出的内容）

- 本记录只登记上述**机械事实**（命令、原样输出、`sha256`、逐号出现次数、`verdict` 字段原样）。
- 编号出现次数**不构成**「需求内容满足 AC-SUP-01…10」的判定：是否实质满足由独立需求评审（`review-annotations/requirement.yml`）判定，本记录不作正确性结论。
- 本 TASK 不新增任何语义覆盖检查器、不新增 plan §6.2 未列命令、不改动 PRD／`_backlog.yml`／评审证据。
