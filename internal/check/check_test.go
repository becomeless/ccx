package check

import (
	"testing"

	"github.com/becomeless/cc-x/internal/config"
	"github.com/becomeless/cc-x/internal/i18n"
)

// classifyHTTP：状态码 -> 结果分层（OK 标志 + 文案 key）。
func TestClassifyHTTP(t *testing.T) {
	i18n.SetLang(config.LangEN)
	cases := []struct {
		code    string
		wantOK  bool
		wantKey string
	}{
		{"200", true, "check.ok"},
		{"201", true, "check.ok"},
		{"401", false, "check.auth"},
		{"403", false, "check.auth"},
		{"404", false, "check.notFound"},
		{"429", false, "check.http"},
		{"500", false, "check.http"},
	}
	for _, c := range cases {
		r := classifyHTTP(c.code)
		if r.OK != c.wantOK {
			t.Errorf("code %s: OK=%v want %v", c.code, r.OK, c.wantOK)
		}
		if want := i18n.T(c.wantKey, c.code); r.Message != want {
			t.Errorf("code %s: message=%q want %q", c.code, r.Message, want)
		}
	}
}

// authHeader：API_KEY 优先于 AUTH_TOKEN；都缺返回空。
func TestAuthHeader(t *testing.T) {
	cases := []struct {
		name string
		m    map[string]string
		want string
	}{
		{"apiKey", map[string]string{"ANTHROPIC_API_KEY": "k"}, "x-api-key: k"},
		{"token", map[string]string{"ANTHROPIC_AUTH_TOKEN": "t"}, "Authorization: Bearer t"},
		{"none", map[string]string{}, ""},
		{"apiKeyWins", map[string]string{"ANTHROPIC_API_KEY": "k", "ANTHROPIC_AUTH_TOKEN": "t"}, "x-api-key: k"},
		{"blankIgnored", map[string]string{"ANTHROPIC_API_KEY": "  ", "ANTHROPIC_AUTH_TOKEN": "t"}, "Authorization: Bearer t"},
	}
	for _, c := range cases {
		if got := authHeader(c.m); got != c.want {
			t.Errorf("%s: got %q want %q", c.name, got, c.want)
		}
	}
}

// Profile 的无网络早返回：缺地址 / 缺密钥（不触发 curl）。
func TestProfileEarlyReturns(t *testing.T) {
	i18n.SetLang(config.LangEN)

	noURL := Profile(config.Provider{Name: "X", Env: map[string]string{}})
	if noURL.OK || noURL.Message != i18n.T("check.noUrl") {
		t.Errorf("noUrl: got %+v", noURL)
	}

	noKey := Profile(config.Provider{Name: "X", Env: map[string]string{"ANTHROPIC_BASE_URL": "https://x.example.com"}})
	if noKey.OK || noKey.Message != i18n.T("check.noKey") {
		t.Errorf("noKey: got %+v", noKey)
	}
}
