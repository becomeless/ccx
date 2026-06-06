// Package check performs a minimal read-only connectivity probe for a profile.
package check

import (
	"context"
	"errors"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/becomeless/cc-x/internal/config"
	"github.com/becomeless/cc-x/internal/i18n"
)

const timeout = 5 * time.Second

// Result is a localized probe result.
type Result struct {
	OK      bool
	Message string
}

// Profile probes GET {base}/v1/models with the profile's configured auth.
func Profile(p config.Provider) Result {
	m := config.GetProviderEnvMap(p)
	base := strings.TrimSpace(m["ANTHROPIC_BASE_URL"])
	if base == "" {
		return Result{Message: i18n.T("check.noUrl")}
	}

	header := authHeader(m)
	if header == "" {
		return Result{Message: i18n.T("check.noKey")}
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	nullDev := "/dev/null"
	if runtime.GOOS == "windows" {
		nullDev = "NUL"
	}
	cmd := exec.CommandContext(ctx, "curl", "-sS", "-o", nullDev, "-w", "%{http_code}",
		"--connect-timeout", "3", "--max-time", "5",
		"-H", header,
		"-H", "anthropic-version: 2023-06-01",
		strings.TrimRight(base, "/")+"/v1/models")
	out, err := cmd.Output()
	if ctx.Err() == context.DeadlineExceeded {
		return Result{Message: i18n.T("check.timeout")}
	}

	code := strings.TrimSpace(string(out))
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			switch ee.ExitCode() {
			case 6:
				return Result{Message: i18n.T("check.dns")}
			case 28:
				return Result{Message: i18n.T("check.timeout")}
			}
		}
		return Result{Message: i18n.T("check.network")}
	}

	switch {
	case strings.HasPrefix(code, "2"):
		return Result{OK: true, Message: i18n.T("check.ok", code)}
	case code == "401" || code == "403":
		return Result{Message: i18n.T("check.auth", code)}
	case code == "404":
		return Result{Message: i18n.T("check.notFound", code)}
	default:
		return Result{Message: i18n.T("check.http", code)}
	}
}

func authHeader(m map[string]string) string {
	if key := strings.TrimSpace(m["ANTHROPIC_API_KEY"]); key != "" {
		return "x-api-key: " + key
	}
	if tok := strings.TrimSpace(m["ANTHROPIC_AUTH_TOKEN"]); tok != "" {
		return "Authorization: Bearer " + tok
	}
	return ""
}
