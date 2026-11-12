using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace Mochinotch.Win;

public sealed record OutgoingEvent(
    string Tool,
    string Title,
    string Detail,
    string Kind,
    bool Success,
    string? Id,
    string? BundleID);

public sealed record RelayResult(bool AcknowledgeCursor, OutgoingEvent? Event);

/// <summary>
/// <c>Mochinotch --hook --source claude|cursor|codex|kiro</c>.
/// 맥 앱의 hook 해석과 같다. 시스템 알림은 만들지 않는다.
/// </summary>
public static class HookRelay
{
    public static Action<IReadOnlyList<string>>? ChainRunner { get; set; }

    public static int Run(string[] args)
    {
        var options = Options.Parse(args);
        var argPayload = options.Positional.LastOrDefault() ?? "";
        var readsStdin = Console.IsInputRedirected && !(options.Source == "codex" && argPayload.Length > 0);
        var stdin = readsStdin ? Console.In.ReadToEnd() : "";
        var env = Environment.GetEnvironmentVariables()
            .Cast<System.Collections.DictionaryEntry>()
            .ToDictionary(entry => (string)entry.Key, entry => entry.Value?.ToString() ?? "", StringComparer.Ordinal);
        var result = Relay(options, stdin, env);
        if (result.Event != null) Post(result.Event);
        if (result.AcknowledgeCursor)
        {
            try
            {
                Console.Out.Write("{}\n");
                Console.Out.Flush();
            }
            catch
            {
                // 표준 출력이 없는 GUI 실행.
            }
        }
        return 0;
    }

    public static RelayResult Relay(Options options, string stdin, IReadOnlyDictionary<string, string> env)
    {
        var argPayload = options.Positional.LastOrDefault() ?? "";
        if (options.Chain.Length > 0)
            RunChain(options.Chain, argPayload);

        var bundle = options.Bundle;
        if (bundle.Length == 0 && env.TryGetValue("TERM_PROGRAM", out var program))
        {
            bundle = program switch
            {
                "Apple_Terminal" => "com.apple.Terminal",
                "iTerm.app" => "com.googlecode.iterm2",
                "ghostty" => "com.mitchellh.ghostty",
                "WarpTerminal" => "dev.warp.Warp-Stable",
                _ => "",
            };
        }
        if (bundle.Length == 0
            && env.TryGetValue("__CFBundleIdentifier", out var hosting)
            && hosting.Length > 0)
        {
            bundle = hosting;
        }

        var stdinEvent = Object(stdin);
        var argEvent = Object(argPayload);
        var fromCursor = stdinEvent.ContainsKey("cursor_version")
            || (stdinEvent.ContainsKey("conversation_id") && !stdinEvent.ContainsKey("session_id"));
        var source = options.Source;
        if (source == "claude" && fromCursor)
            source = "cursor";

        var tool = options.Tool;
        var title = options.Title;
        var detail = options.Detail;
        var kind = options.Kind;
        string? dedupe = null;

        switch (source)
        {
            case "claude":
                if (tool.Length == 0) tool = "claude";
                switch (Str(stdinEvent, "hook_event_name"))
                {
                    case "PermissionRequest":
                        if (kind.Length == 0) kind = "needsInput";
                        if (title.Length == 0) title = "Claude 확인 필요";
                        if (detail.Length == 0) detail = WaitingDetail(stdinEvent);
                        break;
                    case "PreToolUse":
                        if (!IsUserQuestion(Str(stdinEvent, "tool_name")))
                            return new RelayResult(false, null);
                        if (kind.Length == 0) kind = "needsInput";
                        if (title.Length == 0) title = "Claude 확인 필요";
                        if (detail.Length == 0) detail = QuestionDetail(stdinEvent);
                        break;
                    case "Notification":
                        var type = Str(stdinEvent, "notification_type");
                        var asks = new[] { "agent_needs_input", "elicitation_dialog", "elicitation_url_dialog" };
                        if (!asks.Contains(type)) return new RelayResult(false, null);
                        if (kind.Length == 0) kind = "needsInput";
                        if (title.Length == 0) title = NonEmpty(Str(stdinEvent, "title")) ?? "Claude 확인 필요";
                        if (detail.Length == 0) detail = FirstLine(Str(stdinEvent, "message"));
                        break;
                    case "StopFailure":
                        if (kind.Length == 0) kind = "failed";
                        if (title.Length == 0) title = "Claude Code 실패";
                        break;
                    default:
                        if (kind.Length == 0) kind = "completed";
                        if (title.Length == 0) title = "Claude Code 작업 완료";
                        if (detail.Length == 0) detail = FolderName(Str(stdinEvent, "cwd"));
                        break;
                }
                break;
            case "cursor":
                if (tool.Length == 0) tool = "cursor";
                var eventName = Str(stdinEvent, "hook_event_name");
                if (eventName is "beforeShellExecution" or "beforeMCPExecution")
                    return new RelayResult(false, null);
                if (eventName == "preToolUse")
                {
                    if (!IsUserQuestion(Str(stdinEvent, "tool_name")))
                        return new RelayResult(false, null);
                    if (kind.Length == 0) kind = "needsInput";
                    if (title.Length == 0) title = "Cursor 확인 필요";
                    if (detail.Length == 0) detail = QuestionDetail(stdinEvent);
                    var id = Str(stdinEvent, "tool_use_id").Split('\n')[0];
                    if (id.Length > 0) dedupe = "cursor-ask:" + id;
                }
                else if (eventName == "postToolUse")
                {
                    if (!IsUserQuestion(Str(stdinEvent, "tool_name")))
                        return new RelayResult(false, null);
                    kind = "resolved";
                }
                else
                {
                    var status = (Str(stdinEvent, "status").Length == 0 ? "completed" : Str(stdinEvent, "status")).ToLowerInvariant();
                    if (status == "error")
                    {
                        if (kind.Length == 0) kind = "failed";
                        if (title.Length == 0) title = "Cursor 작업 실패";
                    }
                    else if (status is "aborted" or "cancelled" or "canceled")
                    {
                        if (kind.Length == 0) kind = "cancelled";
                        if (title.Length == 0) title = "Cursor 작업 중단";
                    }
                    else
                    {
                        if (kind.Length == 0) kind = "completed";
                        if (title.Length == 0) title = "Cursor 작업 완료";
                    }
                    if (detail.Length == 0 && stdinEvent.TryGetValue("workspace_roots", out var roots) && roots.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var root in roots.EnumerateArray())
                        {
                            detail = FolderName(root.ValueKind == JsonValueKind.String ? root.GetString() ?? "" : root.ToString());
                            break;
                        }
                    }
                }
                break;
            case "kiro":
                if (tool.Length == 0) tool = "kiro";
                if (kind.Length == 0) kind = "completed";
                if (title.Length == 0) title = "Kiro 작업 완료";
                if (detail.Length == 0) detail = FolderName(Str(stdinEvent, "cwd"));
                break;
            case "codex":
                var codex = argEvent.Count > 0 ? argEvent : stdinEvent;
                var notice = CodexNoticeOf(codex);
                if (notice == null) return new RelayResult(false, null);
                if (tool.Length == 0) tool = "codex";
                if (kind.Length == 0) kind = notice.Value.Kind;
                if (title.Length == 0) title = notice.Value.Title;
                if (detail.Length == 0) detail = notice.Value.Detail;
                if (dedupe == null) dedupe = notice.Value.Dedupe;
                break;
            default:
                if (tool.Length == 0) tool = "custom";
                if (kind.Length == 0) kind = options.Success == false ? "failed" : "completed";
                if (title.Length == 0) title = "작업 완료";
                break;
        }

        if (options.Success == true && kind.Length == 0) kind = "completed";
        if (options.Success == false) kind = "failed";
        if (kind.Length == 0) kind = "completed";

        if (dedupe == null && source == "cursor" && kind is not ("needsInput" or "resolved"))
        {
            var generation = Str(stdinEvent, "generation_id");
            if (generation.Length > 0) dedupe = "cursor:" + generation;
        }

        var outgoing = new OutgoingEvent(tool, title, detail, kind, kind != "failed", dedupe, bundle.Length == 0 ? null : bundle);
        var acknowledge = source == "cursor" && kind is not ("needsInput" or "resolved");
        return new RelayResult(acknowledge, outgoing);
    }

    public static void Post(OutgoingEvent outgoing)
    {
        var token = EventToken.Current();
        if (token == null) return;
        var payload = new Dictionary<string, object?>
        {
            ["tool"] = outgoing.Tool,
            ["title"] = outgoing.Title,
            ["detail"] = outgoing.Detail,
            ["kind"] = outgoing.Kind,
            ["success"] = outgoing.Success,
        };
        if (outgoing.Id != null) payload["id"] = outgoing.Id;
        if (outgoing.BundleID != null) payload["bundleID"] = outgoing.BundleID;
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(1.5) };
            using var request = new HttpRequestMessage(HttpMethod.Post, $"http://127.0.0.1:{EventEndpoint.Port}/event");
            request.Headers.TryAddWithoutValidation(EventEndpoint.Header, token);
            request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
            client.Send(request);
        }
        catch
        {
            // 앱이 꺼져 있으면 조용히 끝난다.
        }
    }

    static void RunChain(string raw, string extra)
    {
        List<string>? command;
        try
        {
            command = JsonSerializer.Deserialize<List<string>>(raw);
        }
        catch
        {
            return;
        }
        if (command == null || command.Count == 0) return;
        if (extra.Length > 0) command.Add(extra);
        if (ChainRunner != null)
        {
            ChainRunner(command);
            return;
        }
        try
        {
            var start = new ProcessStartInfo(command[0])
            {
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            foreach (var argument in command.Skip(1))
                start.ArgumentList.Add(argument);
            Process.Start(start);
        }
        catch
        {
            // 이전 notify가 없어도 우리 알림은 보낸다.
        }
    }

    static bool IsUserQuestion(string name)
    {
        var normalized = name.ToLowerInvariant().Replace("_", "");
        return normalized is "askquestion" or "askuserquestion";
    }

    static string QuestionDetail(Dictionary<string, JsonElement> ev)
    {
        var input = Child(ev, "tool_input");
        var title = FirstLine(NonEmpty(Str(input, "title")) ?? Str(input, "prompt"));
        return title.Length == 0 ? "답변을 기다리고 있어요" : title;
    }

    /// <summary>Codex hook이 노치에 올릴 내용. 올릴 게 없으면 null.</summary>
    readonly record struct CodexNotice(string Kind, string Title, string Detail, string? Dedupe);

    static CodexNotice? CodexNoticeOf(Dictionary<string, JsonElement> ev)
    {
        var type = Str(ev, "type");
        if (Str(ev, "hook_event_name") == "PermissionRequest")
        {
            // 스레드로 띄운 서브에이전트는 명령마다 이 hook이 온다. 사용자 앞의 승인 창이 아니다.
            if (Str(ev, "agent_id").Length > 0) return null;
            var ask = PermissionDetail(ev);
            if (Str(ev, "tool_name").Length == 0 && ask.Length == 0) return null;
            return new CodexNotice("needsInput", "Codex 확인 필요", ask, null);
        }
        if (type == "agent-turn-complete")
        {
            var turn = Str(ev, "turn-id");
            var detail = FirstLine(Str(ev, "last-assistant-message"));
            if (detail.Length == 0) detail = FolderName(Str(ev, "cwd"));
            return new CodexNotice("completed", "Codex 작업 완료", detail, turn.Length > 0 ? "codex:" + turn : null);
        }
        return null;
    }

    static string WaitingDetail(Dictionary<string, JsonElement> ev)
        => IsUserQuestion(Str(ev, "tool_name")) ? QuestionDetail(ev) : PermissionDetail(ev);

    static string PermissionDetail(Dictionary<string, JsonElement> ev)
    {
        var name = Str(ev, "tool_name");
        var input = Child(ev, "tool_input");
        var summary = FirstLine(NonEmpty(Str(input, "command")) ?? NonEmpty(Str(input, "file_path")) ?? Str(input, "description"));
        if (name.Length == 0) return summary;
        if (summary.Length == 0) return name;
        var line = $"{name} · {summary}";
        return line.Length <= 90 ? line : line[..90];
    }

    static string FirstLine(string text, int limit = 90)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) return "";
        var line = trimmed.Split('\n', '\r')[0].Trim();
        return line.Length <= limit ? line : line[..limit];
    }

    static string FolderName(string path)
    {
        if (path.Length == 0) return "";
        return Path.GetFileName(path.TrimEnd('\\', '/'));
    }

    static string? NonEmpty(string text) => text.Length == 0 ? null : text;

    static Dictionary<string, JsonElement> Object(string json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new();
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return new();
            return doc.RootElement.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.Clone());
        }
        catch
        {
            return new();
        }
    }

    static Dictionary<string, JsonElement> Child(Dictionary<string, JsonElement> obj, string key)
    {
        if (!obj.TryGetValue(key, out var value) || value.ValueKind != JsonValueKind.Object) return new();
        return value.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.Clone());
    }

    static string Str(Dictionary<string, JsonElement> obj, string key)
    {
        if (!obj.TryGetValue(key, out var value) || value.ValueKind != JsonValueKind.String) return "";
        return value.GetString() ?? "";
    }

    public sealed class Options
    {
        public string Source { get; set; } = "";
        public string Tool { get; set; } = "";
        public string Title { get; set; } = "";
        public string Detail { get; set; } = "";
        public string Kind { get; set; } = "";
        public bool? Success { get; set; }
        public string Bundle { get; set; } = "";
        public string Chain { get; set; } = "";
        public List<string> Positional { get; } = [];

        public static Options Parse(string[] args)
        {
            var options = new Options();
            for (var index = 0; index < args.Length; index++)
            {
                string Value() => ++index < args.Length ? args[index] : "";
                switch (args[index])
                {
                    case "--source": options.Source = Value(); break;
                    case "--tool": options.Tool = Value(); break;
                    case "--title": options.Title = Value(); break;
                    case "--detail": options.Detail = Value(); break;
                    case "--kind": options.Kind = Value(); break;
                    case "--bundle-id": options.Bundle = Value(); break;
                    case "--success": options.Success = true; break;
                    case "--failure":
                        options.Success = false;
                        if (options.Kind.Length == 0) options.Kind = "failed";
                        break;
                    case "--needs-input": options.Kind = "needsInput"; break;
                    case "--chain": options.Chain = Value(); break;
                    case "--":
                        options.Positional.AddRange(args[(index + 1)..]);
                        index = args.Length;
                        break;
                    default:
                        options.Positional.Add(args[index]);
                        break;
                }
            }
            return options;
        }
    }
}
