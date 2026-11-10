# Go 控制验签固定 operation/domain 绑定

`VerifyControlEnvelope` 已在已知 operation 与非空 domain 检查之后，拒绝 domain 不等于现有 operation 固定表的输入，返回 `ErrControlBindingMismatch`。先前 key 的授权 domain、签名、payload domain 与调用参数虽可一致，却不要求它是该 operation 的固定 domain。签发 API、签名原字节和 domain+NUL+payload 前像不变；节点 Go 与 tools 的共有六组固定表静态一致，Go 额外支持 deployment-observer，其他 manifest/scope 差异和全互操作仍需单独验证。

## 证据

只将原始 Go 协议源文件和新测试文件快照，在显式文件模式执行 `go test -json -vet=off -count=1 -timeout=30s`，没有执行 governance 父包或其 TestMain。测试固定种子、固定时间与合成 scope，独立用 Ed25519 检查签名有效，覆盖七组固定 operation 及 49 组合。旧源码 `source-red` 的 49 个子测试：7 pass、42 fail、skip 0，exit 1；最终 `source-final` 作者与独立各单次 49/49 子测试 pass、skip 0、exit 0。父测试 PASS/FAIL 与子测试不相加；两次复跑不相加。作者 JSON 及 stderr 留存，独立 raw 输出未留存。

最终协议源码 raw SHA-256 `6a767571cdd7961a01c84da385361398c6563a7409d06aeafa95001ffb885dda`；测试 `fa8340e11d601d1bd27bbd923f2872def367eac77c2f5cd863c751ddbe041bf6`。作者和独立分别确认快照前后与当时 live 一致；源码相对 RED 正规化 LF 后仅增加该 guard。测试的签名由被测 signer 合成，再由标准库独立验签，不是外部已知答案或 Node/Go 固定向量；将来签发端若也禁止交叉域，须独立构造负例以继续验证 verifier。

## 兼容与安全边界

已有非固定配对的历史 envelope 现在拒绝；scope、manifest、envelope 等同时无效时错误优先级改变。实际生产调用方如何传域、历史数据与错误分类尚未核实。单文件测试不证明父包集成、可信签发者、真实密钥策略或生产可达性，也不证明 Gate3 可通过。

审查未发现测试调用文件加载、真实 DB、网络或外部进程，但 Go 工具链及标准库不是经 OS 沙箱证明的零 I/O。使用 Go 1.27.1、`shell:false`、local toolchain、module/proxy 关闭、固定白名单环境及本证据目录下独占 cache/tmp/path；实际 backend unknown。工具链自身启动编译/测试进程并写自有缓存；缓存和临时目录原样保留，未清理其他资源。独立静态审查通过该局部目标；multica `CUSTOM.md` #283 已登记。
