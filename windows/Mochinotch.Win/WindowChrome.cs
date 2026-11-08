using System.Runtime.InteropServices;
using Avalonia.Controls;

namespace Mochinotch.Win;

static class WindowChrome
{
    const int ExStyle = -20;
    const int Layered = 0x00080000;
    const int Transparent = 0x00000020;
    const int Tool = 0x00000080;
    const int NoActivate = 0x08000000;

    public static void HideDock()
    {
        if (!OperatingSystem.IsMacOS()) return;
        try
        {
            var app = Msg(GetClass("NSApplication"), Sel("sharedApplication"));
            Msg(app, Sel("setActivationPolicy:"), (nint)1);
        }
        catch
        {
            // 독 아이콘이 남아도 알약은 뜬다.
        }
    }

    public static void Passive(Window window)
    {
        var handle = window.TryGetPlatformHandle()?.Handle ?? 0;
        if (handle == 0) return;
        if (OperatingSystem.IsWindows())
            SetExStyle(handle, Tool | NoActivate);
    }

    public static void ClickThrough(Window window)
    {
        var handle = window.TryGetPlatformHandle()?.Handle ?? 0;
        if (handle == 0) return;
        if (OperatingSystem.IsWindows())
            SetExStyle(handle, Layered | Transparent | Tool | NoActivate);
        else if (OperatingSystem.IsMacOS())
            IgnoreMouse(handle, true);
    }

    static void SetExStyle(nint hwnd, int extra)
    {
        var current = GetWindowLongPtr(hwnd, ExStyle);
        SetWindowLongPtr(hwnd, ExStyle, current | extra);
    }

    static void IgnoreMouse(nint handle, bool ignore)
    {
        try
        {
            var viewClass = GetClass("NSView");
            var window = Msg(handle, Sel("isKindOfClass:"), viewClass) != 0
                ? Msg(handle, Sel("window"))
                : handle;
            if (window == 0) return;
            Msg(window, Sel("setIgnoresMouseEvents:"), ignore ? (nint)1 : 0);
        }
        catch
        {
            // 클릭이 한동안 막히면 연출이 끝날 때 창을 숨긴다.
        }
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    static extern nint GetWindowLongPtr(nint hwnd, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    static extern nint SetWindowLongPtr(nint hwnd, int index, nint value);

    [DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_getClass")]
    static extern nint GetClass(string name);

    [DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "sel_registerName")]
    static extern nint Sel(string name);

    [DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")]
    static extern nint Msg(nint receiver, nint selector);

    [DllImport("/usr/lib/libobjc.A.dylib", EntryPoint = "objc_msgSend")]
    static extern nint Msg(nint receiver, nint selector, nint arg);
}
