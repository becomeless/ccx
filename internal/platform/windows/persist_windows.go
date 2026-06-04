//go:build windows

// Package windows 是 Windows 的「设为默认」持久化：写 HKCU\Environment + 一次 WM_SETTINGCHANGE 广播。
//
// 直接用 golang.org/x/sys/windows 操作注册表，不开 PowerShell 子进程。
// 不用 setx（会截断长值并逐个广播），不碰机器级环境变量。
package windows

import (
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"

	"github.com/becomeless/cc-x/internal/config"
	"github.com/becomeless/cc-x/internal/env"
)

// Persist 把受管键写进/删出 HKCU\Environment（值为空=删除），最后广播一次环境变更。
func Persist(vals env.ManagedVals) error {
	k, err := registry.OpenKey(registry.CURRENT_USER, "Environment", registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	for _, key := range config.ManagedKeys() {
		if v := vals[key]; v == "" {
			_ = k.DeleteValue(key) // 不存在则忽略（best-effort，对齐 npm 版 SilentlyContinue）
		} else if err := k.SetStringValue(key, v); err != nil { // REG_SZ
			return err
		}
	}
	broadcastEnvChange()
	return nil
}

// broadcastEnvChange 发一次 WM_SETTINGCHANGE("Environment")，让新进程尽快看到变更（100ms 短超时、跳过挂死窗口）。
func broadcastEnvChange() {
	const (
		hwndBroadcast   = 0xffff
		wmSettingChange = 0x001A
		smtoAbortIfHung = 0x0002
	)
	user32 := windows.NewLazySystemDLL("user32.dll")
	proc := user32.NewProc("SendMessageTimeoutW")
	env16, err := windows.UTF16PtrFromString("Environment")
	if err != nil {
		return
	}
	var result uintptr
	_, _, _ = proc.Call(
		uintptr(hwndBroadcast),
		uintptr(wmSettingChange),
		0,
		uintptr(unsafe.Pointer(env16)),
		uintptr(smtoAbortIfHung),
		uintptr(100),
		uintptr(unsafe.Pointer(&result)),
	)
}
