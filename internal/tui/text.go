package tui

import (
	"os"
	"strings"

	"github.com/becomeless/cc-x/internal/i18n"
)

// ReadText 在 cooked 模式读一行（兼容中文输入法）。调用前终端应处于 cooked；ReadLine 内部会确保已 Restore。
// 返回 (line, ok)；EOF/中止且无内容时 ok=false。对应 npm 版 src/ui/text.ts 的 readText。
// 语义（空=不改、"-"=清空等）由调用方处理。
func ReadText(t *Terminal, prompt string) (string, bool) {
	return t.ReadLine(prompt)
}

// ReadValue raw 逐键读 ASCII 字段：回车空=不改、"-"=清空、其它=替换、Esc=取消、Ctrl+C 退出（130）。
// secret=true 时回显 *。对应 npm 版 readValue。
//
// 直接处理整段字节而非单键，以支持粘贴（多字符一次到达；ReadKey 单键抽象会丢掉除首字符外的内容）。
func ReadValue(t *Terminal, label, current string, secret bool) (changed bool, value string) {
	cur := current
	switch {
	case cur == "":
		cur = i18n.T("empty.paren")
	case secret:
		cur = "********"
	}
	t.Write("\n  " + label + "  [" + i18n.T("edit.current", cur) + "]  " + i18n.T("edit.inputHint") + "\n  > ")

	if !t.IsTTY() {
		return cookedFallback(t, current)
	}
	if err := t.MakeRaw(); err != nil {
		return cookedFallback(t, current)
	}

	var buf []rune
	for {
		n, err := t.In.Read(t.buf[:])
		if n == 0 && err != nil {
			t.Restore()
			t.Write("\n")
			return false, current
		}
		chunk := t.buf[:n]
		switch ParseKey(chunk).Type {
		case KeyCtrlC:
			t.Restore()
			t.Write("\n")
			os.Exit(130)
		case KeyEnter:
			t.Restore()
			t.Write("\n")
			s := string(buf)
			if s == "" {
				return false, current
			}
			if s == "-" {
				return true, ""
			}
			return true, s
		case KeyEsc:
			t.Restore()
			t.Write("\n")
			return false, current
		case KeyBackspace:
			if len(buf) > 0 {
				buf = buf[:len(buf)-1]
				t.Write("\b \b")
			}
		case KeyChar, KeyDigit:
			s := filterPrintable(chunk)
			if s != "" {
				buf = append(buf, []rune(s)...)
				if secret {
					t.Write(strings.Repeat("*", len([]rune(s))))
				} else {
					t.Write(s)
				}
			}
		}
	}
}

// cookedFallback：非 TTY / raw 失败时，cooked 读一行（语义同 ReadValue 的回车/-/替换）。
func cookedFallback(t *Terminal, current string) (bool, string) {
	line, ok := t.ReadLine("")
	if !ok || line == "" {
		return false, current
	}
	if line == "-" {
		return true, ""
	}
	return true, line
}

// filterPrintable 保留可打印字符（>=0x20 且非 DEL），过滤控制字符与转义序列残留。
func filterPrintable(b []byte) string {
	var sb strings.Builder
	for _, r := range string(b) {
		if r >= 0x20 && r != 0x7f {
			sb.WriteRune(r)
		}
	}
	return sb.String()
}
