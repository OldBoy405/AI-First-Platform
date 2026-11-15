# T 签名撤销与只读来源检查：作者证据

范围：wire §3.2 的 T 端组件；不宣称 M 撤销事务、当前 head/前驱签名链、可信 claim、隔离或执行消费完成。完整业务 TC 仍 0/49，5 major 不关闭，不推进 Gate 3。

## 最小实现

- `lib/execution-authorization.mjs`：initial/revoke 按 purpose 精确字段集验证；revoke 为21键、来源映射/请求恰五键，仅支持 initial→revoke（新 revision=2、lineage=supersedes、新 grant 与 lineage 不同）。未知/未实现 purpose、额外预算/scope、非法类型/UUID/digest/reason 拒绝。
- reason 按 Unicode White_Space 判断非全空白；≤4096 UTF-8 bytes、Unicode 标量，允许 TAB/CR/LF、拒其他 C0/C1。不 trim 或重写原文。
- `crctl.mjs`：`authorization-bind --check --check-source` 显式只读核来源 bytes/digest/映射；`source_verified=true` 仍 `bound=false,current_head_verified=false`。默认 `--check` 保持来源未核验；`--check-source` 单用/带值为 BAD_ARGS。输出 purpose 区分静态包种类。revoke 的非 check 调用（含 `--binding-stdio`）在 challenge/写入前 `EXECUTION_AUTHORIZATION_REVOKED` 拒绝；initial 仍不准入。
- T 旧来源比较也存在负零错拒：`isDeepStrictEqual(-0,0)` 为 false。两个真实 CLI 反例证实后，仅在 `parseExecutionJSON` 的解析树把 -0 视为整数0；原 payload、人类 source、签名输入与 digest bytes 均保留。已扫描该解析器的 binding/identity/CLI 调用者，不通过重新序列化修复签名。
- 修改范围仅3个 T 源码/测试文件，精确 LF/raw 摘要见 [evidence index](revoke-tools-author-evidence-index.json)。

## 真实 RED → 最小 GREEN

| 证据前缀 | 旧行为断言失败 | RED | 最小 GREEN |
|---|---|---|---|
| `revoke-source-check` | CLI 忽略新显式选项、`source_verified=false`，预期 true | 1 RUN / 0P / 1F / exit1 | 1/1、exit0 |
| `revoke-source-negative-zero` | raw `repair_limit:-0` / action `limit:-0` 与已签0比较返回 EXECUTION_SOURCE_INVALID，预期成功 | 2 RUN / 0P / 2F / exit1 | 2/2、exit0 |
| `revoke-static` | 合法 revoke 被 initial-only schema 返回 EXECUTION_GRANT_PAYLOAD_INVALID | 1 RUN / 0P / 1F / exit1 | 1/1、exit0 |
| `revoke-admission-reject` | 非 check revoke 返回 EXECUTION_BINDING_REQUIRED，预期明确 REVOKED | 1 RUN / 0P / 1F / exit1 | 1/1、exit0 |

以上均实际运行公开 Node CLI；0 skip/0 todo，不把语法检查/编译/缺依赖/空选择算 RED。各前缀的原 `.tap` transcript 保留；新增 `.stdout.tap` / `.stderr.log` 是按主线程追加的最终 delimiter **无损 byte split**，不是覆盖原记录或归一化 raw 输出。argv/cwd/观测 exit、TAP 分项与全部摘要见 index；除全 auth 的独立 meta 外，小范围运行的 exit 由主线程当时 tool 返回观测、事后入索引，未伪称原生 runner 提供独立签名回执。

作者扩展反例覆盖：字段集交叉、未实现 purpose、前驱/lineage/revision 类型与范围、额外 scope/额度、Unicode/字节边界、来源内容/未知 actor/重复与 escaped 重复键、非对象 payload、缺 source、只读标志误用、无 challenge 与无 CR/Git 写入。真实 CRLF 来源与 emoji 正例保留原 bytes。

## 作者整体自检与复核状态

`node --test --test-reporter=tap skills/shared/crctl/scripts/test/execution-authorization.test.mjs`，cwd=`tools/`：**151 RUN / 151 PASS / 0 FAIL / 0 SKIP / exit0**，约53秒；[原始 stdout](revoke-tools-author-auth.stdout.tap)、[stderr](revoke-tools-author-auth.stderr.log)、[meta](revoke-tools-author-auth.meta.json)。这些是组件/子断言，不累计成完整业务 TC；上述最小 GREEN 与151重叠，不相加。

非作者 strong 审查、balanced 三文件独立复跑、M HTTP→真实 T 互操作分别另留证据；本作者报告不抢先将尚未完成的工作判 PASS。economy 已指出的 initial/revoke profile 文档歧义已在 wire §1/2/3.1/3.2 最小澄清，21键以实际协议为准，不因口头误数添加字段。

## 边界与保护

四份受保护文件（两仓 data-root `config.d/quality.yaml` 与 source-root `.stdd/binding.yaml`）原 bytes hash 均匹配前次观测；两仓仍 main、原 HEAD、staged_paths=0。首轮收集 index 因把 quality.yaml 错定位到源码根而 ENOENT，已保留/校验此前分出的 raw 文件后按实际 data root 重收；该收集失败不作为任何 RED/GREEN 或配置验证成功。

有效模型由真实 `stdd config models --format json` 读取（exit0/schema_version1/kind=configured）；strong/balanced/economy 分别实际委派。请求档位和 harness 分开记录，无后端身份回执一律 actual=unknown。模型配置、审批/模式与部署信任根未改；未 commit、push、发布或操作真实业务 CR。
