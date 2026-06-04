# ccx -> Go 原生版 vNext：交接文档 / 任务清单

> 状态：2026-06-03 重新决策。跳过 Bun / Node SEA 二进制通道，直接做 Go 原生版。
> 2026-06-04 更新：CLI、数据层、presets、两种启用模式、完整三级 TUI 已完成；Windows 原生分发进入 Release 资产阶段。
> 本文合并了已删除旧 Go 方案中仍然有效的细节，并以当前 npm/TypeScript 实现为行为基准。
>
> 接手顺序：先读 `AGENTS.md`，再读 `docs/npm-rewrite-plan.md`，然后对照当前 `src/` 与 Go 实现。
> `@cc-x/cc-x` npm 版继续作为全平台 npm 安装线；Go 原生版先进入 Windows Release 分发。

---

## 0. 一句话目标

把 `ccx`（命令 `xx`）重写为 **Go 编译的轻量单文件二进制**，做到无 Node.js 运行时依赖、
Windows / macOS / Linux 同一套核心逻辑，并保留现有 npm 版的行为、数据格式、i18n 和两种启用模式。

这不是把 TypeScript 代码打包成另一个 JS 运行时，而是原生重写。Bun / Node SEA 不再作为过渡通道。

---

## 1. 为什么直接 Go

Claude Code 现在已是原生二进制，"用户一定有 Node.js" 不再成立。ccx 继续只有 npm 安装，会让没装 Node
的用户为了一个小工具先装完整 Node.js。

Bun spike 已证明当前 TS 代码可以打包，但也证明它不适合作为轻量终态：

| 形态 | 磁盘体积 | 单个父进程私有工作集 | 判断 |
|---|---:|---:|---|
| npm / Node | 包本体很小，但需要 Node | 约 13 MB | 已有 Node 用户继续可用 |
| Bun 编译二进制 | 约 94 MB | 约 32 MB | 解决无 Node 安装，但不轻量 |
| Go 原生二进制 | 目标为低个位数 MB | 目标为低个位数 MB | 更符合 `xx` 的小工具定位 |

Windows 上 "本次启用" 需要 `xx` 作为父进程阻塞等待 `claude` 退出。用户多开 Claude Code 会话时，
父进程开销会叠加，所以 Go 的低常驻内存比 JS runtime 打包更贴合这个工具。

---

## 2. 已锁定决策

| 项 | 决策 | 理由 |
|---|---|---|
| 语言 | Go | 原生单文件、无运行时依赖、适合低内存父进程、跨平台构建成熟 |
| 行为基准 | 当前 `src/` npm/TypeScript 实现 | 旧 PowerShell / 旧 Go 文档只是历史素材，不再是实现源 |
| TUI | 自绘 ANSI raw-key 菜单 + cooked 文本输入 | 贴近当前 TS 版已验证方案；中文输入法字段必须 cooked，不能全程 raw |
| JSON | Go 原生 `encoding/json` | `providers.json` / `presets.json` 格式保持兼容 |
| presets 兜底 | `go:embed` 内置默认 catalog，同时支持用户覆盖 | 对齐当前 TS 版：用户覆盖优先，内置兜底防缺文件 |
| i18n | 消息目录 `key -> {zh,en}` | 逻辑层不硬编码用户文案；README.md / README.en.md 保持同步 |
| 首版平台 | Windows x64 优先，随后 macOS / Linux | Windows 是主力平台；Unix 分支逻辑同时设计，不做一次性死分叉 |
| 分发 | GitHub Releases 原生资产 + `install.ps1` | Windows x64 先发；README 安装命令必须对应真实 Release 资产 |
| npm 线 | 继续维护 npm 包 | 保留全平台安装覆盖；Go 原生版先发 Windows |

仓库：`github.com/becomeless/cc-x`。包名：`@cc-x/cc-x`。命令名始终是 `xx`。

---

## 2.5 Go Rewrite Design

本节是动手重写前的架构约束。实现可以分阶段落地，但模块边界、兼容契约和高风险原型要先想清楚。

### 2.5.1 模块边界：TS -> Go 映射

| 当前 TS 模块 | Go 模块 | 职责 | 迁移原则 |
|---|---|---|---|
| `src/config/types.ts` | `internal/config` | 7 个受管 env、Store / Provider 类型、官方档判定 | Go 类型必须兼容现有 JSON；字段名和容错语义不能漂 |
| `src/config/store.ts` | `internal/config` | `providers.json` 读写、默认 store、结构校验、唯一名、状态判断 | 先实现并测试；坏文件只报错，不静默覆盖 |
| `src/config/presets.ts` | `internal/presets` | 用户 presets、外部 presets、内置兜底 | 与 store 分离，避免供应商目录污染用户配置数据层 |
| `src/env/session.ts` | `internal/env` + `internal/launch` | 计算 session env、定位并启动 `claude` | env 计算可单测；spawn / TTY 必须真终端 smoke |
| `src/env/default.ts` | `internal/env` + `internal/defaults` | 计算默认 env、更新 current、编排平台持久化 | 只有平台持久化成功后才改 `store.current` |
| `src/env/persist-windows.ts` | `internal/platform/windows` | HKCU 环境变量、`WM_SETTINGCHANGE` 广播 | 不用 `setx`，不碰机器级环境变量 |
| `src/env/persist-unix.ts` | `internal/platform/unix` | shell rc marker block | 文件选择与 marker 替换可用临时文件单测 |
| `src/i18n/*` | `internal/i18n` | zh/en 消息、语言解析、官方显示名 | 数据主键不翻译，只有显示名翻译 |
| `src/ui/*` | `internal/tui` + `internal/display` | 菜单、表单、picker、文本输入、CJK 对齐 | 最危险，必须先做小原型验证 raw/cooked 切换 |
| `src/index.ts` | `cmd/xx/main.go` | 参数解析、dispatch、错误处理、版本 | CLI 行为先跑通，再接 TUI |

边界要求：

- `internal/config` 不能 import TUI、launch 或平台持久化；它只负责数据合同。
- `internal/env` 只做纯计算：给定 Provider，产出 `key -> value or clear`。
- `internal/platform/*` 只做副作用；公共逻辑不要散在 build tag 文件里。
- `internal/tui` 调用应用服务，不直接写注册表、rc 文件或任意 Claude Code 配置。

### 2.5.2 TUI 技术选型

当前决策：**先自己移植现有 TS 的 ANSI raw-key 菜单 + cooked 文本输入，不先上 Bubble Tea。**

理由：

- 当前 TS 版已经验证过 raw 菜单和 cooked 中文输入的分离；Go 版首要目标是行为等价。
- ccx 的 TUI 是三级菜单和表单，不需要复杂组件树；引入 Bubble Tea 会改变事件模型和页面组织方式。
- 最大风险不是渲染，而是 raw mode、中文输入法、Windows TTY、Ctrl+C 和 child process 继承。

建议依赖：

- `golang.org/x/term`：raw mode / restore。
- `github.com/mattn/go-runewidth`：CJK 宽度计算。
- `golang.org/x/sys/windows`：Windows registry、user32 广播。

TUI 原型必须先验证这些场景，再进入完整菜单实现：

- Windows Terminal / PowerShell 中方向键、数字键、Enter、Esc、Ctrl+C 都能正确恢复终端。
- raw 菜单退出后，cooked 文本输入能正常使用中文输入法组词。
- cooked 输入结束后能重新进入 raw 菜单。
- 菜单中启动一个继承 TTY 的子进程后，子进程交互正常，退出后父菜单状态正常。
- 非 TTY 环境下不会卡住，能回退到打印列表 + 读序号或明确报错。

Bubble Tea 只作为 fallback：如果自绘原型无法稳定处理 Windows raw mode / resize / key parsing，再评估引入。

### 2.5.3 终端与子进程抽象

建议把终端输入输出抽成小接口，避免菜单逻辑直接散落 `os.Stdin` / `os.Stdout`：

```text
Terminal
  IsTTY() bool
  MakeRaw() (restore func(), err error)
  ReadKey() (Key, error)
  ReadLine(prompt string, initial string, mask bool) (TextResult, error)
  WriteFrame(lines []string)
```

`ReadKey` 只需要支持 ccx 用到的键：↑ / ↓ / PgUp / PgDn / 数字 / Enter / Esc / q / Ctrl+C。
不要为暂时不存在的复杂编辑能力扩展协议。

启动 `claude` 前必须确保终端已经 restore 到 cooked / normal 状态。Windows 下需要单独验证：

- `exec.LookPath("claude")` 返回 `.exe` 时直接 `exec.Command(path)` 是否正常。
- 返回 `.cmd` / `.bat` 时是否必须经 `%ComSpec% /d /s /c`。
- Ctrl+C 时父进程是否提前退出、是否影响子进程 TTY、退出后终端是否恢复。

### 2.5.4 兼容契约与对拍测试

兼容目标分两层：

- **语义兼容是底线**：老 `providers.json` 能读，保存后不丢字段、不丢 key、不误判官方档。
- **稳定输出是目标**：默认 store 和常见保存路径尽量与 TS 版字节稳定，避免 TS / Go 双线交替保存时文件反复变动。

建议的对拍测试：

- TS 版生成默认 store，Go 版生成默认 store，对比 JSON 内容。
- 同一组 profile 字段，TS `buildProviderEnv` 与 Go env builder 结果一致。
- 同一个 store，TS `--list` 与 Go `--list` 的核心行一致。
- `--default-scope process` 使用临时 store，验证不写系统环境。
- Unix marker block 用临时 rc 文件 golden 测试：无块、已有块、清空 key、特殊字符转义。
- Windows registry 持久化用接口替身单测公共逻辑；真实注册表只做手动 smoke。

双线期间的规则：

- 改 `providers.json` 数据结构时，必须同时更新 TS 和 Go 的 normalize / marshal 测试。
- 改 7 个受管 env 或状态文案时，必须同步 `src/`、Go 模块、README 中英文和本文。
- npm 包继续发布期间，`npm pack --dry-run` 不能把 Go release 资产打进去。

### 2.5.5 分阶段策略

顺序建议：

1. **合同捕获**：先补 TS 行为 golden / smoke，尤其是 store、env、list 输出。
2. **Go 数据层**：读写、校验、默认 store、presets。
3. **CLI 核心**：`--version`、`--help`、`--list`、`xx <name>`、`--default-scope process`。
4. **TUI 原型**：单独验证 raw keypress、cooked 中文输入、TTY restore、Ctrl+C、spawn inherit。
5. **完整 TUI**：主菜单、动作菜单、编辑表单、picker。
6. **平台持久化**：Windows registry + broadcast，Unix rc marker。
7. **分发**：Release 资产、安装脚本、README 安装命令。

可以先做数据层，但不能跳过 TUI 原型直接全量重写 TUI。TUI 原型是 Go 版最大风险的验收闸门。

### 2.5.6 最大风险预案

| 风险 | 触发点 | 预案 |
|---|---|---|
| 中文输入法在 raw mode 下失效 | 编辑备注、自定义供应商、手动 URL | 中文/自由文本字段一律 restore cooked 后读行 |
| Windows Ctrl+C 后终端不恢复 | raw 菜单或子进程运行时中断 | 所有 raw 入口用 defer restore；原型中专门测 Ctrl+C |
| `.cmd` shim 无法直接 exec | `claude` 仍可能通过 cmd shim 暴露 | Windows launch 分支兼容 `.exe` 与 `.cmd`，并写 smoke 记录 |
| 默认持久化失败却改了 current | registry / rc 写入失败 | 只有持久化成功或 dry-run 时才保存 `store.current` |
| 双线保存导致 JSON 抖动 | TS / Go 交替编辑同一 store | Go marshal 固定字段序；能字节稳定的路径尽量字节稳定 |
| Go release 资产误进 npm 包 | `files` 或 dist 污染 | 发布前固定跑 `npm pack --dry-run` |

---

## 3. 铁律

**ccx 永远不写任何 Claude Code 配置文件**：不写 `~/.claude/settings.json`，不碰 `~/.claude.json`。
API 切换只通过环境变量完成。ccx 只能写自己的运行数据 `~/.cc-mini/`，以及为了"设为默认"持久化用户环境变量。

只管理这 7 个环境变量，其它一律不碰：

```text
ANTHROPIC_BASE_URL
ANTHROPIC_AUTH_TOKEN
ANTHROPIC_API_KEY
ANTHROPIC_DEFAULT_OPUS_MODEL
ANTHROPIC_DEFAULT_SONNET_MODEL
ANTHROPIC_DEFAULT_HAIKU_MODEL
CLAUDE_CODE_EFFORT_LEVEL
```

故意不设置 `ANTHROPIC_MODEL`。模型选择交给 Claude Code 会话内 `/model`，三档 `*_MODEL` 变量只负责把
`opus` / `sonnet` / `haiku` 映射到各供应商真实模型名。

启用某个配置时：该配置有值的受管键设值，没有值的受管键清除。清除旧 profile 多余环境变量和设置新值同样重要。

---

## 4. 数据格式合同

### 4.1 用户配置：`~/.cc-mini/providers.json`

路径：

- Windows：`%USERPROFILE%\.cc-mini\providers.json`
- macOS / Linux：`$HOME/.cc-mini/providers.json`
- 测试可用 `--store-dir <dir>` 覆盖，不能碰真实用户 store

结构必须兼容当前 npm 版：

```json
{
  "current": "官方",
  "lang": "zh",
  "providers": [
    { "name": "官方", "note": "", "builtin": "official", "env": {} },
    {
      "name": "DeepSeek",
      "note": "备注可空",
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

规则：

- `name` 是唯一键，`current`、`xx <name>`、删除和重命名都靠它。
- `note` 用于区分同供应商多配置，例如两个 DeepSeek key。
- `builtin: "official"` 是官方登录态的稳定内部标识，显示名可以 i18n，但数据主键不翻译。
- 读旧文件时允许缺 `lang` / `note` / `builtin`；缺 `lang` 默认 `zh`。
- 老文件没有 `builtin` 时，仅当 `name == "官方"` 且 `env` 为空才兜底认作官方档。
- `env` 只保存非空受管键，按上面的 7 个 key 顺序构造。
- JSON 语法或结构损坏时要提示并退出，绝不静默重建覆盖，避免清掉用户明文 key。
- 写入 UTF-8 无 BOM，2 空格缩进。

首次运行若文件不存在，生成默认 store：官方 + DeepSeek + 智谱GLM + 小米MiMo，密钥为空。

### 4.2 供应商目录：`presets.json`

每条供应商：

```json
{
  "name": "DeepSeek",
  "auth": "AUTH_TOKEN",
  "urls": [{ "label": "API", "url": "https://..." }],
  "models": { "opus": "...", "sonnet": "...", "haiku": "..." },
  "effort": "max"
}
```

规则：

- profile 是 **配置**，preset catalog entry 是 **供应商**。
- `auth` 只允许 `AUTH_TOKEN` 或 `API_KEY`。
- `urls` 可多个，多个时弹选择器。
- 选供应商时自动填 base URL、三档模型、auth 字段和 effort。
- 加载优先级：用户 `~/.cc-mini/presets.json` > 二进制旁边或发布资产中的 `presets.json` > `go:embed` 内置常量。
- 缺外部 `presets.json` 不应导致程序崩溃。

---

## 5. 两种启用模式

### 5.1 本次启用

语义：只影响本次子进程。多个终端可以并行使用不同 API，互不干扰。

流程：

1. 找到目标配置。
2. 对 7 个受管键计算最终 env：有值设值，没值清除。
3. 定位 `claude`。
4. 启动 `claude`，继承真实 stdin / stdout / stderr，阻塞等待退出。
5. `claude` 退出后，CLI 路径结束；菜单路径回到对应菜单。

Windows 注意事项：

- 当前 Claude Code 可能是原生 `.exe`，也可能通过 shim 暴露命令；Go 实现不能假设只有 Unix exec 规则。
- 需要分别 smoke `claude.exe`、`claude.cmd` 或 PATH 解析结果。
- 如果 Go `exec.Command` 不能可靠启动 `.cmd`，Windows 分支要显式经 `cmd.exe /c` 启动，并保持 stdio inherit。

### 5.2 设为默认

语义：持久化用户环境变量，只影响新开的终端，不影响已经运行的会话。

公共流程：

1. 对 7 个受管键计算 `key -> value or clear`。
2. 平台持久化成功后，才把 `store.current = name` 写入 `providers.json`。
3. `--default-scope process` 是测试 dry-run：不写注册表、不写 rc 文件，但允许更新临时 store。

Windows：

- 写 `HKCU\Environment`。
- 有值则设置字符串，空值则删除对应 key。
- 只广播一次 `WM_SETTINGCHANGE`，`lParam = "Environment"`，避免 7 次 setx 式慢广播。
- 不要修改系统环境变量，不要动机器级 PATH。

macOS / Linux：

- 只写 shell 启动文件中的 ccx marker 块：

```sh
# >>> xx >>>
export ANTHROPIC_BASE_URL="https://..."
export ANTHROPIC_AUTH_TOKEN="sk-..."
# <<< xx <<<
```

- 每次整体替换 `# >>> xx >>>` 到 `# <<< xx <<<` 之间的内容。
- 块内只保留当前 profile 用到的受管键，从而自然清除上一个默认 profile 的多余 key。
- 选文件建议：`zsh -> ~/.zshrc`，`bash` 在 macOS 优先 `~/.bash_profile`、Linux 优先 `~/.bashrc`，兜底 `~/.profile`。
- fish shell 语法不同，v1 可提示暂不支持默认持久化，或单独实现 `set -gx` marker 块。

---

## 6. CLI 参数

| 命令 | 行为 |
|---|---|
| `xx` | 打开交互菜单 |
| `xx <name>` | 将配置设为默认 |
| `xx <name> --session` / `-s` | 本次启用并启动 `claude` |
| `xx --list` / `-l` | 列出配置和状态 |
| `xx --store-dir <dir>` | 覆盖 store 目录，测试用 |
| `xx --default-scope user` | 设为默认时写用户环境变量，默认值 |
| `xx --default-scope process` | dry-run，不写系统环境，测试用 |
| `xx --lang zh\|en` | 本次界面语言，并在需要时写回 store |
| `xx --version` / `-v` | 打印版本 |
| `xx --help` | 打印帮助 |

找不到 `<name>` 时，输出错误和现有配置名，退出码 1。

语言优先级：`--lang` > `providers.json.lang` > `LC_ALL` / `LANG` > `zh`。

---

## 7. TUI 行为合同

Go 版要复刻当前 npm 版的三级交互，不要先发一个功能缩水的菜单。

### 7.1 主菜单

- 列出所有配置：名称、默认标记、状态、备注。
- 官方档显示为登录态；第三方显示密钥未填 / API_KEY / 密钥已设，并追加 effort。
- 支持新增配置和退出。
- 支持排序时立即存盘。
- 从二级菜单返回时，光标停在刚操作的配置上。
- 新建成功后光标落到新配置；删除后夹取到合理位置。

### 7.2 动作菜单

- 本次启用：启动 `claude`，退出后回到本菜单。
- 设为默认：执行后留在本页，给成功或失败提示。
- 编辑：进入表单，保存或放弃后回本菜单。
- 删除：二次确认。官方档给建议保留提示。
- 返回：回主菜单。
- 记住上次选中的动作项。

### 7.3 编辑表单

字段：

- 供应商
- 备注
- API 地址
- 认证字段
- API 密钥
- opus
- sonnet
- haiku
- effort

交互规则：

- 供应商选择来自 `presets.json`，也允许自定义。
- 供应商有多个 URL 时继续弹 URL 选择器。
- API 地址选择器聚合 catalog URL、已有配置用过的 URL、手动输入和不修改。
- 认证字段只允许 `AUTH_TOKEN` / `API_KEY`。
- effort 允许 `low` / `medium` / `high` / `xhigh` / `max` / `auto` / 留空。
- 文本输入：空回车不修改，`-` 清空，Esc 取消。
- 中文字段必须退出 raw mode，用 cooked 输入，保证输入法组词可用。
- 保存时根据 auth 把密钥写入 `ANTHROPIC_AUTH_TOKEN` 或 `ANTHROPIC_API_KEY`。
- 同名冲突时追加 ` 2` / ` 3`，排除正在编辑的自身。
- 如果官方档被编辑成真实第三方 env，要清掉 `builtin`，避免继续被当登录态。
- 如果当前默认配置被重命名，要同步 `store.current`。

### 7.4 通用菜单

- ↑ / ↓ 导航。
- 数字键直选。
- Enter 确认。
- q / Esc 取消或返回。
- CJK 宽度对齐，用 `github.com/mattn/go-runewidth` 或等价实现。
- 非交互或无 TTY 时回退到打印列表 + 读序号，不要崩。

---

## 8. 建议 Go 项目结构

```text
cmd/xx/main.go              CLI entrypoint
internal/config/            providers.json, defaults, validation, migrations
internal/presets/           presets loading, user override, go:embed fallback
internal/env/               managed env calculations
internal/launch/            claude discovery and child launch
internal/defaults/          default persistence orchestration
internal/platform/windows/  registry writes and WM_SETTINGCHANGE
internal/platform/unix/     shell rc marker blocks
internal/tui/               raw menu, cooked text input, forms, pickers
internal/i18n/              zh/en messages and display names
internal/display/           ANSI, CJK width, padding
```

候选依赖：

- `golang.org/x/sys/windows`：Windows 注册表与广播。
- `github.com/mattn/go-runewidth`：CJK 宽度。
- TUI 优先自己移植当前 TS 的 raw/cooked split；只有当终端处理成本明显失控时，再评估 Bubble Tea。

---

## 9. 构建与测试命令

当前 shell 未必有 `go` 在 PATH。开始实现前先确认工具链：

```powershell
go version
where.exe go
```

如果未安装或不在 PATH，先安装 Go 并新开终端，再写 `go.mod`。不要在文档里硬编码未验证的本机 Go 路径。
如果仓库里已经有 `go.mod`，以 `go.mod` 声明的版本为准。

基础命令：

```powershell
go test ./...
go build ./cmd/xx

npm run typecheck
npm run build
node .\dist\index.js --version
node .\dist\index.js --list
```

只要 npm 线还存在，改 Go 相关共享文档或数据格式时也要跑 npm 验证，避免打破当前公开版。

---

## 10. 里程碑

- [ ] **M0 合同捕获**：为当前 TS 行为补 smoke / golden 测试，覆盖 store、CLI、env 计算、i18n、presets。
  （进行中：已用「TS 生成 vs Go 生成默认 store 逐字节 diff」做了 store 的 golden 验证，见 §13。）
- [x] **M1 Go 骨架**：`go.mod` ✓、目录 ✓；`cmd/xx/main.go` 跑通 `--version` / `--help` / `--list`，
  含手写参数解析、语言优先级（--lang > store.lang > 环境 > zh）、StoreError 友好提示。`--list` 与 TS **中英文均逐字节一致**
  （覆盖登录态/无密钥/AUTH_TOKEN/API_KEY/effort/备注/非首项默认）。`xx <name>` / `-s` / 无参菜单暂占位（待 M4/M5）。
  i18n 全量消息表已移植（`internal/i18n`），CJK 宽度用 go-runewidth（`internal/display`）。
- [x] **M2 数据层（providers.json）**：读写 / 默认 store / 结构校验（坏结构报 ErrFormat 不静默重建）/ UTF-8 无 BOM /
  `builtin` / `lang` 兼容 —— 全部完成，并与 npm 版输出**逐字节一致**（1172B 同 SHA256）。presets（M3）另算。
- [x] **M3 presets**（`internal/presets`）：加载优先级（用户 <storeDir>/presets.json > 二进制旁路 presets.json >
  内置兜底）、URL/auth/model/effort 宽松 normalize。**偏离**：内置兜底用字面量 `BuiltinPresets` 而非 go:embed
  （Go embed 无法引用包外 ../../presets.json；用对拍测试 `TestBuiltinMatchesRootFile` 断言它等于根文件、防漂），
  根 presets.json 仍是唯一可编辑源。
- [x] **M4 两种启用模式**：`internal/env`（受管 vals 纯计算 + 进程级套用）、`internal/launch`（claude 定位 +
  .cmd/.exe 分启动 + 继承 TTY 阻塞）、`internal/platform/unix`（marker 块，平台无关可测）、
  `internal/platform/windows`（HKCU 注册表 + WM_SETTINGCHANGE，build-tag 分实现/stub）、`internal/defaults`（编排，仅持久化成功/dry-run 才改 current）。
  已验证：env/unix 单测；设为默认 dry-run 输出与 TS 逐字一致 + current 更新不写系统；`.cmd` 启动 smoke（假 claude.cmd 收到注入的 BASE_URL）。
  **待人工 smoke**（真终端/真环境，本会话无法自动跑）：① `--default-scope user` 真实写 HKCU 注册表；② 真 claude.exe 交互启动 + Ctrl+C 终端恢复（§12）。
- [x] **M5 TUI**：闸门已过 + **主体已移植**（menu.go/edit.go/pickers.go/text.go:ReadValue），`cmd/xx` 无参→真实 OpenMenu。
  非 TTY 主菜单 fallback 与 TS **逐字节一致**；真终端完整菜单 smoke 已通过（方向键导航、动作菜单、编辑表单、5 个 picker、
  密钥粘贴/掩码/明文切换、中文备注、Shift+↑↓ 排序、删除确认、语言即时切换、新增配置）。
- （原 M5 行细分见下，闸门部分保留）：**原型/闸门已建成**（`internal/tui`：ansi、key 解析、Terminal 抽象、SelectMenu、ReadText；
  `cmd/tui-probe` 驱动）。关键决策：单次 Read 读整段再 ParseKey（避开 lone-ESC 歧义 + Windows 无法对 stdin 设读超时）；
  raw 用 x/term（Windows 自动开 VT 输入），stdout VT 输出单独开（build-tag）。已验证：键解析单测；非 TTY fallback 端到端
  （选择 + cooked 读行 + spawn 继承 + 不卡死）。**待真终端 smoke**（闸门）：`dist\tui-probe.exe` 跑方向键/数字/Enter/q/Esc/
  Ctrl+C 恢复 + 中文输入法组词 + raw↔cooked 切换。闸门过后再写**完整三级菜单/动作菜单/编辑表单/pickers**（M5 主体）。
- [x] **M6 文档 + 版本注入**：`README.md` / `README.en.md` 改为 Windows 原生版优先、npm 全平台版保留；
  `scripts/build-windows-release.ps1` 用 `-ldflags "-X main.version=<version>"` 注入版本并生成 Release zip；
  `docs/go-release-guide.md` 记录发布流程。
- [~] **M7 分发**：`install.ps1` 与 Windows x64 Release zip 构建流程已就绪；真正创建 GitHub Release 时使用新 tag（建议 `v0.4.0`，
  避免复用已用于 npm 首发的 `v0.3.0`），并上传 `ccx_<version>_windows_amd64.zip`、`install.ps1`、`checksums_windows_amd64.txt`。
- [ ] **M8 macOS / Linux**：Unix 默认持久化实测，Release 资产，必要时加 `install.sh`、Homebrew / Scoop。

---

## 11. 发布前验证门槛

任何 Go 原生安装命令进入 README 前，必须同时满足：

- Go 二进制行为等价覆盖 profile CRUD、`--list`、`xx <name>`、`-s`、`--default-scope process`。
- Windows 真终端中 `xx` 菜单方向键、数字键、Enter、Esc、中文输入均正常。
- "本次启用" 能继承真实 TTY 并拉起 `claude`。
- "设为默认" 只写 7 个受管 env，并保留其它用户环境变量。
- `~/.claude/settings.json` 和 `~/.claude.json` 仍未被读取或写入。
- 用现有 `~/.cc-mini/providers.json` 备份验证兼容，不丢 key。
- `npm pack --dry-run` 不包含 Go 二进制或 release 资产，除非明确决定改变 npm 分发策略。
- GitHub Release 里已经存在 README 所写命令要下载的资产（正式发布前必须验证）。

---

## 12. 已知风险

- **Windows `.cmd` / `.exe` 启动差异**：Go 版必须实测 Claude Code 当前安装形态。
- **中文输入法**：菜单 raw mode 与文本 cooked mode 需要清晰切换。
- **fish shell**：默认持久化语法不同，v1 可提示不支持。
- **macOS quarantine / 签名**：终端下载 CLI 通常风险较小，但仍需实机验证。
- **npm 与 Go 双线期**：数据格式改动必须同时保护 npm 版，不能让 Go 计划反向破坏现有发布包。

---

## 13. 进度笔记

- 2026-06-03：决定跳过 Bun / Node SEA，直接做 Go vNext。本文合并旧 Go 方案的细节，并按当前 npm/TS 实现重写为唯一保留的 Go 计划。
- 2026-06-03：Go 工具链装在 `~/go-sdk`（用户级 zip，go1.26.4，非 PATH，构建用全路径 `~/go-sdk/go/bin/go.exe`）。
  `go mod init github.com/becomeless/cc-x` 完成。**M2 数据层落地**：`internal/config/{types.go,store.go,store_test.go}`，
  Provider 自定义 `MarshalJSON` 保证字段序 + env 键按 KnownKeys 序，`gofmt`/`vet`/`test` 全过；
  与 TS 默认 store **逐字节一致**（golden 验证法：`node dist/index.js --store-dir <t> --list` 对比 `CCX_GEN_DEFAULT=<t> go test -run TestGenDefault`）。
  下一步：`internal/i18n`（zh/en 消息）+ `cmd/xx/main.go` 跑通 `--version`/`--help`/`--list`（补齐 M1），随后 env 计算 + launch（M4 起）。
- 2026-06-03：按建议把 `config.KnownKeys` 收成私有 `knownKeys` + `ManagedKeys()` 返回副本（铁律常量防漂），重构后输出仍与 TS 逐字节一致。
  **M3 presets 落地**：`internal/presets/{presets.go,presets_test.go}`，三层加载优先级 + 宽松 normalize；内置兜底用字面量（非 go:embed，理由见 §10 M3），
  对拍测试断言与根 `presets.json` 一致。`vet`/`test` 全过。下一步仍是 i18n + `cmd/xx/main.go`（M1/CLI 核心）。
- 2026-06-03：**M1 CLI 核心完成**。新增 `internal/i18n`（全量消息表 + T/ResolveLang/ProviderDisplayName/StateLabel/NoteSuffix）、
  `internal/display`（go-runewidth 做 CJK 宽度）、`cmd/xx/main.go`（手写 arg 解析 + dispatch + runList）。依赖加 `github.com/mattn/go-runewidth`。
  `--list` 与 TS 中英文逐字节对拍一致。`xx <name>`/`-s`/无参菜单先占位（comingSoon），等 M4 env/launch、M5 TUI。
  下一步：M4 —— `internal/env`（session env 纯计算）+ `internal/launch`（定位并启动 claude，Windows .cmd/.exe 分支）+ Windows/Unix 默认持久化。
- 2026-06-03：**M4 两种启用模式完成**。新增 `internal/{env,launch,defaults}` 与 `internal/platform/{unix,windows}`，依赖加 `golang.org/x/sys`（Windows 注册表+广播，原生实现不开 PowerShell）。
  `cmd/xx/main.go` 接上 `runDefault`/`launchSession`/`warnIfNoKey`，name 路径占位换成真实分派。验证：env/unix 单测全过；
  设为默认 dry-run 与 TS 逐字对拍一致；`.cmd` 启动 smoke 通过（套环境 + cmd.exe /c + stdout 继承）。
  待人工 smoke：真实 HKCU 写入（`--default-scope user`，会改本机默认 API 环境，故未自动跑）、真 claude 交互启动 + Ctrl+C。
  下一步：M5 —— **先做 TUI 原型**（§2.5.5 闸门：raw keypress / 中文 cooked 输入 / TTY restore / Ctrl+C / spawn inherit），再做完整菜单。
- 2026-06-03：**M5 TUI 原型建成**。新增 `internal/tui`（ansi.go / key.go+key_test / terminal.go / vt_{windows,other}.go / select.go / text.go）+ `cmd/tui-probe`，依赖加 `golang.org/x/term`。
  键解析 = 纯函数 ParseKey（单次 Read 整段→解析，避 lone-ESC 歧义），单测覆盖方向/Pg/Shift/Enter/Esc/Ctrl+C/Backspace/数字/CJK。
  非 TTY fallback 端到端验过（选择+cooked 读行+spawn 继承，不卡）。已生成 `dist\tui-probe.exe` 供真终端 smoke。
  **闸门待人工**：真 Windows 终端跑 tui-probe，确认 raw 方向键/数字/Enter/q/Esc、Ctrl+C 恢复、中文输入法、原地重绘、子进程继承。
  闸门过 → 写 M5 主体（主菜单/动作菜单/编辑表单/pickers/排序/记忆选中，移植 src/ui/{menus,edit,pickers}.ts）。
- 2026-06-03：**TUI 原型闸门在真 Windows 终端通过**（方向键/数字/Enter/q/Esc、Ctrl+C 恢复、中文输入法组词、raw↔cooked 切换、
  子进程继承 stdio、原地重绘、CJK 对齐 全部正常；「窗口关」确认是进程退出关窗、非 bug，已给 tui-probe 加结尾暂停）。
  开始 M5 主体：移植 `src/ui/{menus,edit,pickers}.ts` → `internal/tui`，并把 `cmd/xx` 无参路径从 comingSoon 换成真实 openMenu。
- 2026-06-03：**M5 主体完成**。新增 `internal/tui/{menu,edit,pickers}.go` + `text.go:ReadValue`（raw 行编辑器，整段字节处理以支持粘贴密钥）。
  `cmd/xx` 无参→`tui.OpenMenu`。非 TTY 主菜单 fallback 与 TS **逐字节一致**（注入同版本号对拍）。`go build/vet/test ./...` 全绿。
  整个 app（CLI + 完整三级 TUI）已移植到 Go。已生成 `dist\xx-go.exe` 供真终端交互 smoke。
  **待人工**：真终端跑完整菜单（编辑表单/pickers/排序/删除/语言切换）。smoke 用 `--store-dir <临时> --default-scope process` 隔离。
  下一步：M6 文档（README 安装/版本号注入到 Go build）→ M7 分发（Windows Release + install.ps1）。
- 2026-06-04：用户真终端完整菜单 smoke 已通过，M5 关闭。M6/M7 继续：新增 `scripts/build-windows-release.ps1`
  （Windows amd64、版本号 `-ldflags` 注入、Release zip/checksum 产物）、`install.ps1`（下载 GitHub Release zip，安装到
  `%LOCALAPPDATA%\Programs\ccx` 并维护用户 PATH）、`docs/go-release-guide.md`；README 中英同步为 Windows 原生版优先、
  npm 全平台版保留。`v0.3.0` 已是 npm 首发 Release，Go 原生公开发布建议从 `v0.4.0` 起。
