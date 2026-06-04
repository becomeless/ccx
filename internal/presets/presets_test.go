package presets

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// TestBuiltinMatchesRootFile 对拍：内置 BuiltinPresets 必须与仓库根 presets.json（npm 发布用）内容一致。
// 任一方改了忘了同步，这里就红——根 presets.json 是唯一可手编辑源。
func TestBuiltinMatchesRootFile(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("..", "..", "presets.json"))
	if err != nil {
		t.Fatalf("读根 presets.json: %v", err)
	}
	var raw any
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("解析根 presets.json: %v", err)
	}
	got := normalizePresets(raw)
	if !reflect.DeepEqual(got, BuiltinPresets) {
		t.Fatalf("BuiltinPresets 与根 presets.json 不一致：\n根文件=%+v\n内置=%+v", got, BuiltinPresets)
	}
}

// TestLoadFallsBackToBuiltin：空 storeDir 且无旁路文件时回退到内置目录。
func TestLoadFallsBackToBuiltin(t *testing.T) {
	got := Load(t.TempDir()) // 临时目录里没有 presets.json
	if !reflect.DeepEqual(got, BuiltinPresets) {
		t.Fatalf("期望回退到 BuiltinPresets，got %d 条", len(got))
	}
}

// TestUserOverride：用户 <storeDir>/presets.json 优先于内置。
func TestUserOverride(t *testing.T) {
	dir := t.TempDir()
	body := `[{"name":"Custom","auth":"API_KEY","urls":[{"label":"x","url":"https://e.x"}],"models":{"opus":"m"}}]`
	if err := os.WriteFile(filepath.Join(dir, "presets.json"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	got := Load(dir)
	if len(got) != 1 || got[0].Name != "Custom" || got[0].Auth != AuthAPIKey {
		t.Fatalf("用户覆盖未生效：%+v", got)
	}
}

// TestNormalizeDropsNameless：无名条目被丢弃；全空则返回 nil（跌落兜底）。
func TestNormalizeDropsNameless(t *testing.T) {
	var raw any
	_ = json.Unmarshal([]byte(`[{"auth":"AUTH_TOKEN"},{"name":"  "}]`), &raw)
	if got := normalizePresets(raw); got != nil {
		t.Fatalf("期望全部丢弃后返回 nil，got %+v", got)
	}
}
