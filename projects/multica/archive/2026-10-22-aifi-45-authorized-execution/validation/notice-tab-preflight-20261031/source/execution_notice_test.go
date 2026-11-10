package noticeguard_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/multica-ai/multica/server/internal/events"
	"github.com/multica-ai/multica/server/internal/governance"
	"github.com/multica-ai/multica/server/pkg/protocol"
)

const (
	workspaceID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	inboxID     = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
)

func validEvent() governance.NoticeEvent {
	return governance.NoticeEvent{
		WorkspaceID: workspaceID,
		RecipientID: "33333333-3333-4333-8333-333333333333",
		CRID:        "CR-TEST-001",
		Kind:        "run-node-blocked",
		Cause:       "authorization-required",
		Conclusion:  "Authorization is required",
		Action:      "Review the requested scope",
	}
}

func requireErrorContaining(t *testing.T, err error, text string) {
	t.Helper()
	if err == nil || !strings.Contains(strings.ToLower(err.Error()), text) {
		t.Fatalf("error = %v, want an error containing %q", err, text)
	}
}

func failOnPanic(t *testing.T) {
	t.Helper()
	if r := recover(); r != nil {
		t.Errorf("panicked instead of rejecting the missing broadcast before DB access: %v", r)
	}
}

func TestDeliverRejectsMissingBroadcastBeforeDB(t *testing.T) {
	defer failOnPanic(t)
	outcome, err := governance.DeliverNotice(context.Background(), nil, validEvent(), nil)
	requireErrorContaining(t, err, "broadcast")
	if outcome.Created || outcome.Broadcast || outcome.State == governance.NoticeStateDelivered {
		t.Fatalf("missing broadcast returned a delivered outcome: %+v", outcome)
	}
}

func TestRecoveryRejectsMissingBroadcastBeforeDB(t *testing.T) {
	defer failOnPanic(t)
	count, err := governance.RecoverPendingNotices(context.Background(), nil, workspaceID, nil)
	requireErrorContaining(t, err, "broadcast")
	if count != 0 {
		t.Fatalf("recovered %d notices without a broadcast", count)
	}
}

func TestSilentEventsNeedNoBroadcasterOrDB(t *testing.T) {
	for _, kind := range []string{"run-node-started", "run-node-ack", "run-node-completed", "repair-progress"} {
		t.Run(kind, func(t *testing.T) {
			ev := validEvent()
			ev.Kind = kind
			outcome, err := governance.DeliverNotice(context.Background(), nil, ev, nil)
			if err != nil || outcome.State != "silent" || outcome.Created || outcome.Broadcast {
				t.Fatalf("silent outcome = %+v, err = %v", outcome, err)
			}
		})
	}
}

func TestBusBroadcasterRejectsMissingDependencies(t *testing.T) {
	load := func(context.Context, string, string) (map[string]any, error) {
		return map[string]any{"id": inboxID, "workspace_id": workspaceID}, nil
	}
	t.Run("nil bus", func(t *testing.T) {
		err := governance.BusBroadcaster(nil, load)(context.Background(), workspaceID, inboxID)
		requireErrorContaining(t, err, "bus")
	})
	t.Run("nil loader", func(t *testing.T) {
		bus := events.New()
		calls := 0
		bus.Subscribe(protocol.EventInboxNew, func(events.Event) { calls++ })
		err := governance.BusBroadcaster(bus, nil)(context.Background(), workspaceID, inboxID)
		requireErrorContaining(t, err, "load")
		if calls != 0 {
			t.Fatalf("published %d events without a loader", calls)
		}
	})
	t.Run("nil loaded item", func(t *testing.T) {
		bus := events.New()
		calls := 0
		bus.Subscribe(protocol.EventInboxNew, func(events.Event) { calls++ })
		err := governance.BusBroadcaster(bus, func(context.Context, string, string) (map[string]any, error) {
			return nil, nil
		})(context.Background(), workspaceID, inboxID)
		requireErrorContaining(t, err, "load")
		if calls != 0 {
			t.Fatalf("published %d events without a loaded item", calls)
		}
	})
}

func TestBusBroadcasterRejectsMismatchedItemIdentity(t *testing.T) {
	cases := []struct {
		name string
		item map[string]any
	}{
		{"empty map", map[string]any{}},
		{"missing id", map[string]any{"workspace_id": workspaceID}},
		{"wrong id", map[string]any{"id": "other", "workspace_id": workspaceID}},
		{"non-string id", map[string]any{"id": 1, "workspace_id": workspaceID}},
		{"different id case", map[string]any{"id": strings.ToUpper(inboxID), "workspace_id": workspaceID}},
		{"missing workspace", map[string]any{"id": inboxID}},
		{"wrong workspace", map[string]any{"id": inboxID, "workspace_id": "other"}},
		{"non-string workspace", map[string]any{"id": inboxID, "workspace_id": 1}},
		{"different workspace case", map[string]any{"id": inboxID, "workspace_id": strings.ToUpper(workspaceID)}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			bus := events.New()
			calls := 0
			bus.Subscribe(protocol.EventInboxNew, func(events.Event) { calls++ })
			broadcast := governance.BusBroadcaster(bus, func(context.Context, string, string) (map[string]any, error) {
				return tc.item, nil
			})
			err := broadcast(context.Background(), workspaceID, inboxID)
			if err == nil {
				t.Error("broadcast accepted an item with an invalid identity")
			}
			if calls != 0 {
				t.Errorf("published %d events with an invalid identity", calls)
			}
		})
	}
}

func TestBusBroadcasterPublishesLoadedItemAndPropagatesError(t *testing.T) {
	bus := events.New()
	var received []events.Event
	bus.Subscribe(protocol.EventInboxNew, func(e events.Event) { received = append(received, e) })
	loadErr := errors.New("loader failed")
	broadcast := governance.BusBroadcaster(bus, func(_ context.Context, ws, id string) (map[string]any, error) {
		if ws != workspaceID || id != inboxID {
			t.Fatalf("loader called with %q, %q", ws, id)
		}
		return nil, loadErr
	})
	if err := broadcast(context.Background(), workspaceID, inboxID); !errors.Is(err, loadErr) || len(received) != 0 {
		t.Fatalf("loader error = %v, published = %d", err, len(received))
	}
	broadcast = governance.BusBroadcaster(bus, func(_ context.Context, ws, id string) (map[string]any, error) {
		if ws != workspaceID || id != inboxID {
			t.Fatalf("loader called with %q, %q", ws, id)
		}
		return map[string]any{"id": id, "workspace_id": ws, "title": "canonical"}, nil
	})
	if err := broadcast(context.Background(), workspaceID, inboxID); err != nil {
		t.Fatalf("broadcast: %v", err)
	}
	if len(received) != 1 || received[0].Type != protocol.EventInboxNew || received[0].WorkspaceID != workspaceID || received[0].ActorType != "system" {
		t.Fatalf("published events = %+v", received)
	}
	payload, ok := received[0].Payload.(map[string]any)
	if !ok {
		t.Fatalf("payload = %#v", received[0].Payload)
	}
	item, ok := payload["item"].(map[string]any)
	if !ok || item["id"] != inboxID || item["workspace_id"] != workspaceID || item["title"] != "canonical" {
		t.Fatalf("item = %#v", payload["item"])
	}
}

func TestNoticeRenderedPayloadGuard(t *testing.T) {
	fields := []struct {
		name       string
		maintainer bool
		set        func(*governance.NoticeEvent, string)
	}{
		{"cr_id", false, func(ev *governance.NoticeEvent, s string) { ev.CRID = s }},
		{"cause", false, func(ev *governance.NoticeEvent, s string) { ev.Cause = s }},
		{"conclusion", false, func(ev *governance.NoticeEvent, s string) { ev.Conclusion = s }},
		{"action", false, func(ev *governance.NoticeEvent, s string) { ev.Action = s }},
		{"evidence", false, func(ev *governance.NoticeEvent, s string) { ev.EvidenceRef = s }},
		{"code_authorizer", false, func(ev *governance.NoticeEvent, s string) { ev.ErrorCode = s }},
		{"code_maintainer", true, func(ev *governance.NoticeEvent, s string) { ev.ErrorCode = s }},
		{"tried_maintainer", true, func(ev *governance.NoticeEvent, s string) { ev.TriedPaths = []string{"restart runner", s, "retry"} }},
	}
	values := []struct {
		name  string
		value string
	}{
		{"json", " \n[1, 2] \t"},
		{"long", strings.Repeat("x", 1201)},
	}
	for _, field := range fields {
		for _, value := range values {
			t.Run(field.name+"/"+value.name, func(t *testing.T) {
				ev := validEvent()
				if field.maintainer {
					ev.Cause = "environment-failure"
				}
				field.set(&ev, value.value)
				t.Run("build", func(t *testing.T) {
					notice, err := governance.BuildNotice(ev)
					if err == nil || !strings.Contains(err.Error(), "NOTICE_BODY_VERBATIM_PAYLOAD") {
						t.Error("BODY_GUARD_MISSING")
					}
					if notice != (governance.Notice{}) {
						t.Error("BODY_GUARD_RETURNED_NOTICE")
					}
				})
				t.Run("deliver", func(t *testing.T) {
					calls := 0
					defer func() {
						if recover() != nil {
							t.Error("DELIVERY_REACHED_NIL_POOL")
						}
						if calls != 0 {
							t.Error("DELIVERY_BROADCAST_CALLED")
						}
					}()
					outcome, err := governance.DeliverNotice(context.Background(), nil, ev, func(context.Context, string, string) error {
						calls++
						return nil
					})
					if err == nil || !strings.Contains(err.Error(), "NOTICE_BODY_VERBATIM_PAYLOAD") {
						t.Error("DELIVERY_GUARD_MISSING")
					}
					if outcome != (governance.NoticeOutcome{}) {
						t.Error("DELIVERY_GUARD_RETURNED_OUTCOME")
					}
				})
			})
		}
	}
}

func TestNoticeRejectsAmbiguousIdentifiers(t *testing.T) {
	fields := []struct {
		name string
		set  func(*governance.NoticeEvent, string)
	}{
		{"cr_id", func(ev *governance.NoticeEvent, s string) { ev.CRID = s }},
		{"cause", func(ev *governance.NoticeEvent, s string) { ev.Cause = s }},
	}
	values := []struct{ name, value string }{
		{"newline", "value\nforged"},
		{"carriage_return", "value\rforged"},
		{"nul", "value\x00forged"},
		{"delete", "value\x7fforged"},
		{"c1_control", "value\u0081forged"},
		{"line_separator", "value\u2028forged"},
		{"paragraph_separator", "value\u2029forged"},
		{"invalid_utf8", "value\xffforged"},
		{"leading_space", " value"},
		{"trailing_unicode_space", "value\u00a0"},
	}
	for _, field := range fields {
		for _, value := range values {
			t.Run(field.name+"/"+value.name, func(t *testing.T) {
				ev := validEvent()
				field.set(&ev, value.value)
				t.Run("build", func(t *testing.T) {
					notice, err := governance.BuildNotice(ev)
					if err == nil || err.Error() != "NOTICE_IDENTIFIER_INVALID" || notice != (governance.Notice{}) {
						t.Error("IDENTIFIER_GUARD_MISSING")
					}
				})
				t.Run("deliver", func(t *testing.T) {
					calls := 0
					defer func() {
						if recover() != nil {
							t.Error("IDENTIFIER_DELIVERY_REACHED_NIL_POOL")
						}
						if calls != 0 {
							t.Error("IDENTIFIER_DELIVERY_BROADCAST_CALLED")
						}
					}()
					outcome, err := governance.DeliverNotice(context.Background(), nil, ev, func(context.Context, string, string) error {
						calls++
						return nil
					})
					if err == nil || err.Error() != "NOTICE_IDENTIFIER_INVALID" || outcome != (governance.NoticeOutcome{}) {
						t.Error("IDENTIFIER_DELIVERY_GUARD_MISSING")
					}
				})
			})
		}
	}
	t.Run("preserves_valid_unicode", func(t *testing.T) {
		ev := validEvent()
		ev.CRID = "CR-示例-1"
		ev.Cause = "review required"
		notice, err := governance.BuildNotice(ev)
		if err != nil || notice.Title != "CR "+ev.CRID+" · "+ev.Cause ||
			!strings.HasPrefix(notice.Body, notice.Title+"\n") ||
			notice.Audience != governance.NoticeAudienceAuthorizer ||
			notice.DedupeKey != governance.NoticeDedupeKey(ev.CRID, ev.Cause, ev.EvidenceDigest, notice.Audience) {
			t.Error("VALID_IDENTIFIER_CHANGED")
		}
	})
	t.Run("invalid_silent_event_remains_silent", func(t *testing.T) {
		ev := validEvent()
		ev.Kind = "run-node-started"
		ev.CRID = "bad\nidentifier"
		ev.Cause = " bad cause "
		outcome, err := governance.DeliverNotice(context.Background(), nil, ev, nil)
		if err != nil || outcome.State != "silent" || outcome.Created || outcome.Broadcast {
			t.Error("SILENT_IDENTIFIER_BEHAVIOR_CHANGED")
		}
	})
	t.Run("identifier_precedes_command_error", func(t *testing.T) {
		ev := validEvent()
		ev.CRID = "bad\nidentifier"
		ev.Action = "sudo retry"
		_, err := governance.BuildNotice(ev)
		if err == nil || err.Error() != "NOTICE_IDENTIFIER_INVALID" {
			t.Error("IDENTIFIER_ERROR_PRECEDENCE_CHANGED")
		}
	})
}

func TestNoticeRejectsAmbiguousRenderedAtoms(t *testing.T) {
	fields := []struct {
		name       string
		maintainer bool
		set        func(*governance.NoticeEvent, string)
	}{
		{"code_authorizer", false, func(ev *governance.NoticeEvent, s string) { ev.ErrorCode = s }},
		{"code_maintainer", true, func(ev *governance.NoticeEvent, s string) { ev.ErrorCode = s }},
		{"evidence_authorizer", false, func(ev *governance.NoticeEvent, s string) { ev.EvidenceRef = s }},
		{"evidence_maintainer", true, func(ev *governance.NoticeEvent, s string) { ev.EvidenceRef = s }},
	}
	values := []struct{ name, value string }{
		{"newline", "value\nforged"},
		{"carriage_return", "value\rforged"},
		{"tab", "value\tforged"},
		{"nul", "value\x00forged"},
		{"leading_nul", "\x00value"},
		{"trailing_nul", "value\x00"},
		{"delete", "value\x7fforged"},
		{"c1_control", "value\u0081forged"},
		{"line_separator", "value\u2028forged"},
		{"paragraph_separator", "value\u2029forged"},
		{"invalid_utf8", "value\xffforged"},
	}
	for _, field := range fields {
		for _, value := range values {
			t.Run(field.name+"/"+value.name, func(t *testing.T) {
				ev := validEvent()
				if field.maintainer {
					ev.Cause = "environment-failure"
				}
				field.set(&ev, value.value)
				t.Run("build", func(t *testing.T) {
					notice, err := governance.BuildNotice(ev)
					if err == nil || err.Error() != "NOTICE_RENDERED_FIELD_INVALID" || notice != (governance.Notice{}) {
						t.Error("RENDERED_FIELD_GUARD_MISSING")
					}
				})
				t.Run("deliver", func(t *testing.T) {
					calls := 0
					defer func() {
						if recover() != nil {
							t.Error("RENDERED_FIELD_DELIVERY_REACHED_NIL_POOL")
						}
						if calls != 0 {
							t.Error("RENDERED_FIELD_DELIVERY_BROADCAST_CALLED")
						}
					}()
					outcome, err := governance.DeliverNotice(context.Background(), nil, ev, func(context.Context, string, string) error {
						calls++
						return nil
					})
					if err == nil || err.Error() != "NOTICE_RENDERED_FIELD_INVALID" || outcome != (governance.NoticeOutcome{}) {
						t.Error("RENDERED_FIELD_DELIVERY_GUARD_MISSING")
					}
				})
			})
		}
	}
	t.Run("unicode_and_outer_whitespace", func(t *testing.T) {
		ev := validEvent()
		ev.ErrorCode = " \n错误 码\r "
		ev.EvidenceRef = " \t证据 链接\n "
		notice, err := governance.BuildNotice(ev)
		if err != nil || notice.ErrorCode != "错误 码" || notice.EvidenceRef != "证据 链接" ||
			!strings.Contains(notice.Body, "错误：错误 码\n证据：证据 链接") ||
			notice.DedupeKey != governance.NoticeDedupeKey(ev.CRID, ev.Cause, ev.EvidenceDigest, notice.Audience) {
			t.Error("VALID_RENDERED_FIELD_CHANGED")
		}
	})
	t.Run("empty_evidence_ref_remains_hidden", func(t *testing.T) {
		ev := validEvent()
		ev.EvidenceRef = " \n\t "
		notice, err := governance.BuildNotice(ev)
		if err != nil || notice.EvidenceRef != "" || strings.Contains(notice.Body, "证据：") {
			t.Error("EMPTY_EVIDENCE_BEHAVIOR_CHANGED")
		}
	})
	t.Run("json_precedes_rendered_field", func(t *testing.T) {
		ev := validEvent()
		ev.ErrorCode = "[1,\n2]"
		_, err := governance.BuildNotice(ev)
		if err == nil || !strings.Contains(err.Error(), "NOTICE_BODY_VERBATIM_PAYLOAD") {
			t.Error("RENDERED_FIELD_JSON_PRECEDENCE_CHANGED")
		}
	})
	t.Run("identifier_precedes_rendered_field", func(t *testing.T) {
		ev := validEvent()
		ev.CRID = "bad\nidentifier"
		ev.ErrorCode = "bad\ncode"
		_, err := governance.BuildNotice(ev)
		if err == nil || err.Error() != "NOTICE_IDENTIFIER_INVALID" {
			t.Error("RENDERED_FIELD_IDENTIFIER_PRECEDENCE_CHANGED")
		}
	})
	t.Run("rendered_field_precedes_command", func(t *testing.T) {
		ev := validEvent()
		ev.ErrorCode = "bad\ncode"
		ev.Action = "sudo retry"
		_, err := governance.BuildNotice(ev)
		if err == nil || err.Error() != "NOTICE_RENDERED_FIELD_INVALID" {
			t.Error("RENDERED_FIELD_COMMAND_PRECEDENCE_CHANGED")
		}
	})
	t.Run("invalid_silent_event_remains_silent", func(t *testing.T) {
		ev := validEvent()
		ev.Kind = "run-node-started"
		ev.ErrorCode = "bad\ncode"
		outcome, err := governance.DeliverNotice(context.Background(), nil, ev, nil)
		if err != nil || outcome.State != "silent" || outcome.Created || outcome.Broadcast {
			t.Error("SILENT_RENDERED_FIELD_BEHAVIOR_CHANGED")
		}
	})
}

func TestNoticeRejectsCommandsAfterLineSeparators(t *testing.T) {
	fields := []struct {
		name       string
		maintainer bool
		set        func(*governance.NoticeEvent, string)
	}{
		{"action", false, func(ev *governance.NoticeEvent, s string) { ev.Action = s }},
		{"tried_authorizer", false, func(ev *governance.NoticeEvent, s string) { ev.TriedPaths = []string{s} }},
		{"tried_maintainer", true, func(ev *governance.NoticeEvent, s string) { ev.TriedPaths = []string{s} }},
	}
	separators := []struct{ name, value string }{
		{"lf", "\n"}, {"crlf", "\r\n"}, {"cr", "\r"}, {"vt", "\v"},
		{"ff", "\f"}, {"nel", "\u0085"}, {"line", "\u2028"}, {"paragraph", "\u2029"},
	}
	commands := []struct{ name, value string }{
		{"shell", "$ example"}, {"shebang", "#!example"},
	}
	for _, field := range fields {
		for _, sep := range separators {
			for _, command := range commands {
				t.Run(field.name+"/"+sep.name+"/"+command.name, func(t *testing.T) {
					ev := validEvent()
					if field.maintainer {
						ev.Cause = "environment-failure"
					}
					field.set(&ev, "safe context"+sep.value+command.value)
					t.Run("build", func(t *testing.T) {
						notice, err := governance.BuildNotice(ev)
						if err == nil || !strings.Contains(err.Error(), "NOTICE_ACTION_MUST_BE_HUMAN") || notice != (governance.Notice{}) {
							t.Error("LINE_COMMAND_GUARD_MISSING")
						}
					})
					t.Run("deliver", func(t *testing.T) {
						calls := 0
						defer func() {
							if recover() != nil {
								t.Error("LINE_COMMAND_DELIVERY_REACHED_NIL_POOL")
							}
							if calls != 0 {
								t.Error("LINE_COMMAND_BROADCAST_CALLED")
							}
						}()
						outcome, err := governance.DeliverNotice(context.Background(), nil, ev, func(context.Context, string, string) error {
							calls++
							return nil
						})
						if err == nil || !strings.Contains(err.Error(), "NOTICE_ACTION_MUST_BE_HUMAN") || outcome != (governance.NoticeOutcome{}) {
							t.Error("LINE_COMMAND_DELIVERY_GUARD_MISSING")
						}
					})
				})
			}
		}
	}
	t.Run("ordinary_multiline_preserved", func(t *testing.T) {
		ev := validEvent()
		ev.Cause = "environment-failure"
		ev.Action = "Review the evidence\rAsk the owner"
		ev.TriedPaths = []string{"Checked service\u2028Reviewed logs"}
		notice, err := governance.BuildNotice(ev)
		if err != nil || notice.Action != ev.Action || !strings.Contains(notice.Body, ev.Action) || !strings.Contains(notice.Body, ev.TriedPaths[0]) {
			t.Error("ORDINARY_MULTILINE_CHANGED")
		}
	})
	t.Run("silent_event_remains_silent", func(t *testing.T) {
		ev := validEvent()
		ev.Kind = "run-node-started"
		ev.Action = "context\r$ example"
		outcome, err := governance.DeliverNotice(context.Background(), nil, ev, nil)
		if err != nil || outcome.State != "silent" || outcome.Created || outcome.Broadcast {
			t.Error("SILENT_COMMAND_BEHAVIOR_CHANGED")
		}
	})
}

func TestNoticePreservesCommandChecksAcrossNewSeparators(t *testing.T) {
	fields := []struct {
		name       string
		maintainer bool
		set        func(*governance.NoticeEvent, string)
	}{
		{"action", false, func(ev *governance.NoticeEvent, s string) { ev.Action = s }},
		{"tried_authorizer", false, func(ev *governance.NoticeEvent, s string) { ev.TriedPaths = []string{s} }},
		{"tried_maintainer", true, func(ev *governance.NoticeEvent, s string) { ev.TriedPaths = []string{s} }},
	}
	separators := []struct{ name, value string }{
		{"cr", "\r"}, {"vt", "\v"}, {"ff", "\f"},
		{"nel", "\u0085"}, {"line", "\u2028"}, {"paragraph", "\u2029"},
	}
	patterns := []struct {
		name  string
		value func(string) string
	}{
		{"and", func(sep string) string { return "safe context" + sep + " && retry" }},
		{"kubectl", func(sep string) string { return "safe context kubectl " + sep + "status" }},
	}
	for _, field := range fields {
		for _, sep := range separators {
			for _, pattern := range patterns {
				t.Run(field.name+"/"+sep.name+"/"+pattern.name, func(t *testing.T) {
					ev := validEvent()
					if field.maintainer {
						ev.Cause = "environment-failure"
					}
					field.set(&ev, pattern.value(sep.value))
					t.Run("build", func(t *testing.T) {
						notice, err := governance.BuildNotice(ev)
						if err == nil || !strings.Contains(err.Error(), "NOTICE_ACTION_MUST_BE_HUMAN") || notice != (governance.Notice{}) {
							t.Error("LEGACY_COMMAND_GUARD_MISSING")
						}
					})
					t.Run("deliver", func(t *testing.T) {
						calls := 0
						defer func() {
							if recover() != nil {
								t.Error("LEGACY_COMMAND_DELIVERY_REACHED_NIL_POOL")
							}
							if calls != 0 {
								t.Error("LEGACY_COMMAND_BROADCAST_CALLED")
							}
						}()
						outcome, err := governance.DeliverNotice(context.Background(), nil, ev, func(context.Context, string, string) error {
							calls++
							return nil
						})
						if err == nil || !strings.Contains(err.Error(), "NOTICE_ACTION_MUST_BE_HUMAN") || outcome != (governance.NoticeOutcome{}) {
							t.Error("LEGACY_COMMAND_DELIVERY_GUARD_MISSING")
						}
					})
				})
			}
		}
	}
}

func TestNoticeRejectsTabbedExistingCommands(t *testing.T) {
	fields := []struct {
		name       string
		maintainer bool
		set        func(*governance.NoticeEvent, string)
	}{
		{"action_authorizer", false, func(ev *governance.NoticeEvent, s string) { ev.Action = s }},
		{"action_maintainer", true, func(ev *governance.NoticeEvent, s string) { ev.Action = s }},
		{"tried_authorizer", false, func(ev *governance.NoticeEvent, s string) { ev.TriedPaths = []string{"checked logs", s} }},
		{"tried_maintainer", true, func(ev *governance.NoticeEvent, s string) { ev.TriedPaths = []string{"checked logs", s} }},
	}
	separators := []struct{ name, value string }{{"space", " "}, {"tab", "\t"}}
	for _, field := range fields {
		for _, command := range []string{"sudo", "psql", "kubectl", "podman", "docker"} {
			for _, sep := range separators {
				t.Run(field.name+"/"+command+"/"+sep.name, func(t *testing.T) {
					ev := validEvent()
					if field.maintainer {
						ev.Cause = "environment-failure"
					}
					field.set(&ev, "Review context: "+command+sep.value+"status")
					t.Run("build", func(t *testing.T) {
						notice, err := governance.BuildNotice(ev)
						if err == nil || !strings.Contains(err.Error(), "NOTICE_ACTION_MUST_BE_HUMAN") || notice != (governance.Notice{}) {
							t.Errorf("TABBED_COMMAND_BUILD_GUARD_MISSING: notice = %+v, err = %v", notice, err)
						}
					})
					t.Run("deliver", func(t *testing.T) {
						// A missed command guard reaches the existing nil-broadcast rejection,
						// not a nil pool. This checks validation order, not DB delivery.
						outcome, err := governance.DeliverNotice(context.Background(), nil, ev, nil)
						if err == nil || !strings.Contains(err.Error(), "NOTICE_ACTION_MUST_BE_HUMAN") || outcome != (governance.NoticeOutcome{}) {
							t.Errorf("TABBED_COMMAND_DELIVERY_GUARD_MISSING: outcome = %+v, err = %v", outcome, err)
						}
					})
				})
			}
		}
	}
	for _, cause := range []string{"authorization-required", "environment-failure"} {
		t.Run("ordinary_tabs_"+cause, func(t *testing.T) {
			ev := validEvent()
			ev.Cause = cause
			ev.Action = "Review\tthe evidence"
			ev.TriedPaths = []string{"dockerfile\treview"}
			notice, err := governance.BuildNotice(ev)
			if err != nil || notice.Action != ev.Action || (cause == "environment-failure" && !strings.Contains(notice.Body, ev.TriedPaths[0])) {
				t.Error("ORDINARY_TABS_CHANGED")
			}
		})
	}
	t.Run("non_command_delivery_stops_before_db", func(t *testing.T) {
		ev := validEvent()
		if _, err := governance.BuildNotice(ev); err != nil {
			t.Fatalf("valid control rejected: %v", err)
		}
		outcome, err := governance.DeliverNotice(context.Background(), nil, ev, nil)
		if err == nil || err.Error() != "notice broadcast is required" || outcome != (governance.NoticeOutcome{}) {
			t.Fatalf("nil-broadcast control: outcome = %+v, err = %v", outcome, err)
		}
	})
	for _, field := range fields {
		for _, value := range []struct{ name, text string }{
			{"literal_backslash_t", "Review context: sudo\\tstatus"},
			{"trailing_tab_only", "Review context: sudo\t\t "},
		} {
			t.Run(field.name+"/"+value.name, func(t *testing.T) {
				ev := validEvent()
				if field.maintainer {
					ev.Cause = "environment-failure"
				}
				field.set(&ev, value.text)
				notice, err := governance.BuildNotice(ev)
				if err != nil || notice.Action != strings.TrimSpace(ev.Action) ||
					(field.maintainer && !strings.Contains(notice.Body, strings.Join(ev.TriedPaths, "；"))) {
					t.Errorf("TABBED_COMMAND_BOUNDARY_CHANGED: notice = %+v, err = %v", notice, err)
				}
			})
		}
	}
	t.Run("identifier_precedence", func(t *testing.T) {
		ev := validEvent()
		ev.CRID = "bad\tid"
		ev.Action = "sudo\tstatus"
		_, err := governance.BuildNotice(ev)
		if err == nil || err.Error() != "NOTICE_IDENTIFIER_INVALID" {
			t.Error("TABBED_COMMAND_IDENTIFIER_PRECEDENCE_CHANGED")
		}
	})
	t.Run("length_boundary", func(t *testing.T) {
		ev := validEvent()
		ev.Action = strings.Repeat("x", 1194) + "sudo\tX"
		_, err := governance.BuildNotice(ev)
		if err == nil || !strings.Contains(err.Error(), "NOTICE_ACTION_MUST_BE_HUMAN") {
			t.Error("TABBED_COMMAND_1200_BYTE_GUARD_MISSING")
		}
		ev.Action = "x" + ev.Action
		_, err = governance.BuildNotice(ev)
		if err == nil || !strings.Contains(err.Error(), "NOTICE_BODY_VERBATIM_PAYLOAD") {
			t.Error("TABBED_COMMAND_1201_BYTE_PRECEDENCE_CHANGED")
		}
	})
	for _, cause := range []string{"authorization-required", "environment-failure"} {
		t.Run("long_tried_path_command_precedence/"+cause, func(t *testing.T) {
			ev := validEvent()
			ev.Cause = cause
			ev.TriedPaths = []string{"checked logs", strings.Repeat("x", 1200) + "sudo\tX"}
			notice, err := governance.BuildNotice(ev)
			if err == nil || !strings.Contains(err.Error(), "NOTICE_ACTION_MUST_BE_HUMAN") || notice != (governance.Notice{}) {
				t.Errorf("LONG_TRIED_PATH_TABBED_COMMAND_GUARD_MISSING: notice = %+v, err = %v", notice, err)
			}
			outcome, err := governance.DeliverNotice(context.Background(), nil, ev, nil)
			if err == nil || !strings.Contains(err.Error(), "NOTICE_ACTION_MUST_BE_HUMAN") || outcome != (governance.NoticeOutcome{}) {
				t.Errorf("LONG_TRIED_PATH_DELIVERY_GUARD_MISSING: outcome = %+v, err = %v", outcome, err)
			}
		})
	}
	t.Run("multiline_and_multiple_tabs", func(t *testing.T) {
		ev := validEvent()
		ev.Action = "Review context\nsudo\t\tstatus"
		_, err := governance.BuildNotice(ev)
		if err == nil || !strings.Contains(err.Error(), "NOTICE_ACTION_MUST_BE_HUMAN") {
			t.Error("MULTILINE_TABBED_COMMAND_GUARD_MISSING")
		}
	})
	t.Run("rendered_field_precedence", func(t *testing.T) {
		ev := validEvent()
		ev.ErrorCode = "bad\tcode"
		ev.Action = "sudo\tstatus"
		_, err := governance.BuildNotice(ev)
		if err == nil || err.Error() != "NOTICE_RENDERED_FIELD_INVALID" {
			t.Error("TABBED_COMMAND_PRECEDENCE_CHANGED")
		}
	})
	t.Run("silent_event", func(t *testing.T) {
		ev := validEvent()
		ev.Kind = "run-node-started"
		ev.Action = "sudo\tstatus"
		outcome, err := governance.DeliverNotice(context.Background(), nil, ev, nil)
		if err != nil || outcome.State != "silent" || outcome.Created || outcome.Broadcast {
			t.Error("TABBED_COMMAND_SILENT_BEHAVIOR_CHANGED")
		}
	})
}

func TestNoticeRenderedFieldsPositiveControls(t *testing.T) {
	t.Run("ordinary maintainer", func(t *testing.T) {
		ev := validEvent()
		ev.Cause = "environment-failure"
		ev.ErrorCode = " ENV_UNAVAILABLE "
		ev.EvidenceRef = " validation/env.md "
		ev.TriedPaths = []string{"restart runner", "retry with same grant"}
		notice, err := governance.BuildNotice(ev)
		if err != nil {
			t.Fatal("ordinary maintainer notice rejected")
		}
		want := "CR " + ev.CRID + " · " + ev.Cause + "\n结论：Authorization is required\n错误：ENV_UNAVAILABLE\n证据：validation/env.md\n所需动作：Review the requested scope\n已试路径：restart runner；retry with same grant"
		if notice.Body != want || notice.ErrorCode != "ENV_UNAVAILABLE" || notice.Audience != governance.NoticeAudienceMaintainer || notice.Severity != "attention" || notice.DedupeKey != governance.NoticeDedupeKey(ev.CRID, ev.Cause, ev.EvidenceDigest, notice.Audience) {
			t.Error("ordinary maintainer rendering changed")
		}
	})
	t.Run("unrendered values", func(t *testing.T) {
		ev := validEvent()
		ev.ErrorCode = strings.Repeat(" ", 1201)
		ev.TriedPaths = []string{"[1, 2]", strings.Repeat("x", 1201)}
		notice, err := governance.BuildNotice(ev)
		if err != nil {
			t.Fatal("unrendered fields rejected")
		}
		want := "CR " + ev.CRID + " · " + ev.Cause + "\n结论：Authorization is required\n所需动作：Review the requested scope"
		if notice.Body != want || notice.ErrorCode != "" || notice.Audience != governance.NoticeAudienceAuthorizer || notice.Severity != "action_required" {
			t.Error("authorizer rendering changed")
		}
	})
	t.Run("per item and trimmed boundaries", func(t *testing.T) {
		ev := validEvent()
		ev.Cause = "credential-failure"
		ev.ErrorCode = " " + strings.Repeat("c", 1200) + " "
		ev.TriedPaths = []string{strings.Repeat("a", 700), strings.Repeat("b", 700), strings.Repeat(" ", 1201), "[not json"}
		notice, err := governance.BuildNotice(ev)
		if err != nil {
			t.Fatal("legal per-item values rejected")
		}
		if notice.ErrorCode != strings.TrimSpace(ev.ErrorCode) || !strings.Contains(notice.Body, "已试路径："+strings.Join(ev.TriedPaths, "；")) {
			t.Error("legal per-item rendering changed")
		}
	})
	t.Run("hidden command remains rejected", func(t *testing.T) {
		ev := validEvent()
		ev.TriedPaths = []string{"sudo restart"}
		_, err := governance.BuildNotice(ev)
		if err == nil || !strings.Contains(err.Error(), "NOTICE_ACTION_MUST_BE_HUMAN") {
			t.Error("existing tried-path command guard changed")
		}
	})
}
