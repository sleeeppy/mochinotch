using System.Runtime.InteropServices;

namespace Mochinotch.Win;

public static class ForegroundAgent
{
    public static AgentTool? Current()
    {
        if (!OperatingSystem.IsWindows()) return null;
        var hwnd = GetForegroundWindow();
        if (hwnd == 0) return null;
        _ = GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0) return null;
        try
        {
            var name = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName;
            return name.ToLowerInvariant() switch
            {
                "cursor" => AgentTool.Cursor,
                "claude" => AgentTool.Claude,
                "codex" => AgentTool.Codex,
                "kiro" => AgentTool.Kiro,
                _ => null,
            };
        }
        catch
        {
            return null;
        }
    }

    public static void Focus(AgentTool tool)
    {
        if (!OperatingSystem.IsWindows()) return;
        var names = tool switch
        {
            AgentTool.Cursor => new[] { "Cursor" },
            AgentTool.Claude => new[] { "Claude" },
            AgentTool.Codex => new[] { "Codex" },
            AgentTool.Kiro => new[] { "Kiro" },
            _ => Array.Empty<string>(),
        };
        foreach (var name in names)
        {
            var proc = System.Diagnostics.Process.GetProcessesByName(name)
                .FirstOrDefault(item => item.MainWindowHandle != 0);
            if (proc == null) continue;
            var hwnd = proc.MainWindowHandle;
            ShowWindow(hwnd, 9);
            var foreground = GetForegroundWindow();
            var foregroundThread = GetWindowThreadProcessId(foreground, out _);
            var targetThread = GetWindowThreadProcessId(hwnd, out _);
            var current = GetCurrentThreadId();
            AttachThreadInput(current, foregroundThread, true);
            AttachThreadInput(current, targetThread, true);
            SetForegroundWindow(hwnd);
            AttachThreadInput(current, targetThread, false);
            AttachThreadInput(current, foregroundThread, false);
            return;
        }
    }

    [DllImport("user32.dll")]
    static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);

    [DllImport("user32.dll")]
    static extern bool SetForegroundWindow(nint hwnd);

    [DllImport("user32.dll")]
    static extern bool ShowWindow(nint hwnd, int command);

    [DllImport("user32.dll")]
    static extern bool AttachThreadInput(uint from, uint to, bool attach);

    [DllImport("kernel32.dll")]
    static extern uint GetCurrentThreadId();
}

public static class LoginStart
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string RunName = "Mochinotch";

    public static bool Supported => OperatingSystem.IsWindows();

    public static bool Enabled
    {
        get
        {
            if (!Supported) return false;
            try
            {
                using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
                return key?.GetValue(RunName) is string;
            }
            catch
            {
                return false;
            }
        }
    }

    public static void Set(bool enabled, string exe)
    {
        if (!Supported) return;
        using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled) key.SetValue(RunName, "\"" + exe + "\"");
        else key.DeleteValue(RunName, throwOnMissingValue: false);
    }
}
