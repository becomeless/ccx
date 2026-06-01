# ccx

> [简体中文](README.md) | English

**A Claude Code API switcher** (terminal command: `xx`). Quickly switch Claude Code
between the official account and third-party Anthropic-compatible APIs (DeepSeek,
Zhipu GLM, Xiaomi MiMo, etc.).

What makes it different: **it never writes any config file**. It works purely through
environment variables, so it is **physically incapable of clobbering your MCP servers,
plugins, or hooks** — and it lets **multiple terminals each run a different API at the
same time, without interfering with one another**.

---

## Why it exists

Claude Code can talk to different API backends via environment variables, but switching
by hand is tedious: editing `settings.json` or typing long `export`s, plus third-party
APIs need **model mappings** (they only know their own model names), and there's no neat
way to give each of several parallel terminals a different API. ccx folds all of that
into one command, `xx`: pick a provider, then either **use it for this terminal only** or
**set it as the default** for future terminals.

## ccx vs cc-switch

cc-switch is an excellent all-in-one **GUI** — if you want a graphical app, want to manage
MCP centrally, and also switch Codex / Gemini and other CLIs, it fits better. ccx takes the
opposite, **minimal** approach:

| | ccx (command `xx`) | cc-switch |
|---|---|---|
| Form | Terminal command (lightweight) | Desktop GUI (full-featured) |
| Scope | Only switches the API | API + MCP + multiple CLIs + prompts… |
| Touches config files? | **No** (env vars only) | Rewrites config files from its own DB |
| Can lose MCP / plugins? | **Impossible by design** | Users have reported it overwriting them |
| Different API per terminal | **Native** (process-level isolation) | Global switch; sessions can interfere |

**ccx fits you if you** live in the terminal, often run **several terminals with different
APIs in parallel**, have been burned by a switcher corrupting your config/MCP, or simply
want the one job done with zero extra features.

**cc-switch fits you if you** want a GUI, need to manage MCP and several AI CLIs in one
place, or prefer an all-in-one tool.

## Safety

- **Writes no config files.** It never touches `~/.claude/settings.json`, and never opens
  `~/.claude.json` (where your MCP config lives). MCP / plugins / hooks / permissions
  cannot be affected.
- It only ever sets/clears these 7 "managed" variables, nothing else:
  `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`,
  `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`,
  `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `CLAUDE_CODE_EFFORT_LEVEL`.
- On switch it clears the managed variables the target profile doesn't use (the two auth
  fields are mutually exclusive), so nothing leaks from the previous provider.

> 💡 **About `settings.json` and other Claude Code config files:** don't manage them with
> third-party tools (ccx deliberately doesn't either). To change them, use Claude Code's own
> `/update-config` and just describe what you want in natural language (e.g. "allow npm
> commands", "switch to dark theme") — Claude Code maintains the file itself, which is safer
> than letting an external tool rewrite it.

## Requirements

- **PowerShell 7+ (`pwsh`)** — installable on Windows / macOS / Linux. Currently verified
  mainly on Windows; on other platforms "Set as default" relies on user environment
  variables and behavior may differ slightly.
- **Claude Code installed (`claude` on PATH)** — "Use this session" launches `claude`.

## Install

**Option 1: PowerShell Gallery (recommended)**

```powershell
Install-Module ccx
```

Then type `xx` in any terminal (the module auto-loads). Update with `Update-Module ccx`;
remove with `Uninstall-Module ccx`.

**Option 2: from source (dev / custom)**

```powershell
git clone https://github.com/becomeless/ccx
pwsh -ExecutionPolicy Bypass -File .\ccx\install.ps1
```

This registers an `xx` function in your PowerShell `$PROFILE` (wrapped in `# >>> xx >>>`
markers, idempotent). **Open a new terminal** afterwards. You can also skip install and just
run `pwsh -File path\xx.ps1`.

## Quick start

1. Open a new terminal and run `xx`. On first run it creates 4 default profiles in
   `~/.cc-mini/providers.json` (official + DeepSeek + Zhipu GLM + Xiaomi MiMo) with
   **empty keys**.
2. Use ↑↓ to pick a profile → Enter → "Edit" → enter your **API key** (done locally).
3. Then either choose **Set as default** (open a new terminal, bare `claude` uses it) or
   **Use this session** (launches Claude in the current terminal immediately).

## The two activation modes (core concept)

Which API Claude uses is ultimately decided by **environment variables**. ccx offers two
scopes:

| | Use this session | Set as default |
|---|---|---|
| Mechanism | Sets env vars in **the current process only**, then launches `claude` | Writes **user environment variables** |
| Scope | This terminal only, **gone when it closes** | Future **newly opened** terminals' bare `claude` |
| Effect on other / running sessions | **None** | **None** (env is fixed at process start) |
| Typical use | Parallel terminals, each on a different API | Your usual "main" API |

**Parallel example:** open 4 terminals and run `xx 官方 -Session`, `xx DeepSeek -Session`,
`xx 智谱GLM -Session`, `xx 小米MiMo -Session` — four Claude sessions running at once, each
on its own API, independent.

**Why not switch via a global config file?** Because `settings.json` is global and editing
it can disturb **running** sessions (e.g. another terminal suddenly erroring with
`... cannot be parsed as a URL`). ccx avoids this with env vars: per-process isolation plus
a user-level default.

## Menu

Run `xx` for the interactive menu (`↑↓` move, `Enter` select, `q`/`Esc` quit; number keys
also work). With a profile highlighted, press **`Shift+↑↓` (or `PgUp`/`PgDn`) to move it
up/down and reorder** — saved instantly:

- **Select a profile → Enter** opens the action menu:
  - **Use this session** — sets env for this terminal and launches Claude now.
  - **Set as default** — writes user env vars; **open a new terminal** for bare `claude` to
    pick it up; running sessions unaffected.
  - **Edit** — opens the form (below).
  - **Delete** — removes the profile (with confirmation; keep "官方").
  - **Back**.
- **+ New profile** / **Quit**.

**Edit form:** `↑↓` to pick a field, `Enter` to edit it; scroll past the fields to choose
"Save & return" / "Discard". Inside a field, **Enter = keep unchanged**, `-` = clear,
`Esc` = cancel that field. The first field is **"Provider"**: pick a provider (from the
catalog) and it **auto-fills** the API URL, the three model mappings, and the auth field
(if the provider has multiple API URLs — e.g. Xiaomi MiMo's pay-as-you-go API vs TokenPlan —
you choose one). "Note" is free text. "API URL" can also be opened on its own to override
(catalog + already-used URLs + manual entry).

> "Provider" is a picker — press `Esc` to cancel in one key. "Note" uses plain input
> (Enter = keep, `-` = clear; CJK input-method friendly).

## CLI usage

```powershell
xx                       # interactive menu
xx DeepSeek              # "Set as default" to the profile named DeepSeek
xx DeepSeek -Session     # "Use this session" and launch Claude
xx -List                 # list all profiles and their status
```

## Profile fields

| Field | Env var | Notes |
|---|---|---|
| Provider | — | Picked from the catalog; auto-fills API URL / models / auth field. Also the profile's unique id — collisions get a ` 2`/` 3`… suffix (see "Multiple accounts") |
| Note | — | Free text; tells apart multiple profiles of the same provider |
| API URL | `ANTHROPIC_BASE_URL` | Third-party endpoint; empty = official login |
| Auth field | — | Whether the key goes into `AUTH_TOKEN` or `API_KEY` |
| API key | `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_API_KEY` | Value for the chosen auth field |
| opus → model | `ANTHROPIC_DEFAULT_OPUS_MODEL` | model the `opus` tier maps to |
| sonnet → model | `ANTHROPIC_DEFAULT_SONNET_MODEL` | model the `sonnet` tier maps to |
| haiku → model | `ANTHROPIC_DEFAULT_HAIKU_MODEL` | model for `haiku`; **also used by background tasks** |
| effort | `CLAUDE_CODE_EFFORT_LEVEL` | thinking depth (see below) |

> ccx deliberately does **not** set `ANTHROPIC_MODEL` nor touch the `model` field in
> `settings.json`. Pick a tier live with `/model opus|sonnet|haiku`; the mapping translates
> it to the provider's model.

## Model mapping & effort

Third-party APIs **must** have model mappings, because they only accept their own model
names while Claude Code defaults to `claude-*`. Background tasks use the `haiku` tier, so
**`haiku → model` must be set too** (otherwise background calls fail).

**effort:** `low < medium < high < xhigh < max`; higher = smarter but slower / more tokens;
`auto` = the model's default; empty = unset. effort is a Claude-model feature — whether a
third party honors it depends on its implementation.

| Profile | BASE_URL | OPUS / SONNET | HAIKU | effort |
|---|---|---|---|---|
| 官方 (official) | (empty = login) | — | — | empty / `auto` |
| DeepSeek | `https://api.deepseek.com/anthropic` | `deepseek-v4-pro` | `deepseek-v4-flash` | `max` (per their docs) |
| Zhipu GLM | `https://open.bigmodel.cn/api/anthropic` | `GLM-4.7` | `glm-4.5-air` | empty |
| Xiaomi MiMo | `https://api.xiaomimimo.com/anthropic` (pay-as-you-go)<br>`https://token-plan-cn.xiaomimimo.com/anthropic` (TokenPlan) | `mimo-v2.5-pro` | `mimo-v2.5-pro` | empty |

> Model names change as providers update; follow each provider's official docs.

## Auth field: AUTH_TOKEN vs API_KEY

| Option | Actual header | Used by |
|---|---|---|
| `ANTHROPIC_AUTH_TOKEN` (default) | `Authorization: Bearer <key>` | most third-party relays |
| `ANTHROPIC_API_KEY` | `x-api-key: <key>` | official API and a few relays |

Some endpoints accept only one; the wrong one yields 401. Switch it in the Edit form;
ccx clears the other on switch to avoid conflicts.

## Multiple accounts

For multiple accounts of the same vendor (e.g. personal vs work DeepSeek keys): **just
create multiple profiles**. Picking the same provider a second time auto-names it
`DeepSeek 2`; use the **Note** field to mark "personal / work". The list shows them as
"Provider — Note", easy to tell apart.

## Maintaining the provider catalog

`presets.json` (ships with the tool) is the **provider catalog** — the "Provider" choices
when creating/editing a profile come from here. Add a provider, no code change. Each entry:

```json
[
  {
    "name": "DeepSeek",
    "auth": "AUTH_TOKEN",
    "effort": "max",
    "urls": [ { "label": "Anthropic-compatible", "url": "https://api.deepseek.com/anthropic" } ],
    "models": { "opus": "deepseek-v4-pro", "sonnet": "deepseek-v4-pro", "haiku": "deepseek-v4-flash" }
  }
]
```

- `urls` may contain **multiple** entries (e.g. a vendor splitting its API and TokenPlan
  across different addresses) — you pick one when choosing that provider.
- `models` are the **recommended** opus/sonnet/haiku mappings, auto-filled on pick (still
  editable afterwards).
- `auth` (`AUTH_TOKEN`/`API_KEY`) and `effort` are optional and carried over on pick.

The "API URL" pick list also **auto-collects** URLs already used in your `providers.json`
(tagged `(已有:name)`).

## First run: skipping login / onboarding

With a third-party API (token auth) Claude Code may still show the login/onboarding screen
on first launch, because it hasn't recorded that onboarding is done. One-time fix: add
`"hasCompletedOnboarding": true` to `~/.claude.json`.

File location:

- Windows: `C:\Users\<you>\.claude.json`
- macOS / Linux: `~/.claude.json`

**Important: this file also holds your MCP config — only ADD the key, don't overwrite the
whole file.** If it doesn't exist, create it as `{ "hasCompletedOnboarding": true }`.

> ccx deliberately does **not** edit this file for you — it's exactly the file no tool
> should mess with. One-time step (some versions may need more; follow official docs).

## Files & data

- Profiles (with keys, stored **in plaintext** locally — don't share): `~/.cc-mini/providers.json`
- Provider catalog: `presets.json` (shipped)
- "Set as default" writes **Windows user environment variables**, not a file; switching to
  "官方" clears all managed variables.
- **No Claude config file is ever modified.**

## FAQ

**Will switching in one terminal affect another running terminal?** No. "Use this session"
is per-process; "Set as default" writes user env vars that only apply to **newly started**
processes.

**I "set as default" but the current terminal still uses the old API.** Expected — open a
**new** terminal.

**I saw `... cannot be parsed as a URL`.** A profile's API URL was set to an invalid value;
fix or delete that profile in Edit.

**effort has no effect on a third party.** It's a Claude-model feature; third parties may
not support it. DeepSeek recommends `max`; leave others empty.

## Uninstall

- Delete `~/.cc-mini/`;
- Remove the block between `# >>> xx >>>` and `# <<< xx <<<` in your `$PROFILE`;
- Clear the user env vars: run `xx` → Set as default → 官方 clears all managed variables.

## Philosophy

ccx was born out of my own friction using cc-switch. This isn't a criticism — cc-switch is
powerful and capable; I just wanted a lighter path.

So ccx follows a single principle: **the simpler, the better.**

- Do one thing — switch the API — and do it well;
- Touch as little as possible — above all, **never write the user's config files**
  (`~/.claude/settings.json`, `~/.claude.json`);
- Before adding any feature, ask first: can we *not* add it?

Issues / PRs welcome. But remember: **a change that makes ccx simpler is more welcome than one
that makes it more powerful.** Any change that writes the user's config files will not be accepted.

## License

[MIT](LICENSE)
