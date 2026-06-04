package config

import (
	"os"
	"testing"
)

// TestGenDefault 是跨实现对比辅助：设了 CCX_GEN_DEFAULT=<dir> 时，把默认 store 写到该目录，
// 供与 npm 版生成的 providers.json 逐字节 diff。平时跳过。
func TestGenDefault(t *testing.T) {
	out := os.Getenv("CCX_GEN_DEFAULT")
	if out == "" {
		t.Skip("set CCX_GEN_DEFAULT=<dir> to generate")
	}
	if err := Save(ResolveStorePaths(out), DefaultStore()); err != nil {
		t.Fatal(err)
	}
}

// TestDefaultRoundTrip：Save 后能 Load 回来，且关键字段不变。
func TestDefaultRoundTrip(t *testing.T) {
	dir := t.TempDir()
	p := ResolveStorePaths(dir)
	if err := Save(p, DefaultStore()); err != nil {
		t.Fatal(err)
	}
	s, err := Load(p)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if s.Current != "官方" || s.Lang != LangZH || len(s.Providers) != 4 {
		t.Fatalf("unexpected store: current=%q lang=%q n=%d", s.Current, s.Lang, len(s.Providers))
	}
	if !IsOfficial(s.Providers[0]) {
		t.Fatalf("provider[0] should be official")
	}
	if st := GetProviderState(s.Providers[1]); st.Key != KeyNone || st.Effort != "max" {
		t.Fatalf("DeepSeek state: key=%q effort=%q", st.Key, st.Effort)
	}
}

// TestNormalizeRejectsBadFormat：结构损坏（providers 非数组）必须报 ErrFormat，绝不静默成空。
func TestNormalizeRejectsBadFormat(t *testing.T) {
	dir := t.TempDir()
	p := ResolveStorePaths(dir)
	if err := os.MkdirAll(p.Dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p.File, []byte(`{"providers":"oops"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := Load(p)
	var se *StoreError
	if err == nil {
		t.Fatal("expected error for bad format")
	}
	if !asStoreError(err, &se) || se.Kind != ErrFormat {
		t.Fatalf("expected ErrFormat, got %v", err)
	}
}

func asStoreError(err error, target **StoreError) bool {
	se, ok := err.(*StoreError)
	if ok {
		*target = se
	}
	return ok
}
