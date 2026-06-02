# npm 发布教程：把 `@cc-x/cc-x` 发到 npm

> 这是给**你（becomeless）**的发布操作手册。npm 发布是**对外、且同一版本号不可重复**的动作，所以一步步来。
> 全程在仓库根目录 `D:\work\AI\ccx` 操作。npm 包名 **`@cc-x/cc-x`**（作用域包），命令 `xx`，当前版本 `0.3.0`（见 `package.json`）。
>
> **发布状态**：`@cc-x/cc-x@0.3.0` 已于 2026-06-02 首发成功。本文继续作为后续版本的发版检查手册；
> 首发专属步骤保留用于追溯。

> ⚠️ **为什么是作用域包名 `@cc-x/cc-x`，而不是 `cc-x`？**
> npm 有**相似名保护**：它会把名字里的连字符/点/下划线去掉再比对，`cc-x` 归一化后 = `ccx`，
> 和已存在的 `ccx` 包（1.0.0）冲突，**无作用域的 `cc-x` 会被 npm 以 E403「too similar to existing package ccx」拒绝**。
> （`npm view cc-x` 报 404 只说明没有字面叫 cc-x 的包，**测不出相似名规则**——这是当初的误判。）
> 作用域包（`@scope/name`）豁免相似名规则，所以最终用 **`@cc-x/cc-x`**。作用域 `@cc-x` 取自已建好的 npm 组织（`becomeless` 组织名已被占用，故用 `cc-x`；GitHub 仓库仍是 `becomeless/cc-x`）。命令名仍是 `xx`，不受影响。

---

## 0. 一次性准备：npm 账号 + 组织

1. 去 https://www.npmjs.com/signup 注册账号（如果还没有）。记住用户名 / 邮箱 / 密码。
2. **创建免费组织 `cc-x`**（作用域 `@cc-x` 的来源）：
   - https://www.npmjs.com/org/create → 组织名填 `cc-x` → 选 **Free / public** 套餐（公开包免费）。
   - 注：`becomeless` 组织名已被占用，故改用 `cc-x`（作用域 `@cc-x`）；GitHub 仓库仍是 `becomeless/cc-x`，不受影响。
   - 你当前登录的 npm 账号是 `shanfanless`，创建组织后该账号会成为 `@cc-x` 的 owner，可以往里发包。**此组织已创建完成。**
3. **准备发布凭据**：npm 发布要求满足以下二选一：
   - 账号开启 **2FA**（npmjs.com → 头像 → Account → Two-Factor Authentication）。交互执行 `npm publish` 时输入一次性验证码（OTP）。
   - 使用开启 **Bypass 2FA** 的 granular access token（适合非交互发布）。
   首次手动发布推荐直接开启账号 2FA。
4. 在终端登录（这一步**只有你能做**，我无法替你登录）：
   ```bash
   npm login
   npm whoami        # 打印出你的用户名 = 已登录
   ```

> 如果你用 `! npm login` 的形式在本会话里跑，登录态就会留在这个会话里，我后续能帮你验证。

---

## 1. 发布前检查清单（逐项确认）

在仓库根目录依次跑：

```bash
# 1) 查询当前线上版本；待发版本必须比它新
npm view @cc-x/cc-x version    # 当前线上应为 0.3.0；若待发版本相同，先按 §4 升版本号

# 2) 确认待发版本号（必须高于线上版本）
node -e "console.log(require('./package.json').version)"

# 3) 干净构建 + 类型检查（确保 dist 是最新的）
npm run typecheck
npm run build

# 4) 预览“真正会被发布的文件”（关键！确认有 dist/、presets.json、README，没有密钥/node_modules/src）
npm pack --dry-run
```

`npm pack --dry-run` 应该列出约 24 个文件：`LICENSE`、`README*.md`、`dist/**/*.js`、`package.json`、`presets.json`。
**如果看到 `.cc-mini`、`providers.json`、`node_modules`、`.env` 之类——立刻停下找我**（说明 `files` 字段或 `.gitignore` 出问题了）。

> 我们用的是 `package.json` 里的 `files: ["dist","presets.json","README.md","README.en.md"]` 白名单，
> 所以 `src/`、`_smoke/`、`docs/`、`node_modules/` 默认都不会被发布。`LICENSE` 由 npm 自动带上。

可选但推荐——**本机端到端验一遍编译产物**（不污染你的全局）：
```bash
npm link                              # 把本地包链接成全局
node dist/index.js --version          # 应打印 0.3.0（包名是 @cc-x/cc-x，但注册的命令只有 xx）
node dist/index.js --help             # 看帮助
npm unlink -g @cc-x/cc-x        # 验完解除链接
```

---

## 2. 正式发布

```bash
npm publish
```

- **作用域公开包首次发布需要 `--access public`**。我们已在 `package.json` 里配了
  `"publishConfig": { "access": "public" }`，所以直接 `npm publish` 即可，**不必**手动加 `--access=public`。
  （若忘了配 publishConfig，则要写成 `npm publish --access=public`，否则会发成 restricted 私有包。）
- 账号 2FA 路径会提示输 OTP；非交互发布则使用开启 Bypass 2FA 的 granular token。
- `package.json` 里配了 `prepublishOnly: "npm run build"`，所以 publish 前会**自动再构建一次**，双保险。

发布成功后验证：
```bash
npm view @cc-x/cc-x             # 能看到 0.3.0、文件列表等
```
也可以去 https://www.npmjs.com/package/@cc-x/cc-x 看看页面（README 会渲染在那里）。

---

## 3. 发布后

1. **真机装一遍**（最好新开一个干净终端）：
   ```bash
   npm install -g @cc-x/cc-x
   # 在没有 PS xx 函数的环境里：xx --version
   # 在你这台被 PS 函数占用的 Windows 机器上：cmd /c xx --version
   ```
2. **打 git tag 并推送**（对齐版本号，便于追溯）：
   ```bash
   git tag -a v0.3.0 -m "npm 版 @cc-x/cc-x 0.3.0 首发"
   git push origin main --tags
   ```
   > ⚠️ 顺序建议：**先 `npm publish` 成功，再 `git push`**（或同时），避免 README 里写着安装命令
   > 但包还没上线、别人装不上的尴尬窗口。
3. README 里的安装说明此时就“真的能用了”。

---

## 4. 以后怎么发新版本（更新流程）

同一个版本号**不能重发**，所以每次发布前必须先升版本号：

```bash
npm version patch      # 0.3.0 → 0.3.1（修 bug）；或 minor=0.4.0（加功能）、major=1.0.0（大改/稳定）
                       # 这条命令会自动改 package.json 的 version 并打一个 git tag
npm publish
git push origin main --tags
```

> 注意：**npm 版的版本号在 `package.json`**；**PowerShell 版的版本号在 `xx.ps1` 的 `$script:Version` 和
> `ccx.psd1` 的 `ModuleVersion`**——两条线各自独立，发哪条就只动哪条。PS 版发 PSGallery 的流程见现有发版习惯。

---

## 5. 几个要知道的“坑 / 规则”

- **作用域 = 组织/用户名**：`@cc-x/cc-x` 的 `@cc-x` 必须是你拥有的 npm 组织或用户名。
  没建组织就发会报 404 / 403。建组织见 §0。
- **版本不可变**：一旦 `@cc-x/cc-x@0.3.0` 发出去，就不能再用 `0.3.0` 这个号发不同内容。发错了只能：72 小时内
  `npm unpublish @cc-x/cc-x@0.3.0` 撤回，或 `npm deprecate @cc-x/cc-x@0.3.0 "说明"` 标记弃用，然后发 `0.3.1`。
- **Windows 旧版迁移**：如果 `$PROFILE` 里还有老 `xx` 函数，它会优先于 npm 命令。安装 npm 版后，从 `$PROFILE`
  删掉 `# >>> xx >>>` 到 `# <<< xx <<<` 的标记块；如果还装过 PSGallery 模块，再执行
  `Uninstall-Module ccx -AllVersions`。新开终端即可；原有 `~/.cc-mini/providers.json` 会继续沿用。
- **macOS / Linux 尚未真机大规模验证**：「本次启用」全平台一致没问题；「设为默认」写 rc 文件的逻辑只跑过单测。
  首发后若有 mac/linux 用户，留意反馈。要更稳妥，可以先找一台 mac 实测「设为默认」再大力推。
- **2FA OTP 过期**：publish 时 OTP 有时效，输慢了会失败，重新跑 `npm publish` 再输新码即可。

---

## 6. 我能帮你做 / 不能帮你做

| 我能做 | 你来做（我做不了） |
|---|---|
| 跑检查清单（typecheck/build/`npm pack --dry-run`）、修问题、改包名/文档 | `npm login`（你的账号密码 / 2FA） |
| 升版本号、改 README、打 tag 的命令 | 创建 npm 组织 `cc-x`、最终 `npm publish` 的点头与 OTP |
| 发布后帮你验证 `npm view` / 装包测试 | 注册 npm 账号、开 2FA 或准备 granular token |

`@cc-x/cc-x@0.3.0` 已完成首发。以后发新版本，从 §4 升版本号开始，再走 §1 检查与 §2 发布。
