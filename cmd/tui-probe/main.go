// Command tui-probe 是 M5 TUI 原型的验收驱动（§2.5.5 闸门）。请在真实终端运行：
//
//	go run ./cmd/tui-probe        （或 go build 后运行）
//
// 依次验证：① raw-key 菜单（↑↓/数字/Enter/q/Esc/Ctrl+C、原地重绘、CJK 对齐）；
// ② raw 退出后 cooked 中文输入（输入法组词）；③ 启动子进程继承 stdio、退出后菜单状态正常；④ 终端恢复。
// 非 TTY 环境应走 fallback（打印列表 + 读序号），不卡死。
package main

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"

	"github.com/becomeless/cc-x/internal/tui"
)

func main() {
	t := tui.New()
	// 收尾：恢复终端 + 打印 panic + 暂停，避免独立启动时窗口跑完一闪而过（这不是 bug，是进程退出窗口就关）。
	defer func() {
		if r := recover(); r != nil {
			t.Restore()
			fmt.Fprintf(os.Stderr, "\n[probe] panic: %v\n", r)
		}
		t.Restore()
		t.ReadLine("\n[probe] 按 Enter 退出…")
	}()

	if !t.IsTTY() {
		fmt.Fprintln(os.Stderr, "[probe] 非 TTY：将走 fallback（打印列表 + 读序号），不应卡死。")
	}

	items := []string{"官方", "DeepSeek", "", "智谱GLM（中文项测对齐）", "退出"}
	idx := tui.SelectMenu(t, tui.SelectOptions{
		Title: "TUI 原型 · ↑↓/数字 选择，Enter 确认，q/Esc 取消，Ctrl+C 退出",
		Items: items,
		Hint:  "↑↓ 选择 · Enter 确认 · q 取消",
		Start: 1,
	})
	fmt.Printf("\n[probe] 菜单选中: idx=%d -> %s\n", idx, pick(items, idx))

	note, ok := tui.ReadText(t, "  请输入中文备注（验证输入法组词）: ")
	fmt.Printf("[probe] cooked 读到: ok=%v note=%q\n", ok, note)

	fmt.Println("[probe] 启动子进程（继承 stdio）...")
	runChild()
	fmt.Println("[probe] 子进程已返回，终端应恢复正常。原型结束。")
}

func pick(items []string, i int) string {
	if i < 0 || i >= len(items) {
		return "(取消)"
	}
	return items[i]
}

func runChild() {
	var c *exec.Cmd
	if runtime.GOOS == "windows" {
		comspec := os.Getenv("ComSpec")
		if comspec == "" {
			comspec = "cmd.exe"
		}
		c = exec.Command(comspec, "/d", "/s", "/c", "echo [child] running")
	} else {
		c = exec.Command("sh", "-c", "echo '[child] running'; uname -a")
	}
	c.Stdin = os.Stdin
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	_ = c.Run()
}
