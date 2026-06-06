package display

import "testing"

func TestTruncatePlain(t *testing.T) {
	if got := Truncate("hello", 10); got != "hello" {
		t.Errorf("no-op: got %q", got)
	}
	if got := Truncate("hello world", 5); got != "hello" {
		t.Errorf("cut: got %q", got)
	}
	// CJK 全角算 2 宽。
	if got := Truncate("你好世界", 4); got != "你好" {
		t.Errorf("cjk: got %q", got)
	}
}

func TestTruncateANSIAware(t *testing.T) {
	// 颜色码不计入宽度：可见宽度 5 <= 5，原样保留（含转义）。
	colored := "\x1b[32mhello\x1b[39m"
	if got := Truncate(colored, 5); got != colored {
		t.Errorf("ansi within width must be untouched: got %q", got)
	}

	// 在着色中途截断：保留已写转义 + 可见前缀，并补 reset 防泄漏。
	got := Truncate("\x1b[32mhello world\x1b[39m", 5)
	want := "\x1b[32mhello\x1b[0m"
	if got != want {
		t.Errorf("ansi truncate: got %q want %q", got, want)
	}

	// 纯文本截断不应附加 reset。
	if got := Truncate("hello world", 5); got != "hello" {
		t.Errorf("plain truncate must not append reset: got %q", got)
	}
}

func TestVisibleWidth(t *testing.T) {
	// 用纯 ASCII 分隔符，使字节数==显示宽度，便于断言（剥离两端 SGR 后应为 19）。
	const visible = " - api.deepseek.com"
	if w := visibleWidth("\x1b[2m" + visible + "\x1b[22m"); w != len(visible) {
		t.Errorf("visibleWidth ignoring ANSI: got %d want %d", w, len(visible))
	}
}
