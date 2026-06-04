# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this is

`ccx` is a Claude Code API switcher (terminal command: `xx`). It switches Claude Code between the
official account and third-party Anthropic-compatible APIs (DeepSeek, 智谱GLM, 小米MiMo, …).

There are now two active lines. The npm/TypeScript package `@cc-x/cc-x` (command still `xx`) remains
the cross-platform npm line for Windows / macOS / Linux; source is under `src/`, builds to `dist/` via
`tsc`, and ships through npm. The Go native line under `cmd/` and `internal/` has reached behavior
parity on Windows and is entering GitHub Release distribution; see `docs/go-rewrite-plan.md` and
`docs/go-release-guide.md`. Bun/SEA is intentionally skipped.

Before changing the npm edition, read `docs/npm-rewrite-plan.md`; it is the implementation source of
truth. `@cc-x/cc-x@0.3.0` was first published on 2026-06-02.

## The one inviolable design rule

**ccx never writes any Claude Code config file** — not `~/.claude/settings.json`, never `~/.claude.json`
(where MCP config lives). API switching works *purely* through environment variables. This is the entire
reason the tool exists (it cannot clobber a user's MCP / plugins / hooks). ccx may write its own runtime
data under `~/.cc-mini/` and, on Unix, an isolated marker block in the shell startup file to persist the
default environment. Any change that writes a Claude Code config file is out of scope and will be rejected
— see the "设计原则与初心" section of `README.md`. When in doubt, prefer the change that keeps the tool
*simpler*, not more capable.

It only ever touches these 7 "managed" environment variables (`KNOWN_KEYS` in `src/config/types.ts`),
and clears the ones a target profile doesn't use:

```
ANTHROPIC_BASE_URL  ANTHROPIC_AUTH_TOKEN  ANTHROPIC_API_KEY
ANTHROPIC_DEFAULT_OPUS_MODEL  ANTHROPIC_DEFAULT_SONNET_MODEL  ANTHROPIC_DEFAULT_HAIKU_MODEL
CLAUDE_CODE_EFFORT_LEVEL
```

Note it deliberately does NOT set `ANTHROPIC_MODEL` — model selection stays with `/model` in-session,
and the three `*_MODEL` mapping vars translate `opus`/`sonnet`/`haiku` to each provider's real model name.

## Two activation modes (core concept)

These two actions are the heart of the tool:

- **"本次启用"** — launches `claude` with managed vars applied only to the child process. Ephemeral;
  multiple terminals can use different APIs in parallel without interfering.
- **"设为默认"** — persists managed vars for newly opened terminals: Windows user environment variables
  in the registry, or an isolated marker block in a Unix shell startup file. Running sessions are
  unaffected because env vars freeze at process start.

The npm edition implements them in `src/env/session.ts` / `src/env/default.ts`; the Go edition
implements them in `internal/env`, `internal/launch`, and `internal/defaults`. The
`--default-scope process` option exists only for tests.

## Files

- `src/` — npm/TypeScript edition (CLI, profile CRUD, TUI, i18n, and the two activation modes).
- `cmd/` / `internal/` — Go native edition (same behavior contract; Windows native Release first).
- `scripts/build-windows-release.ps1` / `install.ps1` — Go Windows release packaging and installer.
- `package.json` — npm package metadata. The public package is `@cc-x/cc-x`; the installed command is `xx`.
- `presets.json` — the **供应商 (provider) catalog** shown when creating/editing a 配置 (profile). Each
  entry is `{ name, auth, urls:[{label,url}], models:{opus,sonnet,haiku}, effort? }`. Picking a provider
  auto-fills the profile's base URL (a chooser appears if it has multiple `urls`, e.g. an API endpoint vs
  a token-plan endpoint) plus the recommended model mappings and auth field. Add an entry here to offer
  a new provider, no code change needed. Both editions have built-in fallbacks.
- `README.md` / `README.en.md` — keep these in sync; they are the primary user docs.

## Runtime data (not in repo)

- `~/.cc-mini/providers.json` — user's profiles, **including plaintext keys**. Created on first run from
  built-in defaults (官方 + DeepSeek + 智谱GLM + 小米MiMo, keys empty). The npm edition reads/writes it via
  `loadStore` / `saveStore`; the Go edition reads/writes it via `internal/config`. Never commit this.

## Common commands

```powershell
# Build, verify, run
npm run typecheck
npm run build
node .\dist\index.js --version
node .\dist\index.js --list

# Go native line (Go may be installed at ~/go-sdk/go/bin/go.exe on this machine)
$go = "$HOME\go-sdk\go\bin\go.exe"
& $go test ./...
& $go vet ./...
& $go build ./cmd/xx
.\scripts\build-windows-release.ps1 -Version 0.4.1

# Published package
npm install -g @cc-x/cc-x
xx --version
```

The npm edition has gitignored smoke scripts under `_smoke/`; run the relevant scripts with
`npx tsx _smoke/<script>.ts` when changing shared behavior. Always run `npm run typecheck` and
`npm run build`.

## Conventions

- The maintained edition targets **Node.js 18+** and Windows / macOS / Linux.
- All file writes use UTF-8 **without BOM**; match this when writing JSON, `$PROFILE`, or Unix rc blocks.
- The npm UI supports zh/en i18n; keep `README.md` / `README.en.md` in sync.
- Terminology: a saved entry is a **配置 (profile)**; the `presets.json` catalog entries are **供应商
  (providers)**. A profile *references* a provider — multiple profiles may share one provider (e.g. two
  DeepSeek keys), so the profile's `name` is no longer typed by hand; it's set from the chosen provider
  and `Resolve-UniqueName` appends ` 2`/` 3`… on collision. `name` is still the unique key everything
  (`store.current`, `xx <name>`, delete) is keyed on; the `note` field disambiguates same-provider rows.
