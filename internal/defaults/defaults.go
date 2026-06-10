// Package defaults 编排「设为默认」：算受管 vals -> 平台持久化 -> 仅持久化成功（或 dry-run）才更新 current 并存盘。
package defaults

import (
	"runtime"

	"github.com/becomeless/cc-x/internal/config"
	"github.com/becomeless/cc-x/internal/env"
	"github.com/becomeless/cc-x/internal/platform/unix"
	pwin "github.com/becomeless/cc-x/internal/platform/windows"
)

// Scope 是「设为默认」的作用域。
type Scope string

const (
	ScopeUser    Scope = "user"
	ScopeProcess Scope = "process" // dry-run：不写系统，仅更新存储（测试用）
)

// Result 是设为默认的结果。WinOK 仅在 Windows 真实持久化路径非 nil；Unix 仅在 Unix 路径非 nil。
type Result struct {
	Scope    Scope
	DryRun   bool
	WinOK    *bool
	WinErr   string
	Unix     *unix.Result
	StoreErr string
}

// PersistEnv 按配置持久化默认环境变量；不修改 store。
func PersistEnv(p config.Provider, scope Scope) Result {
	vals := env.ComputeManagedVals(p)
	dryRun := scope == ScopeProcess
	res := Result{Scope: scope, DryRun: dryRun}
	if !dryRun {
		if runtime.GOOS == "windows" {
			err := pwin.Persist(vals)
			ok := err == nil
			res.WinOK = &ok
			if err != nil {
				res.WinErr = err.Error()
			}
		} else {
			r := unix.Persist(vals, runtime.GOOS)
			res.Unix = &r
		}
	}
	return res
}

func envPersisted(r Result) bool {
	if r.DryRun {
		return true
	}
	if r.WinOK != nil {
		return *r.WinOK
	}
	if r.Unix != nil {
		return !r.Unix.Unsupported // fish 未写入 -> 不算成功
	}
	return false
}

// SetDefault 设为默认。dryRun（process 作用域）时不碰系统，只更新 store。
// 仅当持久化成功（或 dry-run）才改 store.current 并存盘，避免「报失败却已改默认」的不一致。
func SetDefault(paths config.StorePaths, store *config.Store, p config.Provider, scope Scope) Result {
	res := PersistEnv(p, scope)
	if envPersisted(res) {
		store.Current = p.Name
		if err := config.Save(paths, store); err != nil {
			res.StoreErr = err.Error()
		}
	}
	return res
}
