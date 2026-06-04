// Package tui 是自绘 ANSI 终端 UI：raw-key 菜单 + cooked 文本输入 + 终端原语抽象。
// 移植自 npm 版 src/ui/*，是 Go 版最大风险区（raw mode / 中文输入法 / TTY 恢复 / Ctrl+C / spawn 继承）。
package tui

import (
	"os"
	"strconv"

	"golang.org/x/term"
)

// colorEnabled：仅当 stdout 是终端且未设 NO_COLOR 时上色（管道/重定向自动退化为无色）。
var colorEnabled = term.IsTerminal(int(os.Stdout.Fd())) && os.Getenv("NO_COLOR") == ""

// Color 是支持的颜色名。
type Color string

const (
	ColorNone   Color = "none"
	ColorGreen  Color = "green"
	ColorYellow Color = "yellow"
	ColorCyan   Color = "cyan"
	ColorRed    Color = "red"
	ColorDim    Color = "dim"
	ColorBold   Color = "bold"
)

var colorCodes = map[Color][2]int{
	ColorGreen:  {32, 39},
	ColorYellow: {33, 39},
	ColorCyan:   {36, 39},
	ColorRed:    {31, 39},
	ColorDim:    {2, 22},
	ColorBold:   {1, 22},
}

// Paint 给字符串上色（无色或未知色原样返回）。
func Paint(s string, c Color) string {
	code, ok := colorCodes[c]
	if !ok || !colorEnabled {
		return s
	}
	return "\x1b[" + strconv.Itoa(code[0]) + "m" + s + "\x1b[" + strconv.Itoa(code[1]) + "m"
}

// —— 光标 / 屏幕控制 ——
const (
	HideCursor  = "\x1b[?25l"
	ShowCursor  = "\x1b[?25h"
	ClearDown   = "\x1b[0J"              // 从光标处清到屏幕末尾
	CR          = "\r"                   // 回到行首
	ClearScreen = "\x1b[2J\x1b[3J\x1b[H" // 清屏 + 清回滚 + 归位（制造整页感）
)

// CursorUp 光标上移 n 行（n<=0 返回空串）。
func CursorUp(n int) string {
	if n > 0 {
		return "\x1b[" + strconv.Itoa(n) + "A"
	}
	return ""
}
