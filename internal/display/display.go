// Package display 是终端显示宽度工具：CJK/全角算 2、半角算 1。
// 用 go-runewidth（等价于 npm 版的 string-width / eastasianwidth），切英文后对齐照样成立。
package display

import (
	"strings"

	"github.com/mattn/go-runewidth"
)

// Width 返回字符串的终端显示宽度。
func Width(s string) int {
	return runewidth.StringWidth(s)
}

// Pad 按显示宽度在右侧补空格到 width（不足才补，超出原样返回）。
func Pad(s string, width int) string {
	w := runewidth.StringWidth(s)
	if w < width {
		return s + strings.Repeat(" ", width-w)
	}
	return s
}

// Truncate 按显示宽度截断到 max（防止超宽行在终端换行打乱原地重绘的行数计算）。
func Truncate(s string, max int) string {
	if runewidth.StringWidth(s) <= max {
		return s
	}
	w := 0
	var b strings.Builder
	for _, ch := range s {
		cw := runewidth.RuneWidth(ch)
		if w+cw > max {
			break
		}
		b.WriteRune(ch)
		w += cw
	}
	return b.String()
}
