//go:build !windows

package tui

import "os"

// enableVTOutput 在非 Windows 平台无需处理（终端原生支持 ANSI）。
func enableVTOutput(*os.File) {}
