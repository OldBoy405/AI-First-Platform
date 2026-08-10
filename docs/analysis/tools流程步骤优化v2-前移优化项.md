# tools 流程步骤优化 v2：前移优化项

> 文档定位：从 `tools流程步骤优化v2.md` 的 Phase 2～7 候选路线中，单独抽出的基础路径与入口契约优化。
>
> 当前状态：候选补充，**不并入已在实施中的 Phase 0 / Phase 1 CR**。如需实施，应另立独立 Spec/CR，并与现有 Phase 0 / Phase 1 的改动边界核对。

## 1. 前移原则

这些事项满足以下条件：

- 不需要 Pipeline Runner 或 Skill Runner；
- 直接影响 CR、PRD、SDD、回写等现有 Skill 找到并读取 `tools` 包；
- 可以复用现有 `dir-graph.yaml`、`crctl` 和已有脚本；
- 不新增通用 Runner、动态加载框架或第二套事实源。

## 2. 前移清单

### 2.1 唯一 tools-root 解析契约

来源：主方案 §8.3 Tools root。

以目标 workspace 的 `dir-graph.yaml#workspace.tools_package_path` 为唯一配置来源：

1. 相对路径始终相对于 workspace root 解析；
2. 解析结果必须是实际的 tools 包根目录；
3. 至少验证 `AGENTS.md`、`skills/_index.yml`、`skills/shared/crctl/scripts/crctl.mjs` 等标志文件；
4. 验证失败返回明确的 `TOOLS_PACKAGE_NOT_FOUND`，不得静默继续；
5. 不回退到 workspace 内同名空壳 `tools/`、当前工作目录或调用方 package root；
6. 同一调用链只解析一次并复用结果。

这解决的是包定位问题，不是 Runner 编排问题。

### 2.2 Skill 和脚本入口路径统一

来源：Phase 6 回写脚本、shared crctl 示例及现有 Skill 中的路径写法。

现有部分文档使用：

```text
node tools/skills/...
```

在当前 workspace 中，真实 tools 包位于 sibling `../tools/`。后续应统一为以下规则：

- Skill 文档不得假设 workspace 内存在 `tools/` 子目录；
- 所有需要执行 tools 内脚本的调用，都从统一的 `toolsRoot` 派生绝对路径；
- 文档示例可使用逻辑路径，但必须明确其相对于 tools 包根目录还是 workspace 根目录；
- 回写、crctl、适配器和测试文档不得各自发明路径推导方式。

本项只统一路径契约，不创建新的命令或加载框架。

### 2.3 crctl 的配置加载顺序修正

来源：现有 `crctl.mjs` 的 workspace/config loader；主方案 §8.3 未覆盖这一层实现。

当前 `crctl` 的部分加载逻辑仍直接尝试：

```text
<workspace>/tools/...
<crctl 自身 package root>/...
```

应改为：

1. 读取目标 workspace 的 `workspace.tools_package_path`；
2. 解析并验证 tools root；
3. 从该 root 加载 `dir-graph.yaml`、Pipeline 模板及相关只读配置；
4. 仅在“独立运行且没有 workspace 配置”的明确兼容场景下，才允许使用 crctl 自身 package root；
5. workspace 内同名空壳目录不得作为隐式候选。

状态机、gate 和账本仍由现有 `crctl` 负责，不新增平行 loader 或第二套配置副本。

### 2.4 Registration 复用 `crctl cr-init` 的注册元数据入口

来源：主方案 §8.2 Requirement Register Runner；现有 `cr-init` 已具备相关参数。

`crctl cr-init` 已支持一次写入注册所需的 title、summary、source、target-version 等元信息。现有 `requirement-register` 仍描述注册后直接补写 `cr.md` frontmatter，这会造成入口职责重复。

独立补充 Spec 应明确：

- 注册元数据优先通过现有 `crctl cr-init` 参数传入；
- 不在 Skill 中另行手写受控 frontmatter；
- `cr.md`、`_backlog.yml`、`_index.yml` 的原子建档继续由 `crctl cr-init` 负责；
- 不因为修正入口而新增 `register-preflight`、`registration-check` 或 `stage-context` 命令；
- worktree 创建仍复用现有 `worktree-path` 与 `dir-graph.yaml#repositories`。

## 3. 不在本文件中的事项

以下内容仍保留在后续候选路线中：

- PRD `prepare/finalize` Runner；
- shared Runner library；
- Requirement Register Runner；
- repo/worktree/base context 的完整持久化输出；
- Authoring、Review、Implement、Test、Merge、Writeback、Archive Runner；
- Pipeline typed outputs；
- retry mode、control-plane SHA pin、scope-change ledger、task reconcile 等高级机制。

## 4. 验收边界

独立补充 Spec 至少应验证：

1. 从 workspace 根目录、CR worktree 和其他子目录调用时，均解析到同一 tools root；
2. workspace 内存在空壳 `tools/` 时不会误读；
3. tools root 缺失或标志文件不完整时硬失败；
4. CR、PRD、SDD、回写脚本使用同一条路径规则；
5. `cr-init` 一次完成注册元数据建档，不产生第二次 frontmatter 旁路写入；
6. 现有状态机、gate、审批和账本语义不变。

