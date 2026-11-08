using System.Net;
using System.Text;
using Xunit;

namespace Mochinotch.Win.Tests;

public class EdgeMotionTests
{
    [Fact]
    public void Pour_reaches_the_bottom_and_then_the_light_fades()
    {
        Assert.Equal(0, EdgeMotion.Level(0), 3);
        Assert.True(EdgeMotion.Level(1.74) > 0.95);
        Assert.True(EdgeMotion.Swell(1.45) > 0.99);
        var (progress, front) = EdgeMotion.Pour(EdgeMotion.PourDuration);
        Assert.Equal(1, progress, 3);
        Assert.Equal(0, front, 3);
        Assert.True(EdgeMotion.Pour(0.2).Front > 0);
        Assert.True(EdgeMotion.Level(EdgeMotion.Duration) < 0.01);
        Assert.True(EdgeMotion.WindowOpacity(0.12) > 0.95);
    }

    [Fact]
    public void Streak_travels_from_the_left()
    {
        var early = EdgeMotion.Streak(0.1);
        var later = EdgeMotion.Streak(0.4);
        Assert.True(later.Head > early.Head);
    }
}

public class IslandModelTests
{
    [Fact]
    public void Completed_agent_stays_on_the_left_and_plays_the_edge()
    {
        var model = new IslandModel(persist: false);
        model.Ingest(new IncomingEvent { Tool = "cursor", Kind = "completed", Title = "Cursor 작업 완료", Detail = "app" }, 0);
        Assert.Equal(Presentation.Idle, model.Presentation);
        Assert.Single(model.Toasts(0));
        Assert.True(model.EdgeVisible);
        Assert.Equal(2.2, model.EdgeRim);
        model.Tick(1);
        Assert.True(model.EdgeStrength > 0.5);
        Assert.Single(model.Toasts(1));
        model.Tick(6);
        Assert.Equal(Presentation.Idle, model.Presentation);
        Assert.False(model.EdgeVisible);
        Assert.Empty(model.Toasts(6));
        var icons = model.LeftIcons();
        Assert.Single(icons);
        Assert.Equal(AgentTool.Cursor, icons[0].Tool);
    }

    [Fact]
    public void Confirm_stays_open_and_does_not_light_the_edge()
    {
        var model = new IslandModel(persist: false);
        model.Ingest(new IncomingEvent { Tool = "claude", Kind = "needsInput", Title = "Claude 확인 필요" }, 0);
        Assert.False(model.EdgeVisible);
        Assert.Equal(Presentation.Idle, model.Presentation);
        model.Tick(20);
        var toasts = model.Toasts(20);
        Assert.Single(toasts);
        Assert.Equal(AgentOutcome.NeedsInput, toasts[0].Outcome);
    }

    [Fact]
    public void Cancelled_work_does_not_stay_or_glow()
    {
        var model = new IslandModel(persist: false);
        model.Ingest(new IncomingEvent { Tool = "cursor", Kind = "cancelled" }, 0);
        Assert.False(model.EdgeVisible);
        Assert.Single(model.Toasts(0));
        model.Tick(4);
        Assert.Empty(model.Toasts(4));
        Assert.Empty(model.LeftIcons());
    }

    [Fact]
    public void Duplicate_hook_is_one_notice()
    {
        var model = new IslandModel(persist: false);
        var incoming = new IncomingEvent { Id = "cursor:1", Tool = "cursor", Kind = "completed" };
        model.Ingest(incoming, 0);
        model.Ingest(incoming, 1);
        Assert.Single(model.Notes);
    }

    [Fact]
    public void Resolved_question_closes()
    {
        var model = new IslandModel(persist: false);
        model.Ingest(new IncomingEvent { Tool = "cursor", Kind = "needsInput" }, 0);
        model.Ingest(new IncomingEvent { Tool = "cursor", Kind = "resolved" }, 1);
        Assert.Empty(model.Notes);
        Assert.Equal(Presentation.Idle, model.Presentation);
    }

    [Fact]
    public void Agents_grow_the_pill_to_the_left_only()
    {
        var idle = IslandMetrics.Resolve(Presentation.Idle, 0, 0, false);
        var agents = IslandMetrics.Resolve(Presentation.Idle, 2, 0, false);
        Assert.Equal(160, idle.Width);
        Assert.True(agents.Width > idle.Width);
        Assert.True(agents.Shift < 0);
        Assert.Equal(32, agents.Height);
    }

    [Fact]
    public void Focusing_the_agent_tucks_its_icon()
    {
        var model = new IslandModel(persist: false);
        model.Ingest(new IncomingEvent { Tool = "codex", Kind = "completed" }, 0);
        model.Tick(6);
        model.NoteForeground(AgentTool.Codex, 6);
        Assert.Empty(model.LeftIcons());
    }

    [Fact]
    public void Update_events_are_ignored()
    {
        var model = new IslandModel(persist: false);
        model.Ingest(new IncomingEvent { Kind = "update", Title = "9.9.9" }, 0);
        Assert.Empty(model.Notes);
    }
}

public class HookRelayTests
{
    [Fact]
    public void Claude_stop_is_a_completion()
    {
        var result = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "claude"]),
            """{"hook_event_name":"Stop","cwd":"/work/mochinotch"}""",
            new Dictionary<string, string>());
        Assert.NotNull(result.Event);
        Assert.Equal("claude", result.Event.Tool);
        Assert.Equal("completed", result.Event.Kind);
        Assert.Equal("mochinotch", result.Event.Detail);
        Assert.False(result.AcknowledgeCursor);
    }

    [Fact]
    public void Claude_notification_that_is_not_a_question_is_dropped()
    {
        var result = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "claude"]),
            """{"hook_event_name":"Notification","notification_type":"permission_prompt"}""",
            new Dictionary<string, string>());
        Assert.Null(result.Event);
    }

    [Fact]
    public void Claude_question_asks_for_confirmation()
    {
        var result = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "claude"]),
            """{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"title":"배포할까요?"}}""",
            new Dictionary<string, string>());
        Assert.Equal("needsInput", result.Event?.Kind);
        Assert.Equal("배포할까요?", result.Event?.Detail);
    }

    [Fact]
    public void Cursor_stop_acknowledges_and_dedupes()
    {
        var result = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "cursor"]),
            """{"hook_event_name":"stop","status":"completed","generation_id":"gen-1","workspace_roots":["/work/app"]}""",
            new Dictionary<string, string>());
        Assert.True(result.AcknowledgeCursor);
        Assert.Equal("cursor", result.Event?.Tool);
        Assert.Equal("cursor:gen-1", result.Event?.Id);
        Assert.Equal("app", result.Event?.Detail);
    }

    [Fact]
    public void Cursor_shell_approval_is_not_an_agent_notice()
    {
        var result = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "cursor"]),
            """{"hook_event_name":"beforeShellExecution"}""",
            new Dictionary<string, string>());
        Assert.Null(result.Event);
        Assert.False(result.AcknowledgeCursor);
    }

    [Fact]
    public void Codex_turn_completes_once()
    {
        var result = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "codex", """{"type":"agent-turn-complete","turn-id":"t1","cwd":"/tmp/demo"}"""]),
            "",
            new Dictionary<string, string>());
        Assert.Equal("completed", result.Event?.Kind);
        Assert.Equal("codex:t1", result.Event?.Id);
        Assert.Equal("demo", result.Event?.Detail);
    }

    [Fact]
    public void Claude_hook_from_cursor_is_cursor()
    {
        var result = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "claude"]),
            """{"hook_event_name":"Stop","cursor_version":"1.0","cwd":"/work/app"}""",
            new Dictionary<string, string>());
        Assert.Equal("cursor", result.Event?.Tool);
        Assert.True(result.AcknowledgeCursor);
    }
}

public class HookInstallerTests
{
    [Fact]
    public void Cursor_hooks_are_agent_events_only()
    {
        var home = TempHome();
        var exe = @"C:\Mochinotch\Mochinotch.exe";
        var changed = HookInstaller.Install(home, exe, [HookTool.Cursor]);
        Assert.Contains(HookTool.Cursor, changed.Changed);
        var text = File.ReadAllText(Path.Combine(home, ".cursor", "hooks.json"));
        Assert.Contains("--hook --source cursor", text);
        Assert.Contains("AskQuestion|AskUserQuestion", text);
        Assert.DoesNotContain("toast", text, StringComparison.OrdinalIgnoreCase);
        Assert.False(HookInstaller.Install(home, exe, [HookTool.Cursor]).Changed.Contains(HookTool.Cursor) && !text.Contains(exe));
        Assert.True(HookInstaller.IsConnected(home, HookTool.Cursor, exe));
        var moved = @"D:\Apps\Mochinotch.exe";
        Assert.Contains(HookTool.Cursor, HookInstaller.Install(home, moved, [HookTool.Cursor]).Changed);
        var updated = File.ReadAllText(Path.Combine(home, ".cursor", "hooks.json"));
        Assert.Contains(moved.Replace("\\", "\\\\"), updated);
        Assert.DoesNotContain(exe.Replace("\\", "\\\\"), updated);
    }

    [Fact]
    public void Claude_question_hook_has_a_matcher()
    {
        var home = TempHome();
        HookInstaller.Install(home, "/Applications/Mochinotch", [HookTool.Claude]);
        var text = File.ReadAllText(Path.Combine(home, ".claude", "settings.json"));
        Assert.Contains("AskUserQuestion", text);
        Assert.Contains("--source claude", text);
        Assert.True(HookInstaller.IsConnected(home, HookTool.Claude, "/Applications/Mochinotch"));
    }

    [Fact]
    public void Codex_notify_chains_the_previous_command()
    {
        var home = TempHome();
        Directory.CreateDirectory(Path.Combine(home, ".codex"));
        File.WriteAllText(Path.Combine(home, ".codex", "config.toml"), "notify = [\"old-notify\"]\n\n[model]\nname = \"keep\"\n");
        HookInstaller.Install(home, "C:/Mochinotch.exe", [HookTool.Codex]);
        var text = File.ReadAllText(Path.Combine(home, ".codex", "config.toml"));
        Assert.Contains("C:/Mochinotch.exe", text);
        Assert.Contains("--hook", text);
        Assert.Contains("--chain", text);
        Assert.Contains("old-notify", text);
        Assert.Contains("[model]", text);
        Assert.Contains("PermissionRequest", File.ReadAllText(Path.Combine(home, ".codex", "hooks.json")));
        Assert.True(HookInstaller.IsConnected(home, HookTool.Codex, "C:/Mochinotch.exe"));
    }

    static string TempHome()
    {
        var path = Path.Combine(Path.GetTempPath(), "mochinotch-win-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(path);
        return path;
    }
}

public class EventServerTests
{
    [Fact]
    public async Task Local_event_requires_the_token()
    {
        var previous = EventToken.StoragePath;
        var home = Path.Combine(Path.GetTempPath(), "mochinotch-token-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(home);
        EventToken.StoragePath = Path.Combine(home, "event.token");
        var port = FreePort();
        using var server = new EventServer(port);
        IncomingEvent? got = null;
        server.OnEvent += incoming => got = incoming;
        server.Start();
        Assert.Null(server.Failure);
        var token = EventToken.Current();
        Assert.False(string.IsNullOrEmpty(token));
        using var client = new HttpClient();
        var denied = new HttpRequestMessage(HttpMethod.Post, $"http://127.0.0.1:{port}/event")
        {
            Content = new StringContent("""{"tool":"cursor","kind":"completed"}""", Encoding.UTF8, "application/json"),
        };
        denied.Headers.TryAddWithoutValidation(EventEndpoint.Header, "nope");
        var deniedResponse = await client.SendAsync(denied);
        Assert.Equal(HttpStatusCode.Unauthorized, deniedResponse.StatusCode);
        var allowed = new HttpRequestMessage(HttpMethod.Post, $"http://127.0.0.1:{port}/event")
        {
            Content = new StringContent("""{"tool":"cursor","kind":"completed","title":"done"}""", Encoding.UTF8, "application/json"),
        };
        allowed.Headers.TryAddWithoutValidation(EventEndpoint.Header, token);
        var allowedResponse = await client.SendAsync(allowed);
        Assert.Equal(HttpStatusCode.NoContent, allowedResponse.StatusCode);
        var until = DateTime.UtcNow.AddSeconds(2);
        while (got == null && DateTime.UtcNow < until) await Task.Delay(20);
        Assert.Equal("cursor", got?.Tool);
        Assert.Equal("completed", got?.Kind);
        EventToken.StoragePath = previous;
    }

    static int FreePort()
    {
        var listener = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }
}
