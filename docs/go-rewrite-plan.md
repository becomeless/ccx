# ccx → Go 二进制重写：交接文档 / 任务清单

> 本文件是 **跨上下文窗口的唯一事实来源（source of truth）**。
> 接手时先读完本文，再读 `CLAUDE.md`，然后看 `xx.ps1`（被复刻的原始实现）。
> 每完成一个里程碑，回来勾选下方 checklist 并补充「已知问题 / 进度笔记」。

---

## 0. 一句话目标

把现有 PowerShell-only 的 `ccx`（命令 `xx`）重写为 **Go 编译的单文件二进制**，
做到 **零运行时依赖**、Windows / macOS / Linux 同一套代码、并内建 **中英文切换（i18n）**。
行为、数据格式、铁律与现版完全对齐，体验只能更好、不能更差。

---

## 1. 已锁定的决策（不要再推翻，除非用户明确改主意）

| 项 | 决策 | 理由 |
|---|---|---|
| 语言 | **Go**（最低 1.26，本机已装 1.26.3） | 静态单文件、零运行时、交叉编译一条命令、原生 JSON、Win 注册表有官方库 |
| 菜单 UI | **charmbracelet/bubbletea**（+ lipgloss 上色） | 终端 TUI 体验天花板；箭头键/数字/高亮/原地重绘都现成 |
| JSON | Go 原生 `encoding/json` | `providers.json` / `presets.json` 格式**保持不变**，老用户零迁移 |
| presets 兜底 | `//go:embed presets.json` 打进二进制 | 等价于现 `$BuiltinPresetsJson` |
| i18n | 消息目录（key→{zh,en}），从第一天就抽离，**逻辑层禁止硬编码中文** | 用户明确要中英文切换 |
| 首版平台 | **Windows x64 + macOS arm64**；Linux 暂不构建 | 用户决定；Linux 是 Unix 分支的同一套代码，将来只是多加构建目标，**零额外代码** |
| 分发 | GoReleaser → GitHub Releases；Homebrew tap（mac）+ Scoop（win）+ curl/iwr 兜底 | 二进制自带 PATH，install 脚本几乎可删 |
| 过渡 | 重写期间 `xx.ps1` **原样保留不动**，Go 版验证 OK 再主推 | 降低风险 |

仓库：`github.com/becomeless/ccx`（origin，HTTPS）。`gh` CLI 可用（v2.90）。

---

## 2. 铁律（违反即作废，来自 CLAUDE.md）

**ccx 永远不写任何 Claude Code 配置文件** —— 不写 `~/.claude/settings.json`、不碰 `~/.claude.json`（MCP 配置）。
它 **只通过环境变量切换 API**。这是工具存在的全部理由（不可能误伤用户的 MCP/插件/hooks）。

- ccx 允许写自己的运行数据 `~/.cc-mini/providers.json`。
- 「设为默认」在 Unix 上写 shell 启动文件（`.zshrc`/`.bashrc`）—— 这与现版 `install.ps1` 改 `$PROFILE`
  同性质，**不碰 `~/.claude`，不违反铁律**。这是 Unix 上唯一的「持久化用户环境变量」手段。
- 任何写 Claude Code config 文件的设计都要拒绝。拿不准时，选「让工具更简单」的那条路。

### 受管的 7 个环境变量（只动这些，其它一律不碰）

```
ANTHROPIC_BASE_URL
ANTHROPIC_AUTH_TOKEN
ANTHROPIC_API_KEY
ANTHROPIC_DEFAULT_OPUS_MODEL
ANTHROPIC_DEFAULT_SONNET_MODEL
ANTHROPIC_DEFAULT_HAIKU_MODEL
CLAUDE_CODE_EFFORT_LEVEL
```

**故意不设** `ANTHROPIC_MODEL`（模型选择交给会话内 `/model`；三个 `*_MODEL` 把 opus/sonnet/haiku 映射到各家真实模型名）。
启用某配置时：该配置用到的键 → 设值；没用到的受管键 → 清除。

---

## 3. 数据格式（必须保持兼容，老用户文件能直接读）

### 3.1 `~/.cc-mini/providers.json`（用户配置，含明文密钥，**绝不提交**）

Windows 路径用 `%USERPROFILE%\.cc-mini\providers.json`；Unix 用 `$HOME/.cc-mini/providers.json`。
Go 里统一用 `os.UserHomeDir()`。可被 `--store-dir` 覆盖（测试用）。

结构（字段名、大小写、嵌套必须一致）：

```json
{
  "current": "官方",
  "providers": [
    { "name": "官方", "note": "", "env": {} },
    {
      "name": "DeepSeek", "note": "备注可空",
      "env": {
        "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "sk-...",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-pro",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash",
        "CLAUDE_CODE_EFFORT_LEVEL": "max"
      }
    }
  ]
}
```

- `env` 是一个 map[string]string，**只存非空的受管键**（见 `Build-ProviderEnv`：按 KnownKeys 顺序，跳过空白值）。
- `name` 是唯一键（`current`、`xx <name>`、删除都靠它）。同供应商可多条，靠 `note` 区分。
- 首次运行若文件不存在：用内置默认（官方 + DeepSeek + 智谱GLM + 小米MiMo，密钥空）生成。见 `$DefaultStoreJson`。
- **新增字段**：i18n 需要存语言偏好。建议加顶层 `"lang": "zh"`（缺省视为 `zh`）。读时容错：旧文件没有该字段不报错。
- 写入：UTF-8 **无 BOM**；缩进 2 空格即可（现版用 `ConvertTo-Json -Depth 100`）。

### 3.2 `presets.json`（供应商目录，随仓库分发 + embed 兜底）

每条：`{ name, auth, urls:[{label,url}], models:{opus,sonnet,haiku}, effort? }`。
- `auth`：`"AUTH_TOKEN"`（Bearer，多数第三方）或 `"API_KEY"`（x-api-key，官方/少数）。
- `urls`：可多个（如 MiMo 有「按量付费API」「TokenPlan」两个），多个时让用户选。
- `models`：推荐的三档映射；`effort` 可选（DeepSeek=max，其余多为空）。
- 选了某供应商 → 自动填 base url（多 url 弹选择）、三档模型、auth 字段、effort。
- 运行时优先读二进制同目录/已知位置的 `presets.json`，缺失/解析失败则用 embed 兜底。

---

## 4. 两种启用模式（核心，逐字对齐现版语义）

### 4.1 本次启用（Session-Launch）—— 进程级、阅后即焚
1. 取目标配置的 env map（按 4 节规则）。
2. 对 7 个受管键：有值的 `os.Setenv`，没值的 `os.Unsetenv`（**只动这 7 个**）。
3. 找到 `claude` 可执行（PATH 查找；找不到给红字提示并返回）。
4. `exec.Command("claude")` 且 `Stdin/Stdout/Stderr = os.Stdin/...`（继承，即 inherit）。
   - 现版 PowerShell 有个坑：`pwsh -File` 子进程直接调原生命令会把 stdin 包成管道，claude 用
     `isTTY(stdin)` 误判为非交互、报「Input must be provided…」，故现版用 `Start-Process -NoNewWindow`。
   - **Go 用 `stdio=inherit` 天然没有这个问题**（子进程直接继承真实控制台句柄）。这是换 Go 的红利之一。
5. 等 claude 退出后返回（菜单场景回到上级菜单；CLI 场景结束）。
6. 多终端并行各跑各的 API、互不干扰。

### 4.2 设为默认（Set-Default）—— 持久化用户环境变量，仅影响**新开**终端
对 7 个受管键：目标配置有值的写值，没值的清除。然后 `store.current = name` 并存盘。

**平台分叉（唯一有平台差异的地方）：**

- **Windows**（沿用现版快路径，体验不变）：
  1. 直写注册表 `HKCU\Environment`：有值 `SetStringValue`，无值 `DeleteValue`。
     用 `golang.org/x/sys/windows/registry`。
  2. **只广播一次** `WM_SETTINGCHANGE`（`SendMessageTimeout`，HWND_BROADCAST=0xffff,
     msg=0x001A, SMTO_ABORTIFHUNG=0x0002, 超时 100ms，lParam="Environment"）。
     用 `golang.org/x/sys/windows` 调 user32。这样新开终端立刻读到，且不卡在挂死窗口上。
  3. 不要用「逐个 setx / 逐个广播」——那会广播 7 次、每次每窗口等 1s，窗口一多就拖几秒。

- **macOS / Linux**：写 shell 启动文件里的 **marker 块**（幂等，可重复重写）：
  ```sh
  # >>> xx >>>
  export ANTHROPIC_BASE_URL="https://..."
  export ANTHROPIC_AUTH_TOKEN="sk-..."
  # ...只导出当前配置用到的受管键
  # <<< xx <<<
  ```
  - 每次「设为默认」**整体重写**这个块（用正则定位 `# >>> xx >>>` … `# <<< xx <<<`，替换或追加）。
    重写即自动「清除」上个默认里多余的 export（块里只剩当前配置的键）。
  - 选哪个文件：按 `$SHELL` basename — `zsh`→`~/.zshrc`，`bash`→ macOS 用 `~/.bash_profile`（登录 shell）、
    Linux 用 `~/.bashrc`；都没有就 `~/.profile`。
  - **fish 语法不同**（`set -gx K V`，无 `export`）：v1 可先不支持，检测到 fish 给提示「请手动设置或用本次启用」；
    或单独写 `~/.config/fish/config.fish` 的 fish 块。列为 follow-up。
  - 语义与 Windows 一致：**只影响新开终端，不动正在运行的会话**（rc 文件只在新交互 shell 启动时加载）。
  - 复用同样的 marker-块逻辑去给 Unix 写 `install`（注册 `xx` 命令）——但若走 Homebrew/二进制自带 PATH，可省。

---

## 5. i18n 设计（中英文切换）

- 新建 `internal/i18n` 包：`type Lang string`（`"zh"` / `"en"`）；
  `var messages = map[string]map[Lang]string{ "menu.title": {...}, ... }`；
  `func T(key string, args ...any) string`（缺 key 回退到 zh 或返回 key 本身，便于发现漏翻）。
  也可用 embed 的 `i18n/zh.json` + `i18n/en.json`，二选一，**简单优先**（小工具用 map 字面量足够）。
- 语言来源优先级：`--lang en` 参数 > `providers.json` 的 `lang` 字段 > 环境 `LC_ALL`/`LANG`（含 `zh` 视为中文）> 默认 `zh`。
- 主菜单加一项「语言 / Language」即时切换并存盘（写回 `lang` 字段）。
- **所有 user-facing 字符串都走 `T()`**；提交前 grep 确认逻辑层无裸中文（除注释）。
- 文案来源：`README.md`（中）/ `README.en.md`（英）已是 zh/en 镜像，可直接取词。
- CJK 宽度对齐（见现版 `Get-DisplayWidth`/`Pad-Display`，全角=2 半角=1）要移植：用 `golang.org/x/text/width`
  或 `mattn/go-runewidth`（推荐后者，专门干这个）。英文是半角，切英文后对齐照样成立。

---

## 6. CLI 参数（对齐现版 + 新增 --lang）

| 现版（PowerShell） | Go 版（建议） | 行为 |
|---|---|---|
| `xx` | `xx` | 打开交互菜单 |
| `xx DeepSeek` | `xx DeepSeek` | 设为默认到该配置 |
| `xx DeepSeek -Session` | `xx DeepSeek --session` / `-s` | 本次启用并启动 claude |
| `xx -List` | `xx --list` / `-l` | 列出所有配置及状态 |
| `xx -StoreDir <d>` | `xx --store-dir <d>` | 覆盖存储目录（测试用） |
| `xx -DefaultScope Process` | `xx --default-scope process` | 设为默认写到哪：`user`(默认持久) / `process`(仅测试，不持久) |
| （无） | `xx --lang zh\|en` | 本次界面语言 |
| （无） | `xx --version` / `xx --help` | 版本 / 帮助 |

找不到 `<name>` 时：红字「找不到配置：X」+ 列出现有名字，退出码 1。

---

## 7. 菜单结构（三级，逐项复刻现版交互）

参考 `xx.ps1` 的 `Main-Menu` / `Action-Menu` / `Edit-Form` 及各 `Pick-*`。bubbletea 用「一个 model + 多个
子状态/子页面」实现，或每级一个 model 压栈。要点：

**一级 · 主菜单**（`Main-Menu`）
- 列出所有配置：`名称(对齐16)  (默认)(对齐8) [状态] — 备注`。
- 状态文案（`Show-State`）：`官方`→`登录态`；否则 `密钥未填` / `密钥·API_KEY` / `密钥已设`；
  若有 effort 追加 ` · effort=xxx`。
- `Shift+↑↓` 或 `PgUp/PgDn` **就地排序**配置并立即存盘（只在配置区前 N 项内移动）。
- 「＋ 新增配置」（亮黄色）、「退出」。
- **记住选中项**：从二级返回后光标停在刚操作的配置上；新建成功后落到新配置；删除后夹取范围。

**二级 · 动作菜单**（`Action-Menu`，标题含配置名/默认标记/备注/状态）
- `本次启用` → 启动 claude，退出后**回到本菜单**（停在该项）。
- `设为默认` → 执行后**留在本页**，顶部绿色 toast 提示一轮（不回一级）。
- `编辑` → 进表单；保存/放弃都回本菜单停在「编辑」。改了名字/供应商且它是当前默认时，同步 `current`。
- `删除` → 二次确认 `(y/N)`；`官方` 给「建议保留」提示；删后回一级。
- `返回 / q / Esc` → 回一级。
- **记住选中的动作项**。

**三级 · 编辑表单**（`Edit-Form`，一屏显示所有字段，选序号改单项）
- 字段：供应商 / 备注 / API 地址 / 认证字段 / API 密钥(显示为 ****) / opus / sonnet / haiku / effort。
- 选「供应商」→ `Pick-Provider`（从目录选或自定义手填名）；选定后自动填 base(多 url 弹 `Pick-ProviderUrl`)、
  三档模型、auth、effort。
- 选「API 地址」→ `Pick-BaseUrl`（目录所有 url + 已有配置用过的 url + 手动输入 + 不修改）。
- 选「认证字段」→ `Pick-Auth`（AUTH_TOKEN / API_KEY）。
- 选「effort」→ `Pick-Effort`（low/medium/high/xhigh/max/auto/留空）。
- 文本输入语义：回车空=不改、输入 `-` 回车=清空、Esc=取消（密钥用掩码显示）。
- 「保存并返回」：名字空则拒绝；按 auth 把密钥写进 `ANTHROPIC_API_KEY` 或 `ANTHROPIC_AUTH_TOKEN`；
  `Resolve-UniqueName`（同名被别条占用则追加 ` 2`/` 3`…，排除自身）；`Build-ProviderEnv`（按 KnownKeys 顺序、丢空值）。
- **记住选中字段**：改完一项回到表单停在原项。

**通用菜单交互**（`Select-Menu`）：↑↓ 导航（跳过空分隔行）、数字键直选、Enter 确认、q/Esc 取消、
原地重绘不闪烁、非交互/无控制台时回退到「打印列表 + 读序号」。bubbletea 自带大部分；非交互回退要自己加。

---

## 8. 建议的 Go 项目结构

```
ccx/
  go.mod                      // module github.com/becomeless/ccx
  main.go                     // 入口：解析 flag → 分派 CLI 或启动 TUI
  presets.json                // 保留（embed 源）
  internal/
    config/                   // providers.json 读写、默认生成、env map 构造
      store.go
    presets/                  // presets.json 加载 + //go:embed 兜底
      presets.go
    env/                      // 两种模式 + 平台持久化
      session.go              // 本次启用（全平台）
      default.go              // 设为默认（公共逻辑）
      persist_windows.go      // //go:build windows —— 注册表 + 广播
      persist_unix.go         // //go:build !windows —— rc 文件 marker 块
    i18n/
      i18n.go                 // T()、Lang、消息目录
    ui/                       // bubbletea：主菜单/动作菜单/表单/各 picker
      ...
  docs/go-rewrite-plan.md     // 本文件
  .goreleaser.yaml            // 构建 win-amd64 + darwin-arm64（先不含 linux）
  xx.ps1                      // 过渡期保留，勿动
```

依赖（`go get`）：
- `github.com/charmbracelet/bubbletea` + `github.com/charmbracelet/lipgloss`
- `github.com/mattn/go-runewidth`（CJK 宽度）
- `golang.org/x/sys/windows`（仅 windows 构建标签下用：注册表 + 广播）

---

## 9. 构建 / 测试命令（重要：Go 不在当前 shell PATH）

本机 Go 装在 `C:\Program Files\Go\bin\go.exe`（winget 装的，新开终端才会进 PATH）。
当前会话用全路径调用：

```powershell
& "C:\Program Files\Go\bin\go.exe" version
& "C:\Program Files\Go\bin\go.exe" mod tidy
& "C:\Program Files\Go\bin\go.exe" build -o xx.exe .
# 交叉编译 macOS arm64：
$env:GOOS="darwin"; $env:GOARCH="arm64"; & "C:\Program Files\Go\bin\go.exe" build -o dist/xx-darwin-arm64 .
```

本地验证（不污染真实环境）：用 `--store-dir <临时目录>` + `--default-scope process`。
mac 上的 rc-文件逻辑在 Windows 上没法真跑，需要在 mac 实机或对 `persist_unix.go` 写单元测试（传入临时 rc 文件路径）。

---

## 10. 里程碑 Checklist（完成就勾，并在末尾记进度）

- [ ] **M1 骨架**：go.mod、目录、`config` 读写 providers.json（对齐格式，含 `lang` 容错）、`presets` 加载 + embed 兜底。
- [ ] **M2 i18n**：`i18n` 包 + `T()`；抽离全部字符串（zh 先全，en 跟上）；runewidth 对齐。
- [ ] **M3 两模式**：`session.go`（exec claude，inherit stdio）；`default.go` + `persist_windows.go`（注册表+广播）+ `persist_unix.go`（rc marker 块）。先做 CLI 路径（`xx <name>` / `-s` / `--list`）跑通。
- [ ] **M4 TUI**：bubbletea 主菜单（含排序/记忆选中/状态文案）、动作菜单（toast/停留语义）、编辑表单 + 各 picker、非交互回退。
- [ ] **M5 CLI 收尾**：`--lang` / `--version` / `--help` / `--store-dir` / `--default-scope`，与现版行为对齐。
- [ ] **M6 分发**：`.goreleaser.yaml`（win-amd64 + darwin-arm64）、GitHub Release、Homebrew tap、Scoop、curl/iwr 安装脚本。
- [ ] **M7 文档**：更新 README.md / README.en.md（新装法、跨平台、语言切换）；CLAUDE.md 增补 Go 版构建说明；保留 xx.ps1 直到 Go 版稳定。

---

## 11. 已知问题 / 风险 / 待定

- **fish shell**：export 语法不同（`set -gx`），v1 暂不支持设为默认（给提示）。follow-up。
- **macOS 实测**：rc 文件与 claude TTY 行为只能在 mac 实机验证；开发在 Windows，要靠交叉编译产物 + 让用户在 mac 上试。
- **Node 不再保证存在**：这是当初选二进制（而非 Node）的核心理由，已规避。
- **Linux**：代码已覆盖（Unix 分支），仅未构建；有需求时在 `.goreleaser.yaml` 加 `linux/amd64` 目标即可。
- **签名/公证**：macOS 未签名二进制会被 Gatekeeper 拦（用户需 `xattr -d com.apple.quarantine` 或右键打开）。
  Homebrew 安装可缓解。是否做 Apple 公证 = 后续可选（要 Apple 开发者账号）。Windows SmartScreen 同理。
- **版本号**：现版在 `xx.ps1` 的 `$script:Version` 与 `ccx.psd1` 的 ModuleVersion 两处。Go 版用 ldflags 注入
  version（GoReleaser 自动）。发版流程见 memory `ccx-release-workflow`。

---

## 12. 进度笔记（每次接手在此追加，倒序）

- 2026-06-01：完成方案定稿 + 本交接文档。已 winget 装好 Go 1.26.3。尚未写任何 Go 代码（M1 未开始）。
