package guardprobe

import "testing"

func TestCommandGuardTabs(t *testing.T) {
	for _, command := range []string{"sudo", "psql", "kubectl", "podman", "docker"} {
		for _, sep := range []struct {
			name  string
			value string
		}{{"space", " "}, {"tab", "\t"}} {
			t.Run(sep.name+"_"+command, func(t *testing.T) {
				if !looksLikeCommandShipping("Review context: " + command + sep.value + "status") {
					t.Errorf("command guard missed %s followed by %s", command, sep.name)
				}
			})
		}
	}
}

func TestCommandGuardExistingBehavior(t *testing.T) {
	for _, tc := range []struct {
		name string
		text string
		want bool
	}{
		{"ordinary_tab", "Review\tthe evidence", false},
		{"prefix_not_command", "dockerfile\treview", false},
		{"literal_backslash_t", "sudo\\tstatus", false},
		{"trailing_tab", "Review: sudo\t\t ", false},
		{"existing_shell_chain", "check && report", true},
		{"unicode_separator_dollar", "review\u2028$ command", true},
		{"unicode_separator_shebang", "review\u2029#!/bin/sh", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := looksLikeCommandShipping(tc.text); got != tc.want {
				t.Errorf("guard = %v, want %v", got, tc.want)
			}
		})
	}
}
