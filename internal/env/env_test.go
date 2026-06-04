package env

import (
	"os"
	"testing"

	"github.com/becomeless/cc-x/internal/config"
)

func TestComputeManagedVals(t *testing.T) {
	p := config.Provider{Name: "x", Env: map[string]string{
		"ANTHROPIC_BASE_URL":       "https://e.x",
		"ANTHROPIC_AUTH_TOKEN":     "  ", // 仅空白 -> 视为清除
		"ANTHROPIC_API_KEY":        "k",
		"CLAUDE_CODE_EFFORT_LEVEL": "max",
	}}
	vals := ComputeManagedVals(p)
	if len(vals) != len(config.ManagedKeys()) {
		t.Fatalf("应含全部 %d 键，got %d", len(config.ManagedKeys()), len(vals))
	}
	if vals["ANTHROPIC_BASE_URL"] != "https://e.x" || vals["ANTHROPIC_API_KEY"] != "k" || vals["CLAUDE_CODE_EFFORT_LEVEL"] != "max" {
		t.Fatalf("有值键未保留：%+v", vals)
	}
	for _, k := range []string{"ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL"} {
		if vals[k] != "" {
			t.Fatalf("空/缺键应为清除(\"\")，%s=%q", k, vals[k])
		}
	}
}

func TestApplyManaged(t *testing.T) {
	// 预置一个受管键，验证目标配置没用它时会被清除。
	os.Setenv("ANTHROPIC_AUTH_TOKEN", "stale")
	defer os.Unsetenv("ANTHROPIC_AUTH_TOKEN")
	defer os.Unsetenv("ANTHROPIC_BASE_URL")

	ApplyManaged(config.Provider{Name: "x", Env: map[string]string{"ANTHROPIC_BASE_URL": "https://e.x"}})

	if got := os.Getenv("ANTHROPIC_BASE_URL"); got != "https://e.x" {
		t.Fatalf("BASE_URL 应被设置，got %q", got)
	}
	if _, ok := os.LookupEnv("ANTHROPIC_AUTH_TOKEN"); ok {
		t.Fatalf("AUTH_TOKEN 应被清除")
	}
}
