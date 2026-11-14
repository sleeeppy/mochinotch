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

public class EdgeFrameTests
{
    [Fact]
    public void Same_aspect_grows_the_band_with_resolution()
    {
        var hd = EdgeFrame.Measure(1920, 1080);
        var uhd = EdgeFrame.Measure(3840, 2160);
        Assert.Equal(hd.BandY / 1080, uhd.BandY / 2160, 3);
        Assert.True(uhd.BandY > hd.BandY * 1.9);
        Assert.True(uhd.BandX > hd.BandX * 1.9);
    }

    [Fact]
    public void Ultrawide_sides_stay_near_the_shorter_side()
    {
        var normal = EdgeFrame.Measure(2560, 1440);
        var ultra = EdgeFrame.Measure(5120, 1440);
        Assert.True(ultra.BandY < normal.BandY);
        Assert.True(ultra.BandX < normal.BandX * 1.15);
        Assert.True(ultra.BandX / 5120 < normal.BandX / 2560);
    }

    [Fact]
    public void Portrait_uses_a_different_fraction_than_landscape()
    {
        var landscape = EdgeFrame.Measure(1920, 1080);
        var portrait = EdgeFrame.Measure(1080, 1920);
        Assert.NotEqual(Math.Round(landscape.BandY / 1080, 3), Math.Round(portrait.BandY / 1920, 3));
        Assert.True(portrait.BandX / 1080 > landscape.BandX / 1920);
    }

    [Fact]
    public void Pour_reaches_the_far_corner_on_every_aspect()
    {
        foreach (var (width, height) in new[] { (1920d, 1080d), (5120d, 1440d), (1080d, 1920d), (1600d, 1200d) })
        {
            Assert.Equal(0, EdgeFrame.Span(width / 2, 0, width, height), 3);
            Assert.Equal(1, EdgeFrame.Span(0, height, width, height), 2);
            Assert.Equal(1, EdgeFrame.Span(width, height, width, height), 2);
        }
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
        Assert.Single(model.Toasts(6));
        var icons = model.LeftIcons();
        Assert.Single(icons);
        Assert.Equal(AgentTool.Cursor, icons[0].Tool);
        model.NoteForeground(AgentTool.Cursor, 7);
        Assert.Empty(model.Toasts(7));
        Assert.Empty(model.LeftIcons());
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
        Assert.Empty(model.Toasts(0));
        model.Tick(4);
        Assert.Empty(model.Toasts(4));
        Assert.Empty(model.LeftIcons());
    }

    [Fact]
    public void Failed_work_does_not_overlay()
    {
        var model = new IslandModel(persist: false);
        model.Ingest(new IncomingEvent { Tool = "cursor", Kind = "failed" }, 0);
        Assert.False(model.EdgeVisible);
        Assert.Empty(model.Toasts(0));
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
    public void Open_question_toast_survives_a_later_completion()
    {
        var model = new IslandModel(persist: false);
        model.Ingest(new IncomingEvent { Id = "toast:1", Tool = "cursor", Kind = "needsInput" }, 0);
        model.Ingest(new IncomingEvent { Tool = "cursor", Kind = "completed" }, 3);
        Assert.Equal(AgentOutcome.NeedsInput, model.Toasts(3)[0].Outcome);
        model.NoteForeground(AgentTool.Cursor, 4);
        Assert.Empty(model.Toasts(4));
    }

    [Fact]
    public void Hook_question_closes_when_the_work_finishes()
    {
        var model = new IslandModel(persist: false);
        model.Ingest(new IncomingEvent { Tool = "claude", Kind = "needsInput" }, 0);
        model.Ingest(new IncomingEvent { Tool = "claude", Kind = "completed" }, 3);
        Assert.DoesNotContain(model.Notes, note => note.Outcome == AgentOutcome.NeedsInput);
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

public class WinUpdateTests
{
    const string Page = "https://github.com/sleeeppy/mochinotch/releases/tag/v0.9.0";
    const string Exe = "https://github.com/sleeeppy/mochinotch/releases/download/v0.9.0/Mochinotch-win-x64.exe";
    const string Api = "https://api.github.com/repos/sleeeppy/mochinotch/releases/assets/1";

    [Fact]
    public void Newer_windows_asset_is_offered()
    {
        var release = WinUpdate.FromLatest(ReleaseJson("v0.9.0", includeWindows: true), "0.6.12");
        Assert.Equal("0.9.0", release?.Version);
        Assert.Equal(Api, release?.Download);
        Assert.Equal("Mochinotch-win-x64.exe", release?.FileName);
        Assert.Equal(Page, release?.Page);
    }

    [Fact]
    public void Mac_only_release_is_not_a_windows_update()
    {
        Assert.Null(WinUpdate.FromLatest(ReleaseJson("v0.9.0", includeWindows: false), "0.6.12"));
    }

    [Fact]
    public void Same_or_older_release_is_ignored()
    {
        Assert.Null(WinUpdate.FromLatest(ReleaseJson("v0.6.12", includeWindows: true), "0.6.12"));
        Assert.Null(WinUpdate.FromLatest(ReleaseJson("v0.6.1", includeWindows: true), "0.6.12"));
    }

    [Fact]
    public void Download_outside_github_is_rejected()
    {
        var json = """
            {"tag_name":"v1.0.0","html_url":"https://github.com/sleeeppy/mochinotch/releases/tag/v1.0.0",
             "assets":[{"name":"Mochinotch-win-x64.exe","browser_download_url":"https://evil.example/app.exe"}]}
            """;
        Assert.Null(WinUpdate.FromLatest(json, "0.6.12"));
    }

    [Fact]
    public void Install_target_is_the_running_executable()
    {
        var running = Path.Combine("C", "Apps", "Mochinotch-win-x64.exe");
        Assert.Equal(running, WinUpdate.InstallTarget(running, Path.Combine("C", "Apps")));
    }

    [Fact]
    public void Install_target_falls_back_when_the_process_path_is_missing()
    {
        var directory = Path.Combine("C", "Apps");
        Assert.Equal(
            Path.Combine(directory, "Mochinotch.exe"),
            WinUpdate.InstallTarget("  ", directory + Path.DirectorySeparatorChar));
    }

    [Fact]
    public void Swap_script_replaces_the_running_file_and_starts_it_again()
    {
        var destination = Path.Combine("D", "Apps", "Mochinotch-win-x64.exe");
        var staged = Path.Combine("C", "temp", "new.exe");
        var script = WinUpdate.SwapScript(42, staged, destination);
        Assert.Contains("Wait-Process -Id 42", script);
        Assert.Contains($"-Destination '{destination}'", script);
        Assert.Contains($"-FilePath '{destination}'", script);
        Assert.DoesNotContain("Mochinotch.exe", script);
    }

    [Fact]
    public void Swap_script_escapes_quotes()
    {
        var destination = Path.Combine("C", "O'Brien", "Mochinotch.exe");
        var script = WinUpdate.SwapScript(1, destination, destination);
        Assert.Contains($"'{destination.Replace("'", "''")}'", script);
    }

    [Fact]
    public void A_writable_folder_can_be_replaced()
    {
        var directory = Directory.CreateTempSubdirectory("mn-update").FullName;
        try
        {
            Assert.True(WinUpdate.CanReplace(Path.Combine(directory, "Mochinotch-win-x64.exe")));
            Assert.False(WinUpdate.CanReplace(Path.Combine(directory, "missing", "app.exe")));
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    static string ReleaseJson(string tag, bool includeWindows)
    {
        var windows = includeWindows
            ? $$""",{"name":"Mochinotch-win-x64.exe","url":"{{Api}}","browser_download_url":"{{Exe}}","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"""
            : "";
        return $$"""
            {"tag_name":"{{tag}}","html_url":"{{Page}}","assets":[
              {"name":"Mochinotch.dmg","browser_download_url":"https://github.com/sleeeppy/mochinotch/releases/download/{{tag}}/Mochinotch.dmg"}{{windows}}
            ]}
            """;
    }
}

public class AgentNoticeTests
{
    [Fact]
    public void Cursor_input_needed_toast_is_a_confirmation()
    {
        var incoming = AgentNotices.Interpret(
            "Anysphere.Cursor",
            "Input needed • \"배포할까요?\"",
            "Open Cursor to answer the agent's questions.");
        Assert.Equal("cursor", incoming?.Tool);
        Assert.Equal("needsInput", incoming?.Kind);
        Assert.Equal("배포할까요?", incoming?.Detail);
    }

    [Fact]
    public void Cursor_done_toast_is_left_to_the_hook()
    {
        Assert.Null(AgentNotices.Interpret("Anysphere.Cursor", "Done • Win branch deployment", "Open Cursor to view the agent's output."));
    }

    [Fact]
    public void Other_apps_are_ignored()
    {
        Assert.Null(AgentNotices.Interpret("Microsoft.Todos", "Input needed • 오늘", ""));
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
    public void Codex_subagent_permission_stays_quiet()
    {
        var child = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "codex", """{"hook_event_name":"PermissionRequest","tool_name":"Bash","agent_id":"child-thread","tool_input":{"command":"ls"}}"""]),
            "",
            new Dictionary<string, string>());
        Assert.Null(child.Event);
        var blank = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "codex", """{"hook_event_name":"PermissionRequest","tool_name":"Bash","agent_id":"","tool_input":{"command":"ls"}}"""]),
            "",
            new Dictionary<string, string>());
        Assert.Equal("needsInput", blank.Event?.Kind);
        Assert.Equal("Bash · ls", blank.Event?.Detail);
    }

    [Fact]
    public void Codex_parent_permission_and_only_finished_turns_notify()
    {
        var ask = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "codex", """{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"""]),
            "",
            new Dictionary<string, string>());
        Assert.Equal("needsInput", ask.Event?.Kind);
        Assert.Equal("Bash · ls", ask.Event?.Detail);
        var empty = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "codex", """{"hook_event_name":"PermissionRequest"}"""]),
            "",
            new Dictionary<string, string>());
        Assert.Null(empty.Event);
        var start = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "codex", """{"type":"agent-turn-start"}"""]),
            "",
            new Dictionary<string, string>());
        Assert.Null(start.Event);
        var blank = HookRelay.Relay(
            HookRelay.Options.Parse(["--source", "codex", "{}"]),
            "",
            new Dictionary<string, string>());
        Assert.Null(blank.Event);
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
