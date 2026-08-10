# CR worktree 的操作位置与 tools 安装基准分离

CR 流程可能在 knowledge-base linked worktree 中读写阶段产物，但同一份 `tools_package_path` 相对值若以 worktree checkout 为基准会失效。CR-2026-028 决定区分 Operational Workspace 与 Installation Workspace：前者决定 CR 文件的读写位置，后者是 knowledge-base 主 checkout，并作为 Tools Root 相对路径的唯一解析基准；linked worktree 通过 Git common-dir 关系找到后者。

不采用改写 worktree 内 `dir-graph.yaml`、创建链接目录或新增 `--tools-root`：前两者制造 checkout 特例，后者形成第二路径事实源。非 knowledge-base 的参与仓 worktree 不猜测对应 CR 上下文，继续使用 requirement-register 已输出的 `knowledge_base_worktree` 显式传入 `--workspace`。
