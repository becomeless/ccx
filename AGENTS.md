# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this is

`ccx` is a Codex API switcher (terminal command: `xx`). It switches Codex between the
official account and third-party Anthropic-compatible APIs (DeepSeek, 智谱GLM, 小米MiMo, …). It is a
PowerShell-only project with no build step, no dependencies, and no test suite.

## The one inviolable design rule

**ccx never writes any Claude Code config file** — not `~/.claude/settings.json`, never `~/.claude.json`
(where MCP config lives). API switching works *purely* through environment variables. This is the entire
reason the tool exists (it cannot clobber a user's MCP / plugins / hooks). ccx may write its own runtime
data under `~/.cc-mini/` and, on Unix, an isolated marker block in the shell startup file to persist the
default environment. Any change that writes a Claude Code config file is out of scope and will be rejected
— see the "设计原则与初心" section of `README.md`. When in doubt, prefer the change that keeps the tool
*simpler*, not more capable.

It only ever touches these 7 "managed" environment variables (`$script:KnownKeys` in `xx.ps1`), and
clears the ones a target profile doesn't use:

```
ANTHROPIC_BASE_URL  ANTHROPIC_AUTH_TOKEN  ANTHROPIC_API_KEY
ANTHROPIC_DEFAULT_OPUS_MODEL  ANTHROPIC_DEFAULT_SONNET_MODEL  ANTHROPIC_DEFAULT_HAIKU_MODEL
CLAUDE_CODE_EFFORT_LEVEL
```

Note it deliberately does NOT set `ANTHROPIC_MODEL` — model selection stays with `/model` in-session,
and the three `*_MODEL` mapping vars translate `opus`/`sonnet`/`haiku` to each provider's real model name.

## Two activation modes (core concept)

These two functions in `xx.ps1` are the heart of the tool:

- **`Session-Launch`** ("本次启用") — sets the managed vars on the *current process only* via `Set-Item Env:`,
  then launches `Codex`. Process-scoped, ephemeral, lets multiple terminals each run a different API in
  parallel without interfering.
- **`Set-Default`** ("设为默认") — writes the managed vars as *user* environment variables via
  `[Environment]::SetEnvironmentVariable(..., $script:DefaultScope)` (default `User`). Affects only
  *newly opened* terminals; running sessions are unaffected because env vars freeze at process start.

The `-DefaultScope Process` param exists only for testing `Set-Default` without persisting to the user
environment.

## Files

- `xx.ps1` — the entire application (menu UI, profile CRUD, the two activation modes). Self-contained.
- `presets.json` — the **供应商 (provider) catalog** shown when creating/editing a 配置 (profile). Each
  entry is `{ name, auth, urls:[{label,url}], models:{opus,sonnet,haiku}, effort? }`. Picking a provider
  auto-fills the profile's base URL (a chooser appears if it has multiple `urls`, e.g. an API endpoint vs
  a token-plan endpoint) plus the recommended model mappings and auth field. `xx.ps1` has a built-in
  fallback (`$BuiltinPresetsJson`) if the file is missing. Add an entry here to offer a new provider,
  no code change needed.
- `install.ps1` — registers an `xx` function in the user's PowerShell `$PROFILE`, wrapped in
  `# >>> xx >>>` / `# <<< xx <<<` markers (idempotent; also strips a legacy `ccswitch` block).
- `ccx.psm1` / `ccx.psd1` — thin PowerShell Gallery module wrapper. `xx` runs `xx.ps1` in a *separate*
  `pwsh -NoProfile` subprocess so session-scoped env vars never leak into the caller's shell.
- `publish-psgallery.ps1` — publishes to PowerShell Gallery.
- `README.md` / `README.en.md` — keep these in sync; they are the primary user docs.

## Runtime data (not in repo)

- `~/.cc-mini/providers.json` — user's profiles, **including plaintext keys**. Created on first run from
  `$DefaultStoreJson` (官方 + DeepSeek + 智谱GLM + 小米MiMo, keys empty). Read via `Get-Store`, written via
  `Save-Store`. Never commit this.

## Common commands

```powershell
# Run without installing
pwsh -File .\xx.ps1               # interactive menu
pwsh -File .\xx.ps1 DeepSeek      # set "DeepSeek" profile as default
pwsh -File .\xx.ps1 DeepSeek -Session   # activate for this terminal + launch Codex
pwsh -File .\xx.ps1 -List         # list profiles and their state

# Install the `xx` command into $PROFILE
pwsh -ExecutionPolicy Bypass -File .\install.ps1

# Publish to PowerShell Gallery (prefers Publish-PSResource to avoid a PowerShellGet 2.x
# localization bug; bump ModuleVersion in ccx.psd1 first)
pwsh -File .\publish-psgallery.ps1 -ApiKey <key>
```

There are no tests, linters, or build artifacts. Verify changes by running `xx.ps1` directly.

## Conventions

- Target **PowerShell 7+** (`pwsh`); primarily validated on Windows.
- All file writes use UTF-8 **without BOM** (`$Utf8NoBom` / `New-Object System.Text.UTF8Encoding($false)`) —
  match this when writing JSON or `$PROFILE`.
- The UI is Chinese; user-facing strings and docs are in Chinese (English README is a mirror).
- Terminology: a saved entry is a **配置 (profile)**; the `presets.json` catalog entries are **供应商
  (providers)**. A profile *references* a provider — multiple profiles may share one provider (e.g. two
  DeepSeek keys), so the profile's `name` is no longer typed by hand; it's set from the chosen provider
  and `Resolve-UniqueName` appends ` 2`/` 3`… on collision. `name` is still the unique key everything
  (`store.current`, `xx <name>`, delete) is keyed on; the `note` field disambiguates same-provider rows.
