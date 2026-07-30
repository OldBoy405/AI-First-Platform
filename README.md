# AI-First 研发协同平台 — 设计文档仓库

本仓库只包含设计文档本身，不 vendor 任何外部代码。三个核心模块（multica / openwiki / tools）以 commit SHA 引用的方式记录在 `docs/references/`，实际代码按需 clone 到仓库外部（约定路径见各引用文件）。

## 目录说明

- [`AI-First平台介绍.html`](AI-First平台介绍.html) — 对外产品介绍（Mermaid/SVG 图示）
- `docs/product/` — **权威规格文档**，改动应视为变更，参照文档内已有的修订记录
  - [PRD](docs/product/AI-First平台-PRD.md)
  - [完整技术方案](docs/product/AI-First平台-完整技术方案.html)
  - [P0 数据模型映射表](docs/product/P0-数据模型映射表.md)
  - [P1 crctl 接入设计](docs/product/P1-crctl接入设计.md)
  - [P2 三模式聊天交互设计](docs/product/P2-三模式聊天交互设计.md)
  - [P3 组织智能设计](docs/product/P3-组织智能设计.md)
  - [Wiki 子系统设计](docs/product/Wiki子系统设计.md)
- `docs/analysis/` — 一次性分析/评审产物，非权威规格，过时可直接重写
  - [对比分析：AI-First 研发协同理念与当前方案](docs/analysis/对比分析-AI-First研发协同理念与当前方案.md)
  - [平台方案评审报告](docs/analysis/平台方案评审报告.md)
- `docs/references/` — 外部/关联仓库的 SHA 指针（不 vendor 完整 clone）
  - [multica](docs/references/multica.md)
  - [openwiki](docs/references/openwiki.md)
  - [tools](docs/references/tools.md)
- `references/`、`_scratch/` — 逆向工程素材与临时产物，已 gitignore，不入版本控制
