// Package runtimeinfo formats read-only facts about the current terminal.
package runtimeinfo

import (
	"net/url"
	"os"
	"strings"

	"github.com/becomeless/cc-x/internal/config"
	"github.com/becomeless/cc-x/internal/i18n"
)

// CurrentTerminalLine returns a localized, key-safe description of the API
// currently visible to this terminal process.
func CurrentTerminalLine(store *config.Store) string {
	return i18n.T("terminal.current", currentTerminalTarget(store))
}

func currentTerminalTarget(store *config.Store) string {
	base := strings.TrimSpace(os.Getenv("ANTHROPIC_BASE_URL"))
	if base == "" {
		return i18n.T("terminal.official")
	}

	host := hostOf(base)
	for _, p := range store.Providers {
		pbase := strings.TrimSpace(config.GetProviderEnvMap(p)["ANTHROPIC_BASE_URL"])
		if sameBase(base, pbase) {
			return i18n.T("terminal.matched", host, i18n.ProviderDisplayName(p))
		}
	}
	return i18n.T("terminal.unmatched", host)
}

func sameBase(a, b string) bool {
	return strings.TrimRight(strings.TrimSpace(a), "/") == strings.TrimRight(strings.TrimSpace(b), "/")
}

func hostOf(raw string) string {
	u, err := url.Parse(raw)
	if err == nil && u.Host != "" {
		return u.Host
	}
	return raw
}
