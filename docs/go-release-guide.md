# Go 原生版 Windows Release 手册

本手册用于发布 Go 原生 `xx.exe`。当前先发 Windows x64；npm 包 `@cc-x/cc-x`
仍保留为 macOS / Linux 和已有 Node 用户的全平台安装线。

## 0. 版本号

`v0.3.0` 已用于 npm 首发 Release。Go 原生 Windows 首发请使用新的 tag，例如 `v0.4.0`。
二进制内部版本号通过 Go build 注入：

```powershell
.\scripts\build-windows-release.ps1 -Version 0.4.0
.\dist\release\ccx_0.4.0_windows_amd64\xx.exe --version
```

`xx --version` 必须打印 `0.4.0`，不能是 `dev`。

## 1. 发布前验证

```powershell
$go = "$HOME\go-sdk\go\bin\go.exe"
& $go test ./...
& $go vet ./...
& $go build ./cmd/xx
npm run typecheck
npm run build
npm pack --dry-run
```

检查点：

- `go test` / `go vet` / `go build` 全绿。
- `npm pack --dry-run` 不包含 Go 二进制、Release zip、`providers.json` 或 `node_modules`。
- 真终端 smoke 已通过：主菜单、动作菜单、编辑表单、picker、排序、删除、语言切换、
  `--default-scope process`。
- `ccx_0.4.0_windows_amd64.zip` 内含 `xx.exe`、`presets.json`、`LICENSE`、`README.md`、`README.en.md`。

## 2. 构建资产

```powershell
.\scripts\build-windows-release.ps1 -Version 0.4.0
Get-ChildItem .\dist\release
```

产物：

- `dist\release\ccx_0.4.0_windows_amd64.zip`
- `dist\release\install.ps1`
- `dist\release\checksums_windows_amd64.txt`

## 3. 创建 GitHub Release

确认 tag 未被占用后再创建：

```powershell
git tag -a v0.4.0 -m "ccx Go native Windows v0.4.0"
git push origin main --tags
gh release create v0.4.0 `
  .\dist\release\ccx_0.4.0_windows_amd64.zip `
  .\dist\release\install.ps1 `
  .\dist\release\checksums_windows_amd64.txt `
  --repo becomeless/cc-x `
  --title "ccx v0.4.0" `
  --notes "Go native Windows x64 build. npm @cc-x/cc-x remains available for cross-platform installs."
```

如果想先让自己验证下载链路，可加 `--draft` 创建草稿；确认后在 GitHub 页面发布草稿。
README 里的安装命令依赖 `releases/latest/download/install.ps1`，所以正式发布后再验证它。

## 4. 发布后验证

新开 PowerShell：

```powershell
irm https://github.com/becomeless/cc-x/releases/latest/download/install.ps1 | iex
xx --version
xx --list
```

验证内容：

- `xx --version` 打印新版本。
- `Get-Command xx` 指向 `%LOCALAPPDATA%\Programs\ccx\xx.exe` 或用户自定义安装目录。
- `xx --list` 能读取现有 `~/.cc-mini/providers.json`。
- 切换到「官方」只清理 7 个受管环境变量，不写任何 Claude Code 配置文件。

## 5. 回滚

如果 Release 资产有问题：

```powershell
gh release delete v0.4.0 --repo becomeless/cc-x
git push origin :refs/tags/v0.4.0
git tag -d v0.4.0
```

若已有用户下载，优先发 `v0.4.1` 修正并在 Release notes 里说明，不要复用同一个 tag。
