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
            using var proc = System.Diagnostics.Process.GetProcessById((int)pid);
            var name = proc.ProcessName;
            return name.ToLowerInvariant() switch
            {
                "cursor" => AgentTool.Cursor,
                "claude" => AgentTool.Claude,
                "codex" => AgentTool.Codex,
                "kiro" => AgentTool.Kiro,
                "antigravity" => AgentTool.Antigravity,
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
            AgentTool.Antigravity => new[] { "Antigravity" },
            _ => Array.Empty<string>(),
        };
        foreach (var name in names)
        {
            var procs = System.Diagnostics.Process.GetProcessesByName(name);
            try
            {
                var proc = procs.FirstOrDefault(item => item.MainWindowHandle != 0);
                if (proc == null) continue;
                var hwnd = proc.MainWindowHandle;
                // 최소화돼 있을 때만 복원한다. 최대화된 창에 SW_RESTORE를 부르면 최대화가 풀린다.
                if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
                var foreground = GetForegroundWindow();
                var foregroundThread = foreground != 0 ? GetWindowThreadProcessId(foreground, out _) : 0;
                var targetThread = GetWindowThreadProcessId(hwnd, out _);
                var current = GetCurrentThreadId();
                var attachedForeground = foregroundThread != 0 && foregroundThread != current && AttachThreadInput(current, foregroundThread, true);
                var attachedTarget = targetThread != 0 && targetThread != current && targetThread != foregroundThread && AttachThreadInput(current, targetThread, true);
                SetForegroundWindow(hwnd);
                if (attachedTarget) AttachThreadInput(current, targetThread, false);
                if (attachedForeground) AttachThreadInput(current, foregroundThread, false);
                return;
            }
            finally
            {
                foreach (var item in procs) item.Dispose();
            }
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
    static extern bool IsIconic(nint hwnd);

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
