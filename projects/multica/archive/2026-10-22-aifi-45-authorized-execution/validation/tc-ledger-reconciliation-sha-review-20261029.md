# TC ledger reconciliation 原始字节 SHA-256 独立复核

依据 `validation/tc-ledger-reconciliation-20261029.md` 中的四个历史输入和记录值，直接读取文件原始字节重算 SHA-256；未做换行、编码或其他归一化。未运行历史 CP。

| 路径（相对 AI First Platform；不在其下则为绝对路径） | 结果 | 报告记录值 | 实际 raw SHA-256 |
| --- | --- | --- | --- |
| `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/tc-coverage-20261025T153000Z.md` | 通过 | `b26ed5d3b2ca9a344edb55e2dc79e2153d012336c07fd7dc399ba5d8156a71cc` | `b26ed5d3b2ca9a344edb55e2dc79e2153d012336c07fd7dc399ba5d8156a71cc` |
| `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/m003-handover-20261027.md` | 通过 | `98977b71d7efbfba0b067256af586ac392ce14ad9c991714bc55e0a33f4b76a1` | `98977b71d7efbfba0b067256af586ac392ce14ad9c991714bc55e0a33f4b76a1` |
| `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/gate3-review-20261026/REVIEW-BRIEF.md` | 通过 | `8e391cd672c2ae7137cdc81810bfd6d6a4177012dd1dcff4cf5fe4de9ceb4fed` | `8e391cd672c2ae7137cdc81810bfd6d6a4177012dd1dcff4cf5fe4de9ceb4fed` |
| `projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/run-r2-prerequisite-finding.md` | 通过 | `864e76cd1ea327aded3931bfd9a19960590b5b256ce5aaa206b28157baf59fd6` | `864e76cd1ea327aded3931bfd9a19960590b5b256ce5aaa206b28157baf59fd6` |

实际 backend receipt：unknown。
