// AIFIRST: trusted T committed verdict channel — control settlement (M003, S6).
//
// 结算就是线性化点：一个 request 只有一行 settlement，且只有它能释放 open 槽位。
// 三种看起来不同、其实是同一件事的情形都靠这个主键解决：
//   - T 已提交 verdict、M 的事务回滚后重投；
//   - 结算成功但响应在路上丢了；
//   - 同一份 permit 被重复消费。
//
// 三者都必须返回**原来那份 mapping**，而不是再写一行。
package governance

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

const (
	ControlSettlementEffect   = "effect"
	ControlSettlementNoEffect = "no_effect"
)

var ErrControlSettlementInvalid = errors.New("EXECUTION_CONTROL_SETTLEMENT_INVALID")

type ControlSettlementInput struct {
	RequestID  string
	VerdictID  string
	Kind       string
	EffectKind string
	EffectRef  []byte
	HeadRef    string
	Reason     string
	Now        time.Time
}

type ControlSettlement struct {
	RequestID  string
	VerdictID  string
	Kind       string
	EffectKind string
	EffectRef  []byte
	Replayed   bool
}

func validateControlSettlement(in ControlSettlementInput) error {
	if in.RequestID == "" || in.VerdictID == "" {
		return fmt.Errorf("%w: request 与 verdict 必须有值", ErrControlSettlementInvalid)
	}
	if in.Kind != ControlSettlementEffect && in.Kind != ControlSettlementNoEffect {
		return fmt.Errorf("%w: kind 必须是 effect 或 no_effect", ErrControlSettlementInvalid)
	}
	if in.Kind == ControlSettlementEffect {
		if in.EffectKind == "" || len(in.EffectRef) == 0 {
			return fmt.Errorf("%w: effect 必须有 effect_kind 与 effect_ref", ErrControlSettlementInvalid)
		}
		if !json.Valid(in.EffectRef) {
			return fmt.Errorf("%w: effect_ref 必须是 JSON", ErrControlSettlementInvalid)
		}
	} else if in.EffectKind != "" || len(in.EffectRef) != 0 {
		return fmt.Errorf("%w: no_effect 不得携带 effect 字段", ErrControlSettlementInvalid)
	}
	return nil
}

// SettleControlCommandTx 写结算并推进 command 状态。重复调用返回原 mapping。
func SettleControlCommandTx(ctx context.Context, tx pgx.Tx, in ControlSettlementInput) (ControlSettlement, error) {
	if err := validateControlSettlement(in); err != nil {
		return ControlSettlement{}, err
	}
	// 已有结算：原样返回，不重算、不新增。
	var existing ControlSettlement
	var existingEffectKind *string
	var existingRef []byte
	err := tx.QueryRow(ctx, `
		SELECT request_id::text, verdict_id::text, kind, effect_kind, effect_ref
		FROM cr_execution_control_settlement WHERE request_id = $1::uuid`, in.RequestID).
		Scan(&existing.RequestID, &existing.VerdictID, &existing.Kind, &existingEffectKind, &existingRef)
	switch {
	case err == nil:
		existing.EffectRef = existingRef
		if existingEffectKind != nil {
			existing.EffectKind = *existingEffectKind
		}
		existing.Replayed = true
		return existing, nil
	case !errors.Is(err, pgx.ErrNoRows):
		return ControlSettlement{}, fmt.Errorf("settlement lookup: %w", err)
	}

	// 锁住 command：结算必须落在它的当前状态之后，而不是和状态转换赛跑。
	var state string
	var commandBytes []byte
	if err := tx.QueryRow(ctx, `
		SELECT state, command_bytes FROM cr_execution_control_command WHERE request_id = $1::uuid FOR UPDATE`,
		in.RequestID).Scan(&state, &commandBytes); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ControlSettlement{}, fmt.Errorf("%w: command 不存在", ErrControlSettlementInvalid)
		}
		return ControlSettlement{}, fmt.Errorf("settlement command lock: %w", err)
	}
	// 撤销先于本次 settlement 提交：即使调用方拿着 T 已提交的 permit，也只能结算为 no_effect。
	// 找不到 selection→CR 这条链时不猜（不能把「查不到」当成「没撤销」之外的另一种放行）。
	revoked, err := controlAuthorizationRevoked(ctx, tx, in.RequestID)
	if err != nil {
		return ControlSettlement{}, err
	}
	if revoked && in.Kind == ControlSettlementEffect {
		in.Kind = ControlSettlementNoEffect
		in.EffectKind = ""
		in.EffectRef = nil
		if in.Reason == "" {
			in.Reason = "authorization revoked before settlement"
		}
	}

	// 只有 issued / result_ready 能被结算；created 还没发出去，settled_* 已经结了。
	if state != controlCommandIssued && state != controlCommandResultReady {
		return ControlSettlement{}, fmt.Errorf("%w: command 处于 %s，不能结算", ErrControlSettlementInvalid, state)
	}
	target := controlCommandSettledEffect
	if in.Kind == ControlSettlementNoEffect {
		target = controlCommandSettledNoEffect
	}

	var effectKind any
	var effectRef any
	if in.Kind == ControlSettlementEffect {
		effectKind = in.EffectKind
		effectRef = in.EffectRef
	}
	// 被结算的候选摘要就是这条 command 的冻结字节：换了一份命令就不再是同一件事。
	commandDigest := sha256.Sum256(commandBytes)
	if _, err := tx.Exec(ctx, `
		INSERT INTO cr_execution_control_settlement (
			request_id, verdict_id, kind, effect_kind, effect_ref, fixed_candidate_digest, head_ref, reason, settled_at
		) VALUES ($1::uuid, $2::uuid, $3, $4, $5::jsonb, $6, $7, NULLIF($8, ''), COALESCE($9::timestamptz, now()))
		ON CONFLICT (request_id) DO NOTHING`,
		in.RequestID, in.VerdictID, in.Kind, effectKind, effectRef,
		hex.EncodeToString(commandDigest[:]), in.HeadRef, in.Reason, nilIfZeroTime(in.Now)); err != nil {
		return ControlSettlement{}, fmt.Errorf("settlement insert: %w", err)
	}
	if err := TransitionControlCommandTx(ctx, tx, in.RequestID, state, target, in.VerdictID, "", 0); err != nil {
		return ControlSettlement{}, err
	}
	return ControlSettlement{
		RequestID: in.RequestID, VerdictID: in.VerdictID, Kind: in.Kind,
		EffectKind: in.EffectKind, EffectRef: in.EffectRef,
	}, nil
}

// controlAuthorizationRevoked 在结算这一刻重读授权头。
// 链是 command → reservation → selection → cr → approval_record；任何一环缺失都不是「已撤销」。
func controlAuthorizationRevoked(ctx context.Context, tx pgx.Tx, requestID string) (bool, error) {
	var decision *string
	err := tx.QueryRow(ctx, `
		SELECT a.decision
		FROM cr_execution_control_command c
		JOIN cr_execution_control_reservation r ON r.id = c.reservation_id
		JOIN cr_execution_contract_selection s ON s.id = r.selection_id
		JOIN cr ON cr.workspace_id = s.workspace_id AND cr.cr_id = s.cr_id
		LEFT JOIN approval_record a ON a.id = cr.execution_authorization_head_id
		     AND a.workspace_id = cr.workspace_id AND a.cr_id = cr.cr_id
		WHERE c.request_id = $1::uuid`, requestID).Scan(&decision)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("settlement revoke recheck: %w", err)
	}
	return decision != nil && *decision == "reject", nil
}
