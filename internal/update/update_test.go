package update

import (
	"testing"
	"time"
)

func TestIsNewer(t *testing.T) {
	cases := []struct {
		latest, current string
		want            bool
	}{
		{"0.4.4", "0.4.3", true},
		{"0.5.0", "0.4.9", true},
		{"1.0.0", "0.9.9", true},
		{"0.4.3", "0.4.3", false},
		{"0.4.2", "0.4.3", false},
		{"v0.4.4", "v0.4.3", true},   // 前导 v
		{"0.4.4-rc1", "0.4.3", true}, // 后缀
		{"0.4.4", "dev", false},      // current 无法解析 -> 不误报
		{"garbage", "0.4.3", false},  // latest 无法解析 -> 不误报
	}
	for _, c := range cases {
		if got := isNewer(c.latest, c.current); got != c.want {
			t.Errorf("isNewer(%q,%q)=%v want %v", c.latest, c.current, got, c.want)
		}
	}
}

func TestTagRe(t *testing.T) {
	loc := "https://github.com/becomeless/cc-x/releases/tag/v0.4.3"
	m := tagRe.FindStringSubmatch(loc)
	if m == nil || m[1] != "0.4.3" {
		t.Fatalf("从 %q 抠版本号失败：%v", loc, m)
	}
}

func TestCacheRoundtrip(t *testing.T) {
	dir := t.TempDir()
	want := cache{CheckedAt: time.Now().Unix(), Latest: "0.4.4"}
	writeCache(dir, want)
	got, err := readCache(dir)
	if err != nil {
		t.Fatalf("readCache: %v", err)
	}
	if got.Latest != want.Latest || got.CheckedAt != want.CheckedAt {
		t.Fatalf("往返不一致：want %+v got %+v", want, got)
	}
}

func TestBannerFromCache(t *testing.T) {
	dir := t.TempDir()
	writeCache(dir, cache{CheckedAt: time.Now().Unix(), Latest: "0.4.4"})
	if latest, ok := Banner(dir, "0.4.3"); !ok || latest != "0.4.4" {
		t.Fatalf("有新版应返回横幅：latest=%q ok=%v", latest, ok)
	}
	if _, ok := Banner(dir, "0.4.4"); ok {
		t.Fatal("已是最新不应返回横幅")
	}
	if _, ok := Banner(t.TempDir(), "0.4.3"); ok {
		t.Fatal("无缓存不应返回横幅")
	}
}
