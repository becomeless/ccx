// Package unix 是 macOS / Linux 的「设为默认」持久化：在 shell 启动文件里维护一个幂等 marker 块。
//
//	# >>> xx >>>
//	export ANTHROPIC_BASE_URL='https://...'
//	# <<< xx <<<
//
// 每次整体重写该块 —— 自动清除上个默认里多余的 export。只影响新开终端、不动运行中会话。
// fish 语法不同（set -gx），v1 不支持，由调用方据 Kind=="fish" 给提示。
//
// 本包刻意平台无关（纯文件 + 读环境变量），便于在 Windows 开发机上跑 golden 测试；运行期只在 Unix 被调用。
package unix

import (
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/becomeless/cc-x/internal/config"
	"github.com/becomeless/cc-x/internal/env"
)

const begin = "# >>> xx >>>"
const end = "# <<< xx <<<"

// shQuote 单引号包裹并转义内部单引号（'\” 收尾再起），对齐 npm 版 shQuote。
func shQuote(v string) string {
	return "'" + strings.ReplaceAll(v, "'", `'\''`) + "'"
}

// BuildBlock 生成 marker 块文本（只含非空受管键，按 ManagedKeys 顺序）。
func BuildBlock(vals env.ManagedVals) string {
	lines := []string{begin}
	for _, k := range config.ManagedKeys() {
		if v := vals[k]; v != "" {
			lines = append(lines, "export "+k+"="+shQuote(v))
		}
	}
	lines = append(lines, end)
	return strings.Join(lines, "\n")
}

var blockRE = regexp.MustCompile(`(?s)# >>> xx >>>.*?# <<< xx <<<`)

// WriteMarkerBlock 把 marker 块写进/替换进指定 rc 文件（纯 fs，可测）。
// 替换语义与 npm 版一致：有块替换首个块，无块则追加（拼接含一个空行分隔）。
func WriteMarkerBlock(file string, vals env.ManagedVals) error {
	block := BuildBlock(vals)
	text := ""
	if b, err := os.ReadFile(file); err == nil {
		text = string(b)
	}
	if loc := blockRE.FindStringIndex(text); loc != nil {
		text = text[:loc[0]] + block + text[loc[1]:] // 只替换首个块（对齐 TS String.replace 非全局）
	} else if text == "" {
		text = block + "\n"
	} else {
		sep := ""
		if !strings.HasSuffix(text, "\n") {
			sep = "\n"
		}
		text = text + sep + "\n" + block + "\n"
	}
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		return err
	}
	return os.WriteFile(file, []byte(text), 0o644)
}

// ShellKind 是 shell 类型。
type ShellKind string

const (
	KindZsh  ShellKind = "zsh"
	KindBash ShellKind = "bash"
	KindFish ShellKind = "fish"
	KindSh   ShellKind = "sh"
)

// RcTarget 是选定的 rc 文件与其 shell 类型。
type RcTarget struct {
	File string
	Kind ShellKind
}

// RcTargetFor 据 SHELL basename + 平台选 rc 文件。路径用正斜杠（Unix-destined，便于跨平台测试）。
func RcTargetFor(shellPath, goos, home string) RcTarget {
	base := shellPath
	if i := strings.LastIndex(base, "/"); i >= 0 {
		base = base[i+1:]
	}
	switch base {
	case "zsh":
		return RcTarget{File: path.Join(home, ".zshrc"), Kind: KindZsh}
	case "fish":
		return RcTarget{File: path.Join(home, ".config", "fish", "config.fish"), Kind: KindFish}
	case "bash":
		// macOS 登录 shell 读 .bash_profile；Linux 交互非登录读 .bashrc。
		f := ".bashrc"
		if goos == "darwin" {
			f = ".bash_profile"
		}
		return RcTarget{File: path.Join(home, f), Kind: KindBash}
	default:
		return RcTarget{File: path.Join(home, ".profile"), Kind: KindSh}
	}
}

// Result 是 Unix 持久化结果。
type Result struct {
	Kind        ShellKind
	Unsupported bool // fish：v1 未写入，调用方据此提示
	File        string
}

// Persist 选 rc 文件并重写 marker 块（fish 跳过）。运行期只在 Unix 调用。
func Persist(vals env.ManagedVals, goos string) Result {
	home, _ := os.UserHomeDir()
	t := RcTargetFor(os.Getenv("SHELL"), goos, home)
	if t.Kind == KindFish {
		return Result{Kind: KindFish, Unsupported: true, File: t.File}
	}
	_ = WriteMarkerBlock(t.File, vals)
	return Result{Kind: t.Kind, File: t.File}
}
