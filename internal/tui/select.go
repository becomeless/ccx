package tui

import (
	"os"
	"strconv"
	"strings"

	"golang.org/x/term"

	"github.com/becomeless/cc-x/internal/display"
	"github.com/becomeless/cc-x/internal/i18n"
)

// SelectOptions 配置一次 ↑↓ 选择菜单。” 项为不可选分隔空行（导航跳过）。
type SelectOptions struct {
	Title        string
	Notice       string // 标题下方黄字横幅（如「有新版本」），常驻显示
	Items        []string
	Hint         string
	Status       string        // 顶部绿色 toast
	Start        int           // 初始选中（记忆选中）
	Colors       map[int]Color // 按索引上色
	MovableCount int           // 顶部可排序区项数
	OnMove       func(from, to int) []string
	NoNumber     bool // 关闭行首序号（默认显示，与数字直选一致；编辑表单项多于 9 个时关闭）
}

// SelectMenu 自绘 ↑↓ 选择菜单，返回选中索引；取消（q/Esc/非法）返回 -1；Ctrl+C 恢复终端后以 130 退出。
// 自管 raw 进出（与 ReadText 的 cooked 互斥，同一时刻只跑一套）。非 TTY 回退到打印列表 + 读序号。
func SelectMenu(t *Terminal, opts SelectOptions) int {
	if !t.IsTTY() {
		return fallbackSelect(t, opts)
	}
	items := append([]string(nil), opts.Items...)
	nextSel := func(i, d int) int {
		n := len(items)
		for {
			i = ((i+d)%n + n) % n
			if items[i] != "" {
				return i
			}
		}
	}
	idx := opts.Start
	if idx < 0 || idx >= len(items) || items[idx] == "" {
		c := idx
		if c < 0 {
			c = 0
		}
		if c > len(items)-1 {
			c = len(items) - 1
		}
		idx = nextSel(c, 1)
	}

	if err := t.MakeRaw(); err != nil {
		return fallbackSelect(t, opts)
	}
	t.Write(ClearScreen + HideCursor)

	prevLines := 0
	render := func() {
		lines := []string{""}
		if opts.Title != "" {
			lines = append(lines, "  "+Paint(opts.Title, ColorCyan), "")
		}
		if opts.Notice != "" {
			lines = append(lines, "  "+Paint(opts.Notice, ColorYellow), "")
		}
		if opts.Status != "" {
			lines = append(lines, "  "+Paint(opts.Status, ColorGreen), "")
		}
		for i, it := range items {
			if it == "" {
				lines = append(lines, "")
				continue
			}
			num := ""
			if !opts.NoNumber {
				num = strconv.Itoa(i+1) + ". " // 行首序号，与数字键直选对应
			}
			if i == idx {
				lines = append(lines, Paint("   ▶ "+num+it, ColorGreen))
			} else {
				col := ColorNone
				if c, ok := opts.Colors[i]; ok {
					col = c
				}
				lines = append(lines, Paint("     "+num+it, col))
			}
		}
		lines = append(lines, "")
		if opts.Hint != "" {
			lines = append(lines, "  "+Paint(opts.Hint, ColorDim))
		}

		cols := termWidth(t)
		var b strings.Builder
		if prevLines > 0 {
			b.WriteString(CursorUp(prevLines-1) + CR + ClearDown)
		}
		for i, l := range lines {
			if i > 0 {
				b.WriteByte('\n')
			}
			b.WriteString(display.Truncate(l, cols-1))
		}
		t.Write(b.String())
		prevLines = len(lines)
	}
	cleanup := func() {
		t.Write(ShowCursor + "\n")
		t.Restore()
	}

	render()
	for {
		k := t.ReadKey()
		switch k.Type {
		case KeyCtrlC:
			cleanup()
			os.Exit(130)
		case KeyUp:
			idx = nextSel(idx, -1)
			render()
		case KeyDown:
			idx = nextSel(idx, 1)
			render()
		case KeyShiftUp, KeyPgUp:
			if opts.OnMove != nil && idx > 0 && idx < opts.MovableCount {
				items = opts.OnMove(idx, idx-1)
				idx--
				render()
			}
		case KeyShiftDown, KeyPgDn:
			if opts.OnMove != nil && idx < opts.MovableCount-1 {
				items = opts.OnMove(idx, idx+1)
				idx++
				render()
			}
		case KeyEnter:
			cleanup()
			return idx
		case KeyEsc:
			cleanup()
			return -1
		case KeyDigit:
			if !opts.NoNumber {
				n := int(k.Rune - '0')
				if n >= 1 && n <= len(items) && items[n-1] != "" {
					cleanup()
					return n - 1
				}
			}
		case KeyChar:
			if k.Rune == 'q' {
				cleanup()
				return -1
			}
		}
	}
}

func termWidth(t *Terminal) int {
	w, _, err := term.GetSize(int(t.Out.Fd()))
	if err != nil || w <= 0 {
		return 80
	}
	return w
}

// fallbackSelect 非交互回退：打印列表 + 读一行序号。
func fallbackSelect(t *Terminal, opts SelectOptions) int {
	t.Write("\n")
	if opts.Title != "" {
		t.Write("  " + opts.Title + "\n\n")
	}
	for i, it := range opts.Items {
		if it != "" {
			t.Write("   " + strconv.Itoa(i+1) + ". " + it + "\n")
		}
	}
	ans, ok := t.ReadLine("  " + i18n.T("menu.prompt"))
	if !ok {
		return -1
	}
	s := strings.TrimSpace(ans)
	if s == "q" {
		return -1
	}
	if n, err := strconv.Atoi(s); err == nil && n >= 1 && n <= len(opts.Items) && opts.Items[n-1] != "" {
		return n - 1
	}
	return -1
}
