package i18n

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// tsKeyRe 匹配 src/i18n/messages.ts 里的一条目录键：行首（缩进后）的 'key': { …
// 值串里的引号（如 zh: '切换到 English'）不会命中，因为要求紧跟 ': {'。
var tsKeyRe = regexp.MustCompile(`^\s*'([^']+)'\s*:\s*\{`)

// TestI18nKeysMatchTS 对拍：Go 版 messages 的 key 集合必须与 npm 版 src/i18n/messages.ts 完全一致。
// 只改一边加/删 key（如这次菜单文案漂移）就会红——逼着两版同步。
func TestI18nKeysMatchTS(t *testing.T) {
	tsPath := filepath.Join("..", "..", "src", "i18n", "messages.ts")
	data, err := os.ReadFile(tsPath)
	if err != nil {
		t.Fatalf("读 %s（npm 版不在此 clone？）: %v", tsPath, err)
	}

	tsKeys := map[string]bool{}
	for _, line := range strings.Split(string(data), "\n") {
		if m := tsKeyRe.FindStringSubmatch(line); m != nil {
			tsKeys[m[1]] = true
		}
	}
	if len(tsKeys) == 0 {
		t.Fatal("从 messages.ts 没解析出任何 key——正则或文件格式变了，先修测试")
	}

	goKeys := map[string]bool{}
	for k := range messages {
		goKeys[k] = true
	}

	onlyGo := diff(goKeys, tsKeys)
	onlyTS := diff(tsKeys, goKeys)
	if len(onlyGo) > 0 || len(onlyTS) > 0 {
		t.Fatalf("i18n key 两版不一致（功能改动漏同步了某一版）：\n  仅 Go 有：%v\n  仅 TS 有：%v", onlyGo, onlyTS)
	}
}

// diff 返回在 a 中但不在 b 中的 key（已排序，便于稳定输出）。
func diff(a, b map[string]bool) []string {
	var out []string
	for k := range a {
		if !b[k] {
			out = append(out, k)
		}
	}
	sort.Strings(out)
	return out
}
