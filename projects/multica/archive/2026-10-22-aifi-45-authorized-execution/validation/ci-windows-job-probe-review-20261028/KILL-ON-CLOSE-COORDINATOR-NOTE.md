# 双 Job 方案的用词矛盾

`KILL-ON-CLOSE-TWO-JOB-REVIEW.md` 的结构节称“PID 仅比对，不用于打开”，但 P2 又要求在 exec 保持 helper 原句柄时 `OpenProcess` 打开 helper PID；两者不一致。实施前须明确：P2 若采用 PID，只能打开本次 exec 创建且原始句柄仍被持有、并核对身份的 helper；不按 PID 终止、不打开未知 child PID。**该身份假设仍待独立安全审查与实测**。本说明不修改原评审、也不授权运行。
