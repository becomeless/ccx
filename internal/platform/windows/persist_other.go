//go:build !windows

// 非 Windows 平台的 stub：让 internal/defaults 能在所有平台编译。运行期不会被调用
// （defaults 按 runtime.GOOS 分派，只有 Windows 才走这里）。
package windows

import (
	"errors"

	"github.com/becomeless/cc-x/internal/env"
)

// Persist 在非 Windows 平台不可用。
func Persist(vals env.ManagedVals) error {
	_ = vals
	return errors.New("windows persistence is not available on this platform")
}
