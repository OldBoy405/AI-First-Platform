# Spec: ci-credential-and-frontend-typecheck

> Change: 2026-11-19-delivery-quality-baseline | Auto-generated Human View

## Requirements

### Requirement: 不放宽现有规则，恢复正式前端 lint、类型检查和单元测试；原有 UI 状态和交互保持不变。

#### Scenario: SC-DQB-CCF-001

- **GIVEN** 干净候选按锁文件安装依赖，并启用现有视图 lint 及无障碍规则。
- **WHEN** 运行 pnpm lint、pnpm typecheck 及 pnpm test。
- **THEN** SHALL lint 与 typecheck 退出 0 并实际执行 views 的三个任务；现有规则下 lint 无错误；pnpm test 的失败用例全部落在声明的上游已知红文件集内，无集外新失败。
- **AND** 相关组件 SHALL 使用现有安全的 UI 图标接口，保持状态含义；presenter 图标按钮 SHALL 有可访问名称且点击仍执行原动作。
- **AND** 上游已知红 SHALL 以 6 个 Views 文件的文件级清单声明；不修改上游测试或产品、不放宽 lint 规则、不调测试超时。清单外任何新失败 SHALL 使门禁红；文件级例外不证明清单内无新回归。
- **AND** 测试任务 SHALL 完整执行；其他任务失败、进程异常、Vitest 未处理异常或结果不完整 SHALL 使门禁红，不因同时存在清单内失败而放行。

### Requirement: 项目质量配置须明确且实际通过必跑浏览器路径，不依赖既存服务或未设置的 E2E 范围。

#### Scenario: SC-DQB-CCF-002

- **GIVEN** 已创建本次的独立一次性库、Go API 与 web 进程，有明确测试地址，不读取主工作树环境文件。
- **WHEN** 按正式命令仅执行 Chromium 的 e2e/issue-task-history.spec.ts。
- **THEN** SHALL 执行且通过这一个命名用例，无失败或跳过；真实响应须验证 compact、own、subtree 的请求范围和内容。
- **AND** 用例与 quality.e2e.critical_paths 的范围 SHALL 一致，并记录本次自建测试栈的回收结果。
