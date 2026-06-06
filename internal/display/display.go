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
// ANSI-aware：转义序列（\x1b[…m）不计入宽度且整段保留；若在着色中途截断，补 \x1b[0m 防颜色泄漏到后续行。
func Truncate(s string, max int) string {
	if visibleWidth(s) <= max {
		return s
	}
	runes := []rune(s)
	var b strings.Builder
	w := 0
	colored := false
	for i := 0; i < len(runes); i++ {
		if runes[i] == 0x1b {
			end := csiEnd(runes, i)
			for k := i; k <= end; k++ {
				b.WriteRune(runes[k])
			}
			colored = true
			i = end
			continue
		}
		cw := runewidth.RuneWidth(runes[i])
		if w+cw > max {
			break
		}
		b.WriteRune(runes[i])
		w += cw
	}
	if colored {
		b.WriteString("\x1b[0m")
	}
	return b.String()
}

// visibleWidth 返回去除 ANSI 转义序列后的显示宽度。
func visibleWidth(s string) int {
	runes := []rune(s)
	w := 0
	for i := 0; i < len(runes); i++ {
		if runes[i] == 0x1b {
			i = csiEnd(runes, i)
			continue
		}
		w += runewidth.RuneWidth(runes[i])
	}
	return w
}

// csiEnd 返回从 ESC（runes[i]==0x1b）起 CSI 序列的最后一个下标（含终止字节 0x40–0x7E）。
// 形如 ESC [ 参数… 终止字节。非 CSI（ESC 后非 '['）或无终止字节时退化为能消费到的最远下标。
func csiEnd(runes []rune, i int) int {
	if i+1 >= len(runes) || runes[i+1] != '[' {
		return i // 孤立 ESC，当单字符
	}
	j := i + 2 // 跳过 ESC 和引导符 '['
	for j < len(runes) {
		if runes[j] >= '@' && runes[j] <= '~' { // 终止字节
			return j
		}
		j++
	}
	return len(runes) - 1
}
