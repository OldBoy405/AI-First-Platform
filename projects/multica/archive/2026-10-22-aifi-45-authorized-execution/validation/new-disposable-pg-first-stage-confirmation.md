# AIFI-45 新 disposable PG：第一阶段确认

## 用户决定与范围

在主会话询问是否批准 [方案简报](new-disposable-pg-decision-brief.md) 的**第一阶段设计与实现范围**、并明确不包含引擎或镜像探针、数据库创建或连接、清理、旧资源访问或 Gate3，真实执行另行审批后，用户原话：

> 批准，继续完成所有未完成的项，中途非必要不要一直中断汇报。子代理委派使用pi-web内置的，遵循llm分层

该确认是 BUILD 中新入口**第一阶段范围的具体变更决定**，不是仅重申原先的 fresh-install A 方向；允许在该范围内继续落实设计和实现。它不是对尚未确定的每项技术细节、资源配置或安全假设的证明，也不是实施完成、业务验收或 Gate3 审批。委派使用 pi-web 内置 `Agent`；已请求模型与实际后端分开记载，没有实际回执时记 unknown。

## 不包含的授权

- 不读取、运行或改向旧 `multica/scripts/aifi45-db/run.mjs`，不读取或连接事故库，不操作既有 HOLD 容器、端口、卷或 `checkpoint-outbox-cli.test.mjs`。一次子代理任务遗漏“不得读取”的限制，导致直接只读该旧 runner；已告知用户并保留[偏差记录](old-runner-read-process-deviation.md)，不追认授权。
- 不探测容器引擎或镜像，不创建、启动、访问或清理真实数据库及相关资源；真实执行的身份、权限、迁移初态、进程/连接退出和精确清理附件须单独批准。
- 不改归档 canonical、`.stdd.yaml`、批准状态或 Gate；不提交、推送或部署，不降低原 TC/验收要求。M006 的历史写入问题不得因本确认被追认为当时合规；`resolved` 仍为 false，后续随 C6/Gate3 审议。
- 纯内存或 fake 验证须逐文件预检其初始化、外部调用、临时文件和清理，并保持与真实资源隔离证据分离；任何尚未获适用批准或安全边界未证明的实际命令仍不运行。禁止依赖默认 URL 或回退目标把 HOLD 误当测试资源。

M006 的人工设计记录已按现行工作区第 7 条精准补记第一阶段决定，未改其 `reason` 历史、其他条目或 `resolved:false`。修改前后用拒绝重复键的 YAML 解析检查了 9 个唯一 ID、必需字段、类型及冲突标记；除 M006 的 `actual_change`/`impact_scope` 外，其余解析后语义摘要一致。这不追认该条历史写入，也不替代资源批准。

独立只读审查会话 `01a1a948-cd44-7374-9f4d-474ce5d3e2d1` 请求 balanced 档 `OpenAIPersonal/gpt-6.1-terra:xhigh`，指出草案 §7 仍把已确认范围内实现写成另行获批；已原位修正为第一阶段范围内实现已确认、真实资源执行另批，同一审查复核认为该 P2 闭合且未见授权夸大。审查未执行测试或 YAML 校验；无实际后端回执时记 unknown。

确认时新实例及测试入口的真实效果均无证据。原迁移兼容、旧行保护、各测试初态、权限、故障恢复及真实清理仍待验证；不把假对象、静态检查或用户决定计为业务 TC PASS。

## 后续离线复核与范围偏差

本轮子代理请求 balanced 档 `OpenAIPersonal/gpt-6.1-terra:xhigh`，实际后端无回执，记 unknown。预检 `selection.mjs` 与 `selection.test.mjs` 后，在空环境用显式 Node 路径执行 `env -i '/d/Program Files (x86)/nodejs/node' ../multica/scripts/aifi45-disposable/selection.test.mjs`，合成数据对账 **21 通过、0 失败、0 skip**，不是数据库或业务 TC 证据。首次直接以 `env -i node` 执行因空环境缺 PATH 返回 127，测试未启动。该代理未修改文件；固定源码／迁移／测试清单和真实实例身份合同仍未完成。

代理读取 `phase-context.md` 时读到了其中事故／HOLD 的历史文字，违反了本次委派中不得读取该内容的限制；据其报告未访问事故数据库、容器或卷，也未打开旧 runner。一次状态输出过长，工具产生临时日志 `C:/Users/GOBAO/AppData/Local/Temp/pi-bash-10a33606a358800c.log`；未读取、清理或推断其内容。
