// AIFIRST: AIFI-45 attention routing — SC-NTF-001/002/003/004/005/006/007.
//
// Three properties, and nothing else:
//
//  1. A notice is addressed to exactly one (CR, cause, evidence, audience) key.
//     Replays, concurrent duplicates and post-crash retries collapse onto that one
//     inbox row instead of producing a second reminder.
//  2. The inbox row and the notice row are written in one transaction; the
//     broadcast happens after commit and the "delivered" mark after the
//     broadcast. A crash between any two of those leaves a *pending* notice that
//     recovery re-broadcasts on the same inbox id — never a lost notice, and
//     never a second one.
//  3. Mechanical events (a node started, an ack, progress on a repair) do not
//     notify anyone at all. Silence is the default; a notification has to be
//     earned by something a human must decide or fix.
//
// The audience split is a permission boundary, not a preference: being able to fix
// the environment is not being allowed to decide the business question, so the two
// audiences are disjoint and a maintainer notice never carries an authorisation
// decision.
package governance

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/multica-ai/multica/server/internal/events"
	"github.com/multica-ai/multica/server/pkg/protocol"
)

const (
	NoticeStatePending   = "pending"
	NoticeStateDelivered = "delivered"

	NoticeAudienceAuthorizer = "authorizer"
	NoticeAudienceMaintainer = "maintainer"

	noticeInboxType = "cr_execution_notice"
)

// NoticeSilentKinds are run-record events that must stay quiet: they are already
// visible in the run history, and a reminder for them is pure noise.
var NoticeSilentKinds = map[string]bool{
	"run-node-started":   true,
	"run-node-ack":       true,
	"run-node-completed": true,
	"repair-progress":    true,
}

// NoticeMaintainerCauses are the failures a maintainer can actually fix.
var NoticeMaintainerCauses = map[string]bool{
	"environment-failure": true,
	"credential-failure":  true,
	"deploy-failure":      true,
	"binding-failure":     true,
}

// NoticeEvent is the input to a notification. `Kind` is the run-record kind and is
// consulted only for the silence rule; the cause is what the notice is about.
type NoticeEvent struct {
	WorkspaceID    string
	CRID           string
	Kind           string
	Cause          string
	EvidenceDigest string
	ErrorCode      string
	Conclusion     string
	EvidenceRef    string
	Action         string
	TriedPaths     []string
	RecipientID    string
}

// Notice is the rendered message. DedupeKey is derived, never supplied.
type Notice struct {
	Audience    string
	DedupeKey   string
	Title       string
	Body        string
	Severity    string
	Conclusion  string
	Action      string
	EvidenceRef string
	ErrorCode   string
}

type NoticeOutcome struct {
	DedupeKey   string `json:"dedupe_key"`
	NoticeID    string `json:"notice_id"`
	InboxItemID string `json:"inbox_item_id"`
	Audience    string `json:"audience"`
	Created     bool   `json:"created"`
	Broadcast   bool   `json:"broadcast"`
	State       string `json:"state"`
}

// ExecutionNoticeTestHook is a fault-injection seam used only by the recovery
// tests. It is not consulted in production paths beyond the nil check.
var ExecutionNoticeTestHook func(point string) error

func noticeFault(point string) error {
	if ExecutionNoticeTestHook == nil {
		return nil
	}
	return ExecutionNoticeTestHook(point)
}

// NoticeIsSilent reports whether this run-record kind should notify anyone.
func NoticeIsSilent(kind string) bool { return NoticeSilentKinds[kind] }

// NoticeAudienceFor routes a cause to the one party allowed to act on it.
func NoticeAudienceFor(cause string) string {
	if NoticeMaintainerCauses[cause] {
		return NoticeAudienceMaintainer
	}
	return NoticeAudienceAuthorizer
}

// NoticeDedupeKey names one notification. The CR id is part of the key, so two CRs
// failing for the same root cause never collapse into one reminder.
func NoticeDedupeKey(crID, cause, evidenceDigest, audience string) string {
	sum := sha256.Sum256([]byte(strings.Join([]string{
		"cr-execution-notice/v1", crID, cause, evidenceDigest, audience,
	}, "\x00")))
	return hex.EncodeToString(sum[:])
}

// looksLikeVerbatimPayload keeps a raw JSON body out of the notification: a copy of
// the payload is not a conclusion, and it is unreadable for the person deciding.
func looksLikeVerbatimPayload(value string) bool {
	trimmed := strings.TrimSpace(value)
	if len(trimmed) > 1200 {
		return true
	}
	if !strings.HasPrefix(trimmed, "{") && !strings.HasPrefix(trimmed, "[") {
		return false
	}
	var probe any
	return json.Unmarshal([]byte(trimmed), &probe) == nil
}

func isSafeNoticeLine(value string) bool {
	return utf8.ValidString(value) && strings.IndexFunc(value, func(r rune) bool {
		return unicode.IsControl(r) || unicode.In(r, unicode.Zl, unicode.Zp)
	}) < 0
}

// looksLikeCommandShipping rejects instructions that hand a shell command to the
// reader. A notification asks for a decision or a fix; it must not turn the business
// side into a relay for terminal commands.
func looksLikeCommandShipping(value string) bool {
	for _, line := range strings.Split(value, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		if strings.HasPrefix(trimmed, "$ ") || strings.HasPrefix(trimmed, "#!") {
			return true
		}
		for _, pattern := range []string{" && ", "sudo ", "psql ", "kubectl ", "podman ", "docker "} {
			if strings.Contains(trimmed, pattern) {
				return true
			}
		}
	}
	for _, line := range strings.FieldsFunc(value, func(r rune) bool {
		switch r {
		case '\n', '\r', '\v', '\f', '\u0085', '\u2028', '\u2029':
			return true
		default:
			return false
		}
	}) {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "$ ") || strings.HasPrefix(trimmed, "#!") {
			return true
		}
	}
	return false
}

// BuildNotice renders the message and refuses one that is only a payload dump.
func BuildNotice(ev NoticeEvent) (Notice, error) {
	if strings.TrimSpace(ev.CRID) == "" {
		return Notice{}, fmt.Errorf("notice requires cr_id")
	}
	if strings.TrimSpace(ev.Cause) == "" {
		return Notice{}, fmt.Errorf("notice requires cause")
	}
	if strings.TrimSpace(ev.Conclusion) == "" {
		return Notice{}, fmt.Errorf("notice requires a conclusion")
	}
	if strings.TrimSpace(ev.Action) == "" {
		return Notice{}, fmt.Errorf("notice requires the action still needed")
	}
	for _, field := range []string{ev.CRID, ev.Cause, ev.Conclusion, ev.Action, ev.EvidenceRef, ev.ErrorCode} {
		if looksLikeVerbatimPayload(field) {
			return Notice{}, fmt.Errorf("NOTICE_BODY_VERBATIM_PAYLOAD: 通知不得复制整份 JSON 或报告")
		}
	}
	for _, identifier := range []string{ev.CRID, ev.Cause} {
		if strings.TrimSpace(identifier) != identifier || !isSafeNoticeLine(identifier) {
			return Notice{}, errors.New("NOTICE_IDENTIFIER_INVALID")
		}
	}
	for _, field := range []string{ev.ErrorCode, ev.EvidenceRef} {
		if !isSafeNoticeLine(strings.TrimSpace(field)) {
			return Notice{}, errors.New("NOTICE_RENDERED_FIELD_INVALID")
		}
	}
	if looksLikeCommandShipping(ev.Action) {
		return Notice{}, fmt.Errorf("NOTICE_ACTION_MUST_BE_HUMAN: 所需动作必须是人能做的动作，不能是终端命令")
	}
	for _, tried := range ev.TriedPaths {
		if looksLikeCommandShipping(tried) {
			return Notice{}, fmt.Errorf("NOTICE_ACTION_MUST_BE_HUMAN: 已试路径不能是终端命令")
		}
	}
	audience := NoticeAudienceFor(ev.Cause)
	if audience == NoticeAudienceMaintainer && len(ev.TriedPaths) > 0 {
		for _, tried := range ev.TriedPaths {
			if looksLikeVerbatimPayload(tried) {
				return Notice{}, fmt.Errorf("NOTICE_BODY_VERBATIM_PAYLOAD: 通知不得复制整份 JSON 或报告")
			}
		}
	}
	severity := "attention"
	if audience == NoticeAudienceAuthorizer {
		severity = "action_required"
	}
	lines := []string{
		"CR " + ev.CRID + " · " + ev.Cause,
		"结论：" + strings.TrimSpace(ev.Conclusion),
	}
	if code := strings.TrimSpace(ev.ErrorCode); code != "" {
		lines = append(lines, "错误："+code)
	}
	if ref := strings.TrimSpace(ev.EvidenceRef); ref != "" {
		lines = append(lines, "证据："+ref)
	}
	lines = append(lines, "所需动作："+strings.TrimSpace(ev.Action))
	// A maintainer notice has to say what was already tried, otherwise the first
	// reply is "did you try X" and the business side ends up relaying commands.
	if audience == NoticeAudienceMaintainer && len(ev.TriedPaths) > 0 {
		lines = append(lines, "已试路径："+strings.Join(ev.TriedPaths, "；"))
	}
	return Notice{
		Audience:    audience,
		DedupeKey:   NoticeDedupeKey(ev.CRID, ev.Cause, ev.EvidenceDigest, audience),
		Title:       "CR " + ev.CRID + " · " + ev.Cause,
		Body:        strings.Join(lines, "\n"),
		Severity:    severity,
		Conclusion:  strings.TrimSpace(ev.Conclusion),
		Action:      strings.TrimSpace(ev.Action),
		EvidenceRef: strings.TrimSpace(ev.EvidenceRef),
		ErrorCode:   strings.TrimSpace(ev.ErrorCode),
	}, nil
}

// DeliverNotice writes the notice and its inbox row in one transaction, broadcasts
// after commit and marks the notice delivered last.
func DeliverNotice(ctx context.Context, pool *pgxpool.Pool, ev NoticeEvent, broadcast func(context.Context, string, string) error) (NoticeOutcome, error) {
	return deliverNoticeWith(ctx, pool, ev, broadcast)
}

func deliverNoticeWith(ctx context.Context, pool *pgxpool.Pool, ev NoticeEvent, broadcast func(context.Context, string, string) error) (NoticeOutcome, error) {
	if NoticeIsSilent(ev.Kind) {
		return NoticeOutcome{Created: false, Broadcast: false, State: "silent"}, nil
	}
	notice, err := BuildNotice(ev)
	if err != nil {
		return NoticeOutcome{}, err
	}
	workspaceID, err := uuid.Parse(ev.WorkspaceID)
	if err != nil {
		return NoticeOutcome{}, fmt.Errorf("notice workspace id: %w", err)
	}
	recipientID, err := uuid.Parse(ev.RecipientID)
	if err != nil {
		return NoticeOutcome{}, fmt.Errorf("notice recipient id: %w", err)
	}
	if broadcast == nil {
		return NoticeOutcome{}, errors.New("notice broadcast is required")
	}
	inboxItemID := uuid.New()

	tx, err := pool.Begin(ctx)
	if err != nil {
		return NoticeOutcome{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	outcome := NoticeOutcome{
		DedupeKey: notice.DedupeKey, InboxItemID: inboxItemID.String(), Audience: notice.Audience,
	}
	var noticeID uuid.UUID
	err = tx.QueryRow(ctx, `
		INSERT INTO cr_execution_notice
			(workspace_id, cr_id, cause_code, audience, dedupe_key, inbox_item_id)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (workspace_id, dedupe_key) DO NOTHING
		RETURNING id`,
		workspaceID, ev.CRID, ev.Cause, notice.Audience, notice.DedupeKey, inboxItemID).Scan(&noticeID)
	if errors.Is(err, pgx.ErrNoRows) {
		// The same notification already exists: reuse it, add no reminder.
		var existingInbox uuid.UUID
		if scanErr := tx.QueryRow(ctx, `
			SELECT id, inbox_item_id, state FROM cr_execution_notice
			WHERE workspace_id = $1 AND dedupe_key = $2`,
			workspaceID, notice.DedupeKey).Scan(&noticeID, &existingInbox, &outcome.State); scanErr != nil {
			return NoticeOutcome{}, scanErr
		}
		if commitErr := tx.Commit(ctx); commitErr != nil {
			return NoticeOutcome{}, commitErr
		}
		outcome.NoticeID = noticeID.String()
		outcome.InboxItemID = existingInbox.String()
		outcome.Created = false
		return outcome, nil
	}
	if err != nil {
		return NoticeOutcome{}, err
	}
	outcome.NoticeID = noticeID.String()
	outcome.Created = true

	if err := noticeFault("before-inbox"); err != nil {
		return NoticeOutcome{}, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO inbox_item (id, workspace_id, recipient_type, recipient_id, type, severity, title, body)
		VALUES ($1, $2, 'member', $3, $4, $5, $6, $7)`,
		inboxItemID, workspaceID, recipientID, noticeInboxType, notice.Severity, notice.Title, notice.Body); err != nil {
		return NoticeOutcome{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return NoticeOutcome{}, err
	}

	// From here on the reminder exists but is not announced yet: recovery finishes it.
	outcome.State = NoticeStatePending
	if err := noticeFault("after-commit"); err != nil {
		return outcome, err
	}
	if err := broadcast(ctx, workspaceID.String(), inboxItemID.String()); err != nil {
		return outcome, err
	}
	outcome.Broadcast = true
	if err := noticeFault("before-mark"); err != nil {
		return outcome, err
	}
	if _, err := pool.Exec(ctx, `
		UPDATE cr_execution_notice SET state = $2, delivered_at = now()
		WHERE workspace_id = $1 AND id = $3`,
		workspaceID, NoticeStateDelivered, noticeID); err != nil {
		return outcome, err
	}
	outcome.State = NoticeStateDelivered
	return outcome, nil
}

// RecoverPendingNotices finishes notices that were committed but never marked
// delivered. It re-broadcasts the *same* inbox id and never creates a new reminder,
// so an at-least-once broadcast is safe for an idempotent consumer.
func RecoverPendingNotices(ctx context.Context, pool *pgxpool.Pool, workspaceID string, broadcast func(context.Context, string, string) error) (int, error) {
	wsID, err := uuid.Parse(workspaceID)
	if err != nil {
		return 0, fmt.Errorf("recover workspace id: %w", err)
	}
	if broadcast == nil {
		return 0, errors.New("notice recovery broadcast is required")
	}
	rows, err := pool.Query(ctx, `
		SELECT id, inbox_item_id FROM cr_execution_notice
		WHERE workspace_id = $1 AND state = $2
		ORDER BY created_at`, wsID, NoticeStatePending)
	if err != nil {
		return 0, err
	}
	type pending struct{ id, inbox uuid.UUID }
	var all []pending
	for rows.Next() {
		var p pending
		if err := rows.Scan(&p.id, &p.inbox); err != nil {
			rows.Close()
			return 0, err
		}
		all = append(all, p)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}
	count := 0
	for _, p := range all {
		if err := broadcast(ctx, wsID.String(), p.inbox.String()); err != nil {
			return count, err
		}
		if _, err := pool.Exec(ctx, `
			UPDATE cr_execution_notice SET state = $2, delivered_at = now()
			WHERE workspace_id = $1 AND id = $3`, wsID, NoticeStateDelivered, p.id); err != nil {
			return count, err
		}
		count++
	}
	return count, nil
}

// InboxItemLoader reads the delivered inbox row back so the broadcast carries the
// canonical item shape instead of a hand-built one.
type InboxItemLoader func(ctx context.Context, workspaceID, inboxItemID string) (map[string]any, error)

// BusBroadcaster publishes inbox:new on the same bus the realtime bridge listens on.
// A bus and a canonical inbox item loader are required for delivery.
func BusBroadcaster(bus *events.Bus, load InboxItemLoader) func(context.Context, string, string) error {
	return func(ctx context.Context, workspaceID, inboxItemID string) error {
		if bus == nil {
			return errors.New("notice broadcast bus is required")
		}
		if load == nil {
			return errors.New("notice broadcast loader is required")
		}
		item, err := load(ctx, workspaceID, inboxItemID)
		if err != nil {
			return err
		}
		if item == nil {
			return errors.New("notice broadcast loader returned no item")
		}
		itemID, ok := item["id"].(string)
		if !ok || itemID != inboxItemID {
			return errors.New("notice broadcast item id does not match")
		}
		itemWorkspaceID, ok := item["workspace_id"].(string)
		if !ok || itemWorkspaceID != workspaceID {
			return errors.New("notice broadcast item workspace_id does not match")
		}
		bus.Publish(events.Event{
			Type:        protocol.EventInboxNew,
			WorkspaceID: workspaceID,
			ActorType:   "system",
			Payload:     map[string]any{"item": item},
		})
		return nil
	}
}

// LoadInboxItem reads one inbox row back as a broadcast payload.
func LoadInboxItem(pool *pgxpool.Pool) InboxItemLoader {
	return func(ctx context.Context, workspaceID, inboxItemID string) (map[string]any, error) {
		wsID, err := uuid.Parse(workspaceID)
		if err != nil {
			return nil, err
		}
		itemID, err := uuid.Parse(inboxItemID)
		if err != nil {
			return nil, err
		}
		var (
			recipientID, typeName, severity, title string
			body                                   *string
			read, archived                         bool
		)
		if err := pool.QueryRow(ctx, `
			SELECT recipient_id::text, type, severity, title, body, read, archived
			FROM inbox_item WHERE workspace_id = $1 AND id = $2`, wsID, itemID).
			Scan(&recipientID, &typeName, &severity, &title, &body, &read, &archived); err != nil {
			return nil, err
		}
		item := map[string]any{
			"id":             inboxItemID,
			"workspace_id":   workspaceID,
			"recipient_type": "member",
			"recipient_id":   recipientID,
			"type":           typeName,
			"severity":       severity,
			"title":          title,
			"read":           read,
			"archived":       archived,
		}
		if body != nil {
			item["body"] = *body
		}
		return item, nil
	}
}

var (
	ErrNoticeAuthorizerRequired    = errors.New("NOTICE_AUTHORIZER_REQUIRED")
	ErrNoticeMaintainerUnavailable = errors.New("NOTICE_MAINTAINER_UNAVAILABLE")
)

// ResolveNoticeRecipient picks the one member allowed to act on this audience.
//
// The authorizer is never derived from a role: being an owner means you can fix the
// environment, not that you may decide this CR's business question. An empty
// authorizer therefore fails closed even in a workspace full of owners, and the
// maintainer path only ever returns an owner/admin — a plain business member is
// never elected to receive a maintenance request.
func ResolveNoticeRecipient(ctx context.Context, pool *pgxpool.Pool, workspaceID, audience, authorizerID string) (string, error) {
	wsID, err := uuid.Parse(strings.TrimSpace(workspaceID))
	if err != nil {
		return "", fmt.Errorf("notice workspace id: %w", err)
	}
	switch audience {
	case NoticeAudienceAuthorizer:
		id := strings.TrimSpace(authorizerID)
		if id == "" {
			return "", ErrNoticeAuthorizerRequired
		}
		userID, err := uuid.Parse(id)
		if err != nil {
			return "", fmt.Errorf("notice authorizer id: %w", err)
		}
		var member uuid.UUID
		if err := pool.QueryRow(ctx,
			`SELECT user_id FROM member WHERE workspace_id = $1 AND user_id = $2`,
			wsID, userID).Scan(&member); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return "", ErrNoticeAuthorizerRequired
			}
			return "", err
		}
		return member.String(), nil
	case NoticeAudienceMaintainer:
		var maintainer uuid.UUID
		err := pool.QueryRow(ctx, `
			SELECT user_id FROM member
			WHERE workspace_id = $1 AND role IN ('owner', 'admin')
			ORDER BY created_at, user_id
			LIMIT 1`, wsID).Scan(&maintainer)
		if errors.Is(err, pgx.ErrNoRows) {
			return "", ErrNoticeMaintainerUnavailable
		}
		if err != nil {
			return "", err
		}
		return maintainer.String(), nil
	default:
		return "", fmt.Errorf("unknown notice audience %q", audience)
	}
}
