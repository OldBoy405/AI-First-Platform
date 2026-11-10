# V3 strong 静态安全复审

- 配置：multica/tools `stdd config models --format json` 均为 `schema_version=1`、`kind=configured`，strong 请求 `GBClaude/claude-opus-5-5`、`high`。本次独立会话 `01a186b4-242b-7020-aecc-d2adc980311a` 以该模型和 effort 请求，正常完成。宿主未提供可独立验证的实际后端回执，actual backend **unknown**；不将请求配置本身当作后端凭据。
- 评审范围：`source-final-v3/` 与 PLAN、GREEN-V3、MUTATIONS-V3、两份 balanced 报告。独立评审仅静态读文件；未运行命令或测试、未访问 DB/容器。四文件 raw SHA 在既有报告中一致，评审者**未独立计算**，不把文档互相一致当作重算。变异体仅存 SHA，未由评审者复现。
- 结论：在**标准内建函数与模块初始化可信，且不防任意同 realm 篡改**的限定前提下静态 PASS；非动态复跑，不是来源认证、接线、真实清理或 Gate3 验收。

评审要点：私有快照用于帧、长度、哈希、UTF-8 和 canonical 检查；finally 擦除失败不会发布成功；被隔离的调用方 buffer、JS string 与 native 副本不受该擦除保证。初始化后替换 `TextDecoder.prototype.decode` 的路径已收窄。

残留限制：

1. 多个其他 `Buffer` 方法、哈希与 JSON API 仍动态查找；同 realm 中能替换它们时可取得或改写快照。本限定审查不承诺抵御此攻击，若需求扩大到任意同 realm，必须重新设计与复审。
2. `Buffer.isBuffer` 先于真实 typed-array 判定，proxy 可能运行用户 trap；固定错误不等于无副作用。
3. snapshot 测试中单个超长输入不遍历的断言自身不证明总长度限制；record 测试有独立 allocation-boundary 控制。shared 和 late-decoder snapshot 测试不构成完整并发 TOCTOU 攻击实验。`MUTATIONS-V3.md` 的 shared 变异需要非 shared 才调用 resizable getter 的构造；评审未复现。
4. 强档未复跑 GREEN/变异，也未独立核 SHA；未证明来源、journal、引擎或生产授权。
