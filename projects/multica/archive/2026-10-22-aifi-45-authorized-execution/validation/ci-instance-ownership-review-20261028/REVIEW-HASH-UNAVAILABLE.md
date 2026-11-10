**版本门禁尚无法核验，暂停复审。**

本会话只有 `read/grep/find/ls`，没有命令执行或 SHA-256 工具。虽然已只读读取：

- `multica/scripts/aifi45-db/instance-ownership.mjs`
- `multica/scripts/aifi45-db/instance-ownership.test.mjs`

但工具返回的文本不能证明原始文件字节的 SHA-256，尤其不能排除 CRLF 差异。因此，**不能确认与指定 SHA 一致，也不能声称不符或编造实际 SHA**。

请提供只读哈希执行能力，或提供当前文件的可信哈希结果。可在工作区目录执行：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath `
  '..\multica\scripts\aifi45-db\instance-ownership.mjs', `
  '..\multica\scripts\aifi45-db\instance-ownership.test.mjs'
```

在版本确认前，不输出针对该初稿的问题清单，也不作 Podman 兼容性或安全通过结论。**未修改文件，未运行容器、DB 或测试；本次读取不构成任何实际创建、接管或清理授权。**