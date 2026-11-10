# AIFI-45 通知广播 — 身份修订独立复核（STDD strong）

- 档位：strong，独立只读复核
- 对象：作者在原审（`REVIEW-STRONG.md`，不覆盖）之后对 `execution_notice.go` 与 noticeguard 测试的修订——loader 返回 item 的 id/workspace 精确匹配；恢复使用规范化 `wsID.String()`
- 结论：**两项修订代码层面通过。** 无类型 panic、无遗漏错误回退；未破坏 `LoadInboxItem` 与事件固定绑定。
- 限定：**未运行任何测试**（含新增 noticeguard 单元测试与真实 DB 测试 `TC_NTF_001/002/005/006/007`）；未触碰 DB/容器/真实通知；未修改源码。

## 0. 覆盖快照

本报告只覆盖下表快照（基于 HEAD `81e5293ad` 的未提交工作区）。之后的任何修订不在覆盖范围，不因本报告自动获认可。归档时复算三项 SHA 与复核时一致，无漂移。

| 文件（`multica/server/internal/governance/`） | sha256 | git blob | 相对原审快照 |
|---|---|---|---|
| `execution_notice.go` | `3c523681b010b4c70f4ba96122d57851f21801c5bef4e9ea9b9c7727f819085f` | `22749eafb6d75144bf2f87775f4467538914b4cd` | 已变 |
| `noticeguard_test/execution_notice_test.go` | `184f920c7277e1684d8c2a29c139bff8eb6e5bb990b435e8874c5d990cd49def` | `9e0995c4f6c97fcf4dc60a354b4d5638cf4bcf13` | 已变 |
| `execution_notice_test.go`（DB 测试） | `8d9a72282cb77f558915b621f62111aec9e8234c77a0a1f4fff87586889faa8f` | `fdc8690fb28ffdecd5f2bc80428a6d1df30fb462` | 未变 |

原审快照 `execution_notice.go` 为 sha256 `821a334fcaedf3fa4d36a946187f121708d445b91ce5b01ecb2fd3b51de71fd2`；noticeguard 测试为 `e90f0f215b9c65e4173b05804f81470487d3eb6966130ce9329970214cb76966`。源码相对原审快照只新增两处改动：`BusBroadcaster` 的 id/workspace 校验，以及恢复改用 `wsID.String()`。

## 1. 逐项核对
- **类型 panic：无。** 两处断言均为安全写法 `item["id"].(string)` / `item["workspace_id"].(string)`，类型不符或缺字段时返回错误不 panic；nil map 已在之前拦截。
- **错误回退**
  - 投递路径：校验失败在事务提交后返回错误，`Broadcast=false`，状态保持 pending，可恢复。✔
  - 恢复路径：校验失败返回已完成数量与错误，该条保持 pending。✔
  - 两处均在 `Publish` 之前返回。
- **匹配语义：大小写敏感的精确字符串比较。** 内部调用方均传规范化字符串：投递传 `workspaceID.String()` 与 `inboxItemID.String()`，恢复传 `wsID.String()` 与 `p.inbox.String()`，因此都能匹配。
- **`LoadInboxItem` 兼容**
  - 其返回的 `id` / `workspace_id` 即传入字符串原样带回，总能通过校验，未被破坏。
  - 对它而言该校验是同义反复，真正保证“读到的就是这一行”的是 SQL `WHERE workspace_id=$1 AND id=$2`；新增校验仅对自定义 loader 有实际约束。
- **固定绑定**
  - 事件 `WorkspaceID` 仍取自调用参数，payload item 现须与该参数精确一致。✔
  - DB 测试 `TC_NTF_002` 使用 `LoadInboxItem`，按代码逻辑仍兼容，**未实际运行**。
- **恢复规范化：** 原报告低风险问题4（恢复用未规范化 workspaceID）已修复，广播与 UPDATE 均使用解析后的 `wsID`。

## 2. 测试断言
- **负例 9 组：** id 与 workspace 各覆盖空 map、缺失、取值错误、非字符串、大小写不同；每组断言 `err != nil` 且订阅者调用次数为 0。✔
- **常量改动正确：** 测试常量由全数字 UUID 改为 `aaaa…/bbbb…`。全数字字符串经 `ToUpper` 不变，“大小写不同”两组会形同虚设；改为字母后才真正有效。
- **正例：** 补充 `workspace_id`，并断言 payload 中 id、workspace_id、title 与预期一致。✔
- **不足**
  1. 负例只断言“有错误”，不检查错误内容，无法证明报错来自身份校验那一步。
  2. 恢复规范化无任何测试：单元测试无数据库连接池，DB 测试的 workspaceID 本就是规范格式，大写/非规范输入场景未覆盖。

## 3. 新残留问题（低）
1. `BusBroadcaster` 自身不做规范化：直接调用并传大写 workspaceID 时，`LoadInboxItem` 原样带回、校验通过，最终事件 `WorkspaceID` 为非规范格式。目前生产无此类调用方。
2. 报错使用不带 id 的 `errors.New`，也无可供 `errors.Is` 判断的固定错误值，排查不便。

## 4. 对原报告的局部结论
- **代码层面已关闭：** 原报告低风险问题3（空载荷、id 不一致）与问题4（恢复用未规范化 workspaceID）。
- **仍存在、无变化：**
  - 三个中风险：存储模型与去重键偏离 design §5（缺 project 与 recipient）；`Publish` 无送达回执；依赖错误提交后才暴露，恢复首条失败即卡住后续。
  - 原报告低风险问题5：去重命中 pending 不重新广播。
- **未验收：** 新增 noticeguard 测试未运行；真实 DB 测试（`TC_NTF_001/002/005/006/007`）未运行；生产仍未接线。

## 5. 方法
读取修订后 `execution_notice.go` 相对 HEAD `81e5293ad` 的 diff 与 noticeguard 测试全文，对照原审快照与 `REVIEW-STRONG.md` 结论；计算 sha256 与 git blob。只读，未运行测试、DB、容器或真实通知。
