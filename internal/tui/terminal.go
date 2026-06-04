package tui

import (
	"io"
	"os"

	"golang.org/x/term"
)

// Terminal 封装 stdin/stdout 的 raw 模式、按键读取与 cooked 行读取，避免菜单逻辑直接散落 os.Stdin/Stdout。
type Terminal struct {
	In  *os.File
	Out *os.File
	raw *term.State
	buf [64]byte
}

// New 返回绑定到标准输入输出的 Terminal。
func New() *Terminal { return &Terminal{In: os.Stdin, Out: os.Stdout} }

// IsTTY 报告 stdin 与 stdout 是否都是终端。
func (t *Terminal) IsTTY() bool {
	return term.IsTerminal(int(t.In.Fd())) && term.IsTerminal(int(t.Out.Fd()))
}

// MakeRaw 进入 raw 模式（x/term 在 Windows 上会开 ENABLE_VIRTUAL_TERMINAL_INPUT，方向键即 VT 序列），
// 并在 Windows 上开启 stdout 的 VT 输出（其它平台 no-op）。
func (t *Terminal) MakeRaw() error {
	st, err := term.MakeRaw(int(t.In.Fd()))
	if err != nil {
		return err
	}
	t.raw = st
	enableVTOutput(t.Out)
	return nil
}

// Restore 恢复终端到进入 raw 前的状态。可重复调用（幂等）。
func (t *Terminal) Restore() {
	if t.raw != nil {
		_ = term.Restore(int(t.In.Fd()), t.raw)
		t.raw = nil
	}
}

// ReadKey 读取一次按键。依赖「raw 模式下转义序列单次 read 原子投递」，整段字节交 ParseKey。
func (t *Terminal) ReadKey() Key {
	n, err := t.In.Read(t.buf[:])
	if n == 0 && err != nil {
		return Key{Type: KeyEsc} // EOF/错误当取消处理，避免死循环
	}
	return ParseKey(t.buf[:n])
}

// Write 写一段字符串到 stdout。
func (t *Terminal) Write(s string) { _, _ = io.WriteString(t.Out, s) }

// ReadLine 在 cooked 模式下逐字节读一行（IME 组词由控制台在字节到达前完成）。
// 逐字节避免 bufio 预读越过换行吃掉后续 raw 输入。返回 (line, ok)；EOF 且无内容时 ok=false。
// 调用前应确保终端处于 cooked（非 raw）；若仍在 raw 会自动 Restore。
func (t *Terminal) ReadLine(prompt string) (string, bool) {
	if t.raw != nil {
		t.Restore()
	}
	t.Write(prompt)
	var bs []byte
	one := make([]byte, 1)
	for {
		n, err := t.In.Read(one)
		if n > 0 {
			c := one[0]
			if c == '\n' {
				return string(bs), true
			}
			if c != '\r' {
				bs = append(bs, c)
			}
		}
		if err != nil {
			if len(bs) == 0 {
				return "", false
			}
			return string(bs), true
		}
	}
}
