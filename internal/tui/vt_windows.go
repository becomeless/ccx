//go:build windows

package tui

import (
	"os"

	"golang.org/x/sys/windows"
)

// enableVTOutput 在 Windows 控制台开启 ENABLE_VIRTUAL_TERMINAL_PROCESSING，
// 让 ANSI 颜色/光标转义在 stdout 生效（Windows Terminal 默认已开，旧 conhost 需显式开；best-effort）。
func enableVTOutput(f *os.File) {
	h := windows.Handle(f.Fd())
	var mode uint32
	if windows.GetConsoleMode(h, &mode) != nil {
		return
	}
	_ = windows.SetConsoleMode(h, mode|windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING)
}
