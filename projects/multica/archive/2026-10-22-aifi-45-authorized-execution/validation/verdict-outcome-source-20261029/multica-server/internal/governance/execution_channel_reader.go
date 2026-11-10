// AIFIRST: trusted T committed verdict channel — reader and projection fence (M003).
//
// 严格模式只认已提交的 DB 事实。ACK、receipt、伪 Git pass 都不能代替 T。
// Unknown 不是 legacy。终态 fence 是「任一 generation 已有消费」与「Strict selection」的并集。
package governance

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
)

var (
	ErrReaderNoCommittedT = errors.New("EXECUTION_READER_NO_COMMITTED_T")
	ErrReaderConflict     = errors.New("EXECUTION_READER_CONFLICT")
	ErrReaderUnknown      = errors.New("EXECUTION_READER_UNKNOWN")
	ErrReaderFence        = errors.New("EXECUTION_READER_FENCE_REQUIRED")
)

const SelectionUnknown = "unknown"

// DispatchCount 在没有 committed verdict 时返回 0，并且不插入 root/task。
func DispatchCount(ctx context.Context, tx pgx.Tx, requestID string) (int, error) {
	var n int
	err := tx.QueryRow(ctx, `
		SELECT count(*) FROM cr_execution_tool_verdict WHERE request_id = $1::uuid`, requestID).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("reader committed T: %w", err)
	}
	if n == 0 {
		return 0, nil
	}
	return n, nil
}

// SettleCandidateTx 已结算则返回原 mapping。未结算时，候选摘要必须等于已冻结的 command 字节。
func SettleCandidateTx(ctx context.Context, tx pgx.Tx, candidate []byte, in ControlSettlementInput) (ControlSettlement, error) {
	var existingKind string
	var existingVerdict string
	err := tx.QueryRow(ctx, `
		SELECT kind, verdict_id::text FROM cr_execution_control_settlement WHERE request_id = $1::uuid`,
		in.RequestID).Scan(&existingKind, &existingVerdict)
	if err == nil {
		return SettleControlCommandTx(ctx, tx, in)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return ControlSettlement{}, fmt.Errorf("reader settle lookup: %w", err)
	}
	var commandBytes []byte
	if err := tx.QueryRow(ctx, `
		SELECT command_bytes FROM cr_execution_control_command WHERE request_id = $1::uuid`,
		in.RequestID).Scan(&commandBytes); err != nil {
		return ControlSettlement{}, fmt.Errorf("reader command: %w", err)
	}
	sum := sha256.Sum256(commandBytes)
	want := sha256.Sum256(candidate)
	if hex.EncodeToString(sum[:]) != hex.EncodeToString(want[:]) && string(commandBytes) != string(candidate) {
		return ControlSettlement{}, fmt.Errorf("%w: 未结算候选不能被替换", ErrReaderConflict)
	}
	return SettleControlCommandTx(ctx, tx, in)
}

// SelectionMode 缺行是 Unknown，不是 legacy。查询失败把错误交回去，不降级。
func SelectionMode(ctx context.Context, tx pgx.Tx, workspaceID, projectID, crID string) (string, error) {
	var mode string
	err := tx.QueryRow(ctx, `
		SELECT mode FROM cr_execution_contract_selection
		WHERE workspace_id = $1::uuid AND project_id = $2::uuid AND cr_id = $3`,
		workspaceID, projectID, crID).Scan(&mode)
	if errors.Is(err, pgx.ErrNoRows) {
		return SelectionUnknown, nil
	}
	if err != nil {
		return "", fmt.Errorf("reader selection: %w", err)
	}
	if mode != string(SelectionStrict) && mode != string(SelectionLegacy) {
		return SelectionUnknown, nil
	}
	return mode, nil
}

// RequireCommittedTForStrict 在 strict（哪怕合同字段已被删掉）下仍要求 committed T。
// legacy 保持原行为：不额外要求 T。Unknown 拒绝，不降级。
func RequireCommittedTForStrict(ctx context.Context, tx pgx.Tx, workspaceID, projectID, crID, requestID string) error {
	mode, err := SelectionMode(ctx, tx, workspaceID, projectID, crID)
	if err != nil {
		return err
	}
	switch mode {
	case string(SelectionLegacy):
		return nil
	case SelectionUnknown:
		return fmt.Errorf("%w: selection 缺失或不可读，不能按 legacy 放行", ErrReaderUnknown)
	}
	n, err := DispatchCount(ctx, tx, requestID)
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("%w: strict selection 缺少 committed T", ErrReaderNoCommittedT)
	}
	return nil
}

// TerminalFenceRequired 的并集：该 CR 已有任意 consumption 行，或 selection 为 strict。
func TerminalFenceRequired(ctx context.Context, tx pgx.Tx, workspaceID, projectID, crID string) (bool, error) {
	var consumed int
	if err := tx.QueryRow(ctx, `
		SELECT count(*) FROM cr_execution_consumption
		WHERE workspace_id = $1::uuid AND cr_id = $2`, workspaceID, crID).Scan(&consumed); err != nil {
		return false, fmt.Errorf("reader fence consumption: %w", err)
	}
	if consumed > 0 {
		return true, nil
	}
	mode, err := SelectionMode(ctx, tx, workspaceID, projectID, crID)
	if err != nil {
		return false, err
	}
	return mode == string(SelectionStrict), nil
}

// AcceptTerminalReport 缺 claim 且 fence 为真时返回 409 语义的错误。
// 只有两个字段都缺且 fence_required=false 才走旧终态路径。
func AcceptTerminalReport(ctx context.Context, tx pgx.Tx, workspaceID, projectID, crID, runtimeID, dispatchedAt string) error {
	required, err := TerminalFenceRequired(ctx, tx, workspaceID, projectID, crID)
	if err != nil {
		return err
	}
	missing := runtimeID == "" || dispatchedAt == ""
	if required && missing {
		return fmt.Errorf("%w: 终态上报缺少 claim", ErrReaderFence)
	}
	if !required && runtimeID == "" && dispatchedAt == "" {
		return nil
	}
	if missing {
		return fmt.Errorf("%w: claim 不完整", ErrReaderFence)
	}
	return nil
}
