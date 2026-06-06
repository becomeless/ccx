package runtimeinfo

import (
	"testing"

	"github.com/becomeless/cc-x/internal/config"
	"github.com/becomeless/cc-x/internal/i18n"
)

// currentTerminalTarget：空地址=官方态；命中配置（含尾斜杠规范化）显示 host→名；否则未匹配。
func TestCurrentTerminalTarget(t *testing.T) {
	i18n.SetLang(config.LangEN)
	store := &config.Store{Providers: []config.Provider{
		{Name: "DeepSeek", Env: map[string]string{"ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic"}},
	}}

	cases := []struct {
		name string
		base string
		want string
	}{
		{"official", "", i18n.T("terminal.official")},
		{"matched", "https://api.deepseek.com/anthropic", i18n.T("terminal.matched", "api.deepseek.com", "DeepSeek")},
		{"trailingSlash", "https://api.deepseek.com/anthropic/", i18n.T("terminal.matched", "api.deepseek.com", "DeepSeek")},
		{"spaces", "  https://api.deepseek.com/anthropic  ", i18n.T("terminal.matched", "api.deepseek.com", "DeepSeek")},
		{"unmatched", "https://unknown.example.com/x", i18n.T("terminal.unmatched", "unknown.example.com")},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Setenv("ANTHROPIC_BASE_URL", c.base)
			if got := currentTerminalTarget(store); got != c.want {
				t.Errorf("got %q want %q", got, c.want)
			}
		})
	}
}
