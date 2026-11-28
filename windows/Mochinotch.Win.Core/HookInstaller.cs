using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Mochinotch.Win;

public enum HookTool
{
    Claude,
    Cursor,
    Codex,
    Kiro,
    Antigravity,
}

public sealed record ToolLink(HookTool Tool, bool Present, bool Connected);

public sealed class InstallResult
{
    public List<HookTool> Changed { get; } = [];
    public List<HookTool> Connected { get; } = [];
    public List<(HookTool Tool, string Problem)> Failures { get; } = [];
}

/// <summary>
/// Cursor, Claude, Codex, Kiro, Antigravity의 hook만 넣는다. Windows 알림은 읽지 않는다.
/// </summary>
public static class HookInstaller
{
    static readonly string[] ClaudeEvents = ["Stop", "Notification", "StopFailure", "PermissionRequest", "PreToolUse"];
    static readonly string[] CursorEvents = ["stop", "preToolUse", "postToolUse"];

    public static string Home { get; set; } = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    public static IReadOnlyList<ToolLink> Scan(string? home = null, string? exe = null)
    {
        home ??= Home;
        exe ??= Environment.ProcessPath ?? "";
        return Enum.GetValues<HookTool>().Select(tool => new ToolLink(tool, IsPresent(home, tool), IsConnected(home, tool, exe))).ToList();
    }

    public static InstallResult Install(string home, string exe, IEnumerable<HookTool> tools)
    {
        var result = new InstallResult();
        foreach (var tool in tools)
        {
            try
            {
                if (Merge(home, exe, tool)) result.Changed.Add(tool);
                result.Connected.Add(tool);
            }
            catch (InvalidDataException ex)
            {
                result.Failures.Add((tool, ex.Message));
            }
            catch (Exception ex)
            {
                result.Failures.Add((tool, ex.Message));
            }
        }
        return result;
    }

    /// <summary>
    /// 이미 연결했지만 다른 위치의 Mochinotch를 가리키는 도구만 지금 exe로 옮긴다.
    /// 설치 프로그램이 portable exe에서 설치 폴더로 옮길 때 쓴다. 연결하지 않은 도구는 건드리지 않는다.
    /// </summary>
    public static InstallResult Relink(string home, string exe)
    {
        var stale = Enum.GetValues<HookTool>()
            .Where(tool => IsConnected(home, tool, "") && !IsConnected(home, tool, exe))
            .ToList();
        return Install(home, exe, stale);
    }

    /// <summary>
    /// 설치 프로그램이 Mochinotch를 지울 때 부른다. 도구 설정에서 우리 hook만 빼고 나머지는 그대로 둔다.
    /// Codex notify에 원래 명령을 이어 두었으면(<c>--chain</c>) 그 명령으로 되돌린다.
    /// </summary>
    public static InstallResult Remove(string home)
    {
        var result = new InstallResult();
        foreach (var tool in Enum.GetValues<HookTool>())
        {
            try
            {
                if (Unmerge(home, tool)) result.Changed.Add(tool);
            }
            catch (Exception ex)
            {
                result.Failures.Add((tool, ex.Message));
            }
        }
        return result;
    }

    static bool Unmerge(string home, HookTool tool) => tool switch
    {
        HookTool.Claude => UnmergeHooks(Path.Combine(home, ".claude", "settings.json"), "claude"),
        HookTool.Cursor => UnmergeHooks(Path.Combine(home, ".cursor", "hooks.json"), "cursor"),
        HookTool.Kiro => UnmergeKiro(Path.Combine(home, ".kiro", "hooks", "mochinotch.json")),
        HookTool.Codex => UnmergeCodex(home),
        HookTool.Antigravity => UnmergeAntigravity(AntigravityPath(home)),
        _ => false,
    };

    /// <summary>Claude와 Cursor. <c>hooks</c> 아래 이벤트마다 우리 항목을 빼고, 비면 이벤트도 뺀다.</summary>
    static bool UnmergeHooks(string path, string source)
    {
        var existing = Read(path);
        if (existing == null || !existing.Contains("mochinotch", StringComparison.OrdinalIgnoreCase)) return false;
        if (JsonNode.Parse(existing) is not JsonObject root || root["hooks"] is not JsonObject hooks) return false;
        var removed = false;
        foreach (var pair in hooks.ToList())
        {
            if (pair.Value is not JsonArray list) continue;
            if (!Prune(list, source)) continue;
            removed = true;
            if (list.Count == 0) hooks.Remove(pair.Key);
        }
        if (!removed) return false;
        if (hooks.Count == 0) root.Remove("hooks");
        Write(path, root.ToJsonString(JsonWrite) + "\n", backup: true);
        return true;
    }

    /// <summary>
    /// 목록에서 우리 명령을 뺀다. Claude처럼 묶음 안에 <c>hooks</c>가 있으면 그 안에서 빼고, 빈 묶음도 뺀다.
    /// </summary>
    static bool Prune(JsonArray list, string source)
    {
        var removed = false;
        for (var index = list.Count - 1; index >= 0; index--)
        {
            var item = list[index];
            if (item is JsonObject group && group["hooks"] is JsonArray inner)
            {
                if (!Prune(inner, source)) continue;
                removed = true;
                if (inner.Count == 0) list.RemoveAt(index);
            }
            else if (IsOurs(CommandOf(item), source))
            {
                list.RemoveAt(index);
                removed = true;
            }
        }
        return removed;
    }

    static string? CommandOf(JsonNode? node)
        => node?["command"] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    /// <summary>우리만 쓰는 파일이다. 다른 hook이 없으면 파일째 지운다.</summary>
    static bool UnmergeKiro(string path)
    {
        var existing = Read(path);
        if (existing == null) return false;
        if (JsonNode.Parse(existing) is not JsonObject root || root["hooks"] is not JsonArray hooks) return false;
        var before = hooks.Count;
        for (var index = hooks.Count - 1; index >= 0; index--)
        {
            if (IsOurs(CommandOf(hooks[index]?["action"]), "kiro")) hooks.RemoveAt(index);
        }
        if (hooks.Count == before) return false;
        if (hooks.Count == 0) File.Delete(path);
        else Write(path, root.ToJsonString(JsonWrite) + "\n", backup: true);
        return true;
    }

    /// <summary>이름마다 이벤트를 묶는 파일. 우리 명령을 빼고, 이벤트가 하나도 안 남은 묶음은 지운다.</summary>
    static bool UnmergeAntigravity(string path)
    {
        var existing = Read(path);
        if (existing == null || !existing.Contains("mochinotch", StringComparison.OrdinalIgnoreCase)) return false;
        if (JsonNode.Parse(existing) is not JsonObject root) return false;
        var removed = false;
        foreach (var pair in root.ToList())
        {
            if (pair.Value is not JsonObject entry) continue;
            var touched = false;
            foreach (var ev in entry.ToList())
            {
                if (ev.Value is not JsonArray list || !Prune(list, "antigravity")) continue;
                touched = true;
                if (list.Count == 0) entry.Remove(ev.Key);
            }
            if (!touched) continue;
            removed = true;
            if (!entry.Any(ev => ev.Value is JsonArray)) root.Remove(pair.Key);
        }
        if (!removed) return false;
        Write(path, root.ToJsonString(JsonWrite) + "\n", backup: true);
        return true;
    }

    static bool UnmergeCodex(string home)
    {
        var changed = RemoveLegacyCodexPermissionHooks(home);
        var path = Path.Combine(home, ".codex", "config.toml");
        var existing = Read(path);
        if (existing == null || !TomlNotify.TryFind(existing, out var found)) return changed;
        if (found.Values.Count == 0 || !IsMochinotch(found.Values[0])) return changed;
        string updated;
        var chainAt = found.Values.IndexOf("--chain");
        List<string>? original = null;
        if (chainAt >= 0 && chainAt + 1 < found.Values.Count)
        {
            try
            {
                original = JsonSerializer.Deserialize<List<string>>(found.Values[chainAt + 1]);
            }
            catch (JsonException)
            {
                original = null;
            }
        }
        if (original is { Count: > 0 })
        {
            updated = string.Concat(existing.AsSpan(0, found.Start), "notify = ", TomlNotify.Format(original), existing.AsSpan(found.End));
        }
        else
        {
            // 줄바꿈과, 넣을 때 같이 단 "# Mochinotch" 줄까지 지운다.
            var end = found.End;
            if (end < existing.Length && existing[end] == '\r') end++;
            if (end < existing.Length && existing[end] == '\n') end++;
            var start = found.Start;
            const string marker = "# Mochinotch\n";
            if (start >= marker.Length && existing.AsSpan(start - marker.Length, marker.Length).SequenceEqual(marker)
                && (start == marker.Length || existing[start - marker.Length - 1] == '\n'))
                start -= marker.Length;
            updated = string.Concat(existing.AsSpan(0, start), existing.AsSpan(end));
        }
        if (updated == existing) return changed;
        Write(path, updated, backup: true);
        return true;
    }

    public static bool IsPresent(string home, HookTool tool)
    {
        if (PresenceFolders(tool).Any(folder => Directory.Exists(Path.Combine(home, folder)))) return true;
        return KnownExecutable(tool).Any(File.Exists);
    }

    public static bool IsConnected(string home, HookTool tool, string exe)
    {
        try
        {
            return tool switch
            {
                HookTool.Claude => EventsConnected(Read(Path.Combine(home, ".claude", "settings.json")), "hooks", ClaudeEvents, "claude", exe),
                HookTool.Cursor => EventsConnected(Read(Path.Combine(home, ".cursor", "hooks.json")), "hooks", CursorEvents, "cursor", exe),
                HookTool.Kiro => KiroConnected(Read(Path.Combine(home, ".kiro", "hooks", "mochinotch.json")), exe),
                HookTool.Codex => CodexConnected(home, exe),
                HookTool.Antigravity => AntigravityConnected(Read(AntigravityPath(home)), exe),
                _ => false,
            };
        }
        catch
        {
            return false;
        }
    }

    static bool CodexConnected(string home, string exe)
    {
        var configPath = Path.Combine(home, ".codex", "config.toml");
        var config = File.Exists(configPath) ? File.ReadAllText(configPath) : "";
        if (!TomlNotify.TryFind(config, out var found) || found.Values.Count == 0) return false;
        if (IsMochinotch(found.Values[0]))
            return string.IsNullOrEmpty(exe) || string.Equals(found.Values[0], exe, StringComparison.OrdinalIgnoreCase);
        return found.Values.Any(IsMochinotch);
    }

    static bool Merge(string home, string exe, HookTool tool)
    {
        return tool switch
        {
            HookTool.Claude => MergeJson(Path.Combine(home, ".claude", "settings.json"), root => EnsureClaude(root, Command(exe, "claude"))),
            HookTool.Cursor => MergeJson(Path.Combine(home, ".cursor", "hooks.json"), root =>
            {
                if (root["version"] == null) root["version"] = 1;
                EnsureCursor(root, Command(exe, "cursor"));
            }),
            HookTool.Kiro => MergeKiro(home, exe),
            HookTool.Codex => MergeCodex(home, exe),
            HookTool.Antigravity => MergeAntigravity(home, exe),
            _ => false,
        };
    }

    static string AntigravityPath(string home) => Path.Combine(home, ".gemini", "config", "hooks.json");

    /// <summary>
    /// 이름 하나에 이벤트를 묶는 파일이라, 다른 도구 항목은 두고 <c>mochinotch</c>에 <c>Stop</c>만 넣는다.
    /// 버전에 따라 <c>PreToolUse</c>가 읽히지 않고, 잘못 답하면 도구 호출이 막힌다. 꺼 둔 항목은 켜지 않는다.
    /// </summary>
    static bool MergeAntigravity(string home, string exe)
    {
        var path = AntigravityPath(home);
        var existing = File.Exists(path) ? File.ReadAllText(path) : "";
        var root = ParseObject(existing);
        var command = Command(exe, "antigravity");
        var found = false;
        foreach (var pair in root)
        {
            if (pair.Value is JsonObject entry && entry["Stop"] is JsonArray stops && Retarget(stops, "antigravity", command))
                found = true;
        }
        if (!found)
        {
            var entry = Object(root, "mochinotch");
            Array(entry, "Stop").Add(new JsonObject
            {
                ["type"] = "command",
                ["command"] = command,
                ["timeout"] = 10,
            });
        }
        var updated = root.ToJsonString(JsonWrite) + "\n";
        if (existing == updated) return false;
        Write(path, updated, existing.Length > 0);
        return true;
    }

    static bool AntigravityConnected(string? text, string exe)
    {
        if (text == null || JsonNode.Parse(text) is not JsonObject root) return false;
        return root.Any(pair => pair.Value is JsonObject entry
            && !IsDisabled(entry)
            && ContainsOurs(entry["Stop"], "antigravity", exe));
    }

    static bool MergeJson(string path, Action<JsonObject> edit)
    {
        var existing = File.Exists(path) ? File.ReadAllText(path) : "";
        var root = ParseObject(existing);
        edit(root);
        var updated = root.ToJsonString(JsonWrite) + "\n";
        if (existing == updated) return false;
        Write(path, updated, existing.Length > 0);
        return true;
    }

    static void EnsureClaude(JsonObject root, string command)
    {
        var hooks = Object(root, "hooks");
        foreach (var ev in ClaudeEvents)
        {
            var list = Array(hooks, ev);
            if (!Retarget(list, "claude", command))
                list.Add(ClaudeEntry(command, ev == "PreToolUse" ? "AskUserQuestion" : null));
        }
    }

    static void EnsureCursor(JsonObject root, string command)
    {
        var hooks = Object(root, "hooks");
        foreach (var ev in CursorEvents)
        {
            var list = Array(hooks, ev);
            if (!Retarget(list, "cursor", command))
            {
                var item = new JsonObject { ["command"] = command };
                if (ev is "preToolUse" or "postToolUse")
                    item["matcher"] = "AskQuestion|AskUserQuestion";
                list.Add(item);
            }
        }
    }

    static JsonObject ClaudeEntry(string command, string? matcher)
    {
        var entry = new JsonObject
        {
            ["hooks"] = new JsonArray(new JsonObject
            {
                ["type"] = "command",
                ["command"] = command,
            }),
        };
        if (matcher != null)
        {
            var ordered = new JsonObject { ["matcher"] = matcher };
            foreach (var pair in entry)
                ordered[pair.Key] = pair.Value?.DeepClone();
            return ordered;
        }
        return entry;
    }

    static bool MergeKiro(string home, string exe)
    {
        var path = Path.Combine(home, ".kiro", "hooks", "mochinotch.json");
        var existing = File.Exists(path) ? File.ReadAllText(path) : null;
        if (existing != null && KeepsDisabledKiro(existing))
            return false;
        var command = Command(exe, "kiro");
        var hook = new JsonObject
        {
            ["name"] = "Mochinotch",
            ["description"] = "작업이 끝나면 Mochinotch에 알려요",
            ["trigger"] = "Stop",
            ["action"] = new JsonObject { ["type"] = "command", ["command"] = command },
            ["timeout"] = 10,
        };
        var root = new JsonObject
        {
            ["version"] = "v1",
            ["hooks"] = new JsonArray(hook),
        };
        var updated = root.ToJsonString(JsonWrite) + "\n";
        if (existing == updated) return false;
        Write(path, updated, existing != null);
        return true;
    }

    static bool KeepsDisabledKiro(string existing)
    {
        if (JsonNode.Parse(existing) is not JsonObject root || root["hooks"] is not JsonArray hooks)
            return false;
        foreach (var hook in hooks)
        {
            if (IsDisabled(hook)
                && IsOurs(hook?["action"]?["command"] is JsonValue cmd && cmd.TryGetValue<string>(out var text) ? text : null, "kiro"))
                return true;
        }
        return false;
    }

    static bool KiroConnected(string? text, string exe)
    {
        if (text == null || JsonNode.Parse(text) is not JsonObject root || root["hooks"] is not JsonArray hooks)
            return false;
        foreach (var hook in hooks)
        {
            if (IsDisabled(hook)) continue;
            var trigger = hook?["trigger"] is JsonValue t && t.TryGetValue<string>(out var triggerText) ? triggerText : null;
            var command = hook?["action"]?["command"] is JsonValue c && c.TryGetValue<string>(out var cmdText) ? cmdText : null;
            if (trigger == "Stop" && MatchesOurs(command, "kiro", exe))
                return true;
        }
        return false;
    }

    static bool IsDisabled(JsonNode? hook)
        => hook?["enabled"] is JsonValue flag && flag.TryGetValue<bool>(out var enabled) && !enabled;

    static bool MergeCodex(string home, string exe)
    {
        var cleanedLegacy = RemoveLegacyCodexPermissionHooks(home);
        var path = Path.Combine(home, ".codex", "config.toml");
        var existing = File.Exists(path) ? File.ReadAllText(path) : "";
        var command = new List<string> { exe, "--hook", "--source", "codex" };
        string updated;
        TomlNotify.Found found = default;
        var hasNotify = false;
        try
        {
            hasNotify = TomlNotify.TryFind(existing, out found);
        }
        catch (InvalidDataException)
        {
            if (HeadContainsBareNotify(existing)) throw;
        }
        if (!hasNotify)
        {
            if (HeadContainsBareNotify(existing))
                throw new InvalidDataException("Codex 설정의 notify를 읽지 못했어요");
            updated = PrependNotify(existing, command);
        }
        else if (found.Values.Count > 0 && IsMochinotch(found.Values[0]))
        {
            var rebuilt = new List<string> { exe, "--hook", "--source", "codex" };
            var chainAt = found.Values.IndexOf("--chain");
            if (chainAt >= 0) rebuilt.AddRange(found.Values.Skip(chainAt));
            updated = SameCommand(found.Values, rebuilt) ? existing : ReplaceNotify(existing, found, rebuilt);
        }
        else if (found.Values.Any(IsMochinotch))
        {
            // 다른 도구가 notify를 감싸 인자 안에 우리 명령을 넣어 둔 경우 그대로 둔다.
            updated = existing;
        }
        else
        {
            if (found.Values.Count > 0)
            {
                command.Add("--chain");
                command.Add(JsonSerializer.Serialize(found.Values));
            }
            updated = ReplaceNotify(existing, found, command);
        }
        var changed = cleanedLegacy;
        if (updated != existing)
        {
            Write(path, updated, existing.Length > 0);
            changed = true;
        }
        return changed;
    }

    /// <summary>예전 버전이 <c>.codex/hooks.json</c>의 <c>PermissionRequest</c>에 넣은 우리 훅만 지운다.</summary>
    static bool RemoveLegacyCodexPermissionHooks(string home)
    {
        var path = Path.Combine(home, ".codex", "hooks.json");
        if (!File.Exists(path)) return false;
        var existing = File.ReadAllText(path);
        if (!existing.Contains("mochinotch", StringComparison.OrdinalIgnoreCase)) return false;
        JsonObject? root;
        try
        {
            root = JsonNode.Parse(existing) as JsonObject;
        }
        catch
        {
            return false;
        }
        if (root?["hooks"] is not JsonObject hooks || hooks["PermissionRequest"] is not JsonArray groups)
            return false;
        var removed = false;
        var keptGroups = new JsonArray();
        foreach (var groupNode in groups)
        {
            if (groupNode is JsonObject group && group["hooks"] is JsonArray entries)
            {
                var keptEntries = new JsonArray();
                foreach (var entry in entries)
                {
                    var cmd = entry?["command"] is JsonValue v && v.TryGetValue<string>(out var text) ? text : null;
                    if (IsOurs(cmd, "codex")) removed = true;
                    else keptEntries.Add(entry?.DeepClone());
                }
                if (keptEntries.Count > 0)
                {
                    var clone = (JsonObject)group.DeepClone();
                    clone["hooks"] = keptEntries;
                    keptGroups.Add(clone);
                }
            }
            else
            {
                var cmd = groupNode?["command"] is JsonValue v && v.TryGetValue<string>(out var text) ? text : null;
                if (IsOurs(cmd, "codex")) removed = true;
                else keptGroups.Add(groupNode?.DeepClone());
            }
        }
        if (!removed) return false;
        if (keptGroups.Count == 0) hooks.Remove("PermissionRequest");
        else hooks["PermissionRequest"] = keptGroups;
        var updated = root.ToJsonString(JsonWrite) + "\n";
        if (updated == existing) return false;
        Write(path, updated, backup: true);
        return true;
    }

    static bool SameCommand(IReadOnlyList<string> left, IReadOnlyList<string> right)
        => left.Count == right.Count && left.Zip(right).All(pair => pair.First == pair.Second);

    static string ReplaceNotify(string existing, TomlNotify.Found found, IReadOnlyList<string> command)
    {
        var headEnd = FirstTable(existing) ?? existing.Length;
        if (found.Start < headEnd)
            return string.Concat(existing.AsSpan(0, found.Start), "notify = ", TomlNotify.Format(command), existing.AsSpan(found.End));
        var stripped = string.Concat(existing.AsSpan(0, found.Start), existing.AsSpan(found.End));
        return PrependNotify(stripped, command);
    }

    static string PrependNotify(string existing, IReadOnlyList<string> command)
    {
        var headEnd = FirstTable(existing) ?? existing.Length;
        var prefix = existing[..headEnd];
        if (prefix.Length > 0 && !prefix.EndsWith('\n')) prefix += "\n";
        prefix += "# Mochinotch\nnotify = " + TomlNotify.Format(command) + "\n";
        var tail = existing[headEnd..];
        if (tail.Length > 0 && !prefix.EndsWith('\n')) prefix += "\n";
        return prefix + tail;
    }

    static bool HeadContainsBareNotify(string text)
    {
        var headEnd = FirstTable(text) ?? text.Length;
        return text[..headEnd].Contains("notify", StringComparison.Ordinal);
    }

    static int? FirstTable(string text)
    {
        var index = 0;
        while (index < text.Length)
        {
            var end = text.IndexOf('\n', index);
            if (end < 0) end = text.Length;
            var line = text.AsSpan(index, end - index).TrimStart();
            if (line.Length > 0 && line[0] == '[') return index;
            if (end == text.Length) break;
            index = end + 1;
        }
        return null;
    }

    static bool IsMochinotch(string value)
        => value.Contains("mochinotch", StringComparison.OrdinalIgnoreCase);

    /// <summary>우리 명령을 새 경로로 바꾸고, 없으면 false.</summary>
    static bool Retarget(JsonNode? node, string source, string command)
    {
        var found = false;
        Walk(node, source, command, ref found);
        return found;
    }

    static void Walk(JsonNode? node, string source, string command, ref bool found)
    {
        switch (node)
        {
            case JsonObject obj:
                var pairs = obj.ToList();
                foreach (var pair in pairs)
                {
                    if (pair.Key == "command" && pair.Value is JsonValue value && value.TryGetValue<string>(out var text) && IsOurs(text, source))
                    {
                        found = true;
                        if (text != command) obj["command"] = command;
                    }
                    else
                    {
                        Walk(pair.Value, source, command, ref found);
                    }
                }
                break;
            case JsonArray array:
                foreach (var item in array)
                    Walk(item, source, command, ref found);
                break;
        }
    }

    static bool EventsConnected(string? text, string hooksKey, IReadOnlyList<string> events, string source, string exe)
    {
        if (text == null || JsonNode.Parse(text) is not JsonObject root || root[hooksKey] is not JsonObject hooks)
            return false;
        return events.All(ev => ContainsOurs(hooks[ev], source, exe));
    }

    static bool ContainsOurs(JsonNode? node, string source, string exe)
    {
        switch (node)
        {
            case JsonObject obj:
                foreach (var pair in obj)
                {
                    if (pair.Key == "command" && pair.Value is JsonValue value && value.TryGetValue<string>(out var text) && MatchesOurs(text, source, exe))
                        return true;
                    if (ContainsOurs(pair.Value, source, exe)) return true;
                }
                return false;
            case JsonArray array:
                return array.Any(item => ContainsOurs(item, source, exe));
            default:
                return false;
        }
    }

    static bool MatchesOurs(string? command, string source, string exe)
    {
        if (!IsOurs(command, source)) return false;
        if (string.IsNullOrEmpty(exe)) return true;
        return string.Equals(command, Command(exe, source), StringComparison.OrdinalIgnoreCase);
    }

    public static bool IsOurs(string? command, string source)
        => !string.IsNullOrEmpty(command)
           && command.Contains("--source " + source, StringComparison.Ordinal)
           && command.Contains("mochinotch", StringComparison.OrdinalIgnoreCase)
           && (command.Contains("--hook", StringComparison.Ordinal)
               || command.Contains("mochinotch-notify", StringComparison.Ordinal));

    public static string Command(string exe, string source)
    {
        var quoted = exe.Contains(' ') ? "\"" + exe.Replace("\"", "") + "\"" : exe;
        return $"{quoted} --hook --source {source}";
    }

    static string ConfigFolder(HookTool tool) => tool switch
    {
        HookTool.Claude => ".claude",
        HookTool.Cursor => ".cursor",
        HookTool.Codex => ".codex",
        HookTool.Kiro => ".kiro",
        HookTool.Antigravity => Path.Combine(".gemini", "antigravity"),
        _ => "",
    };

    /// <summary><c>.gemini</c>는 Gemini CLI도 쓰니 Antigravity 폴더만 본다.</summary>
    static IEnumerable<string> PresenceFolders(HookTool tool) => tool == HookTool.Antigravity
        ? [Path.Combine(".gemini", "antigravity"), Path.Combine(".gemini", "antigravity-cli"), Path.Combine(".gemini", "antigravity-ide")]
        : [ConfigFolder(tool)];

    static IEnumerable<string> KnownExecutable(HookTool tool)
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        switch (tool)
        {
            case HookTool.Cursor:
                yield return Path.Combine(local, "Programs", "cursor", "Cursor.exe");
                yield return Path.Combine(local, "Cursor", "Cursor.exe");
                break;
            case HookTool.Claude:
                yield return Path.Combine(local, "AnthropicClaude", "claude.exe");
                yield return Path.Combine(local, "Programs", "Claude", "Claude.exe");
                break;
            case HookTool.Codex:
                yield return Path.Combine(local, "Programs", "OpenAI", "Codex", "Codex.exe");
                break;
            case HookTool.Kiro:
                yield return Path.Combine(local, "Programs", "Kiro", "Kiro.exe");
                break;
            case HookTool.Antigravity:
                yield return Path.Combine(local, "Programs", "Antigravity", "Antigravity.exe");
                break;
        }
    }

    static JsonObject ParseObject(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return new JsonObject();
        if (JsonNode.Parse(text) is not JsonObject obj)
            throw new InvalidDataException("설정 파일을 읽지 못했어요");
        return obj;
    }

    static string? Read(string path) => File.Exists(path) ? File.ReadAllText(path) : null;

    static JsonObject Object(JsonObject parent, string key)
    {
        if (parent[key] is JsonObject obj) return obj;
        if (parent[key] != null) throw new InvalidDataException("설정 파일을 읽지 못했어요");
        obj = new JsonObject();
        parent[key] = obj;
        return obj;
    }

    static JsonArray Array(JsonObject parent, string key)
    {
        if (parent[key] is JsonArray array) return array;
        if (parent[key] != null) throw new InvalidDataException("설정 파일을 읽지 못했어요");
        array = new JsonArray();
        parent[key] = array;
        return array;
    }

    static void Write(string path, string text, bool backup)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        if (backup && File.Exists(path))
            File.Copy(path, path + ".mochinotch.bak", overwrite: true);
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        File.Move(tmp, path, overwrite: true);
    }

    static readonly JsonSerializerOptions JsonWrite = new()
    {
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };
}

/// <summary>Codex <c>config.toml</c>의 <c>notify</c> 문자열 배열만 다룬다.</summary>
static class TomlNotify
{
    public readonly record struct Found(int Start, int End, List<string> Values);

    public static bool TryFind(string text, out Found found)
    {
        found = default;
        var index = 0;
        while (index < text.Length)
        {
            var end = text.IndexOf('\n', index);
            if (end < 0) end = text.Length;
            var lineStart = index;
            var cursor = index;
            while (cursor < end && (text[cursor] == ' ' || text[cursor] == '\t')) cursor++;
            if (text.AsSpan(cursor).StartsWith("notify"))
            {
                cursor += 6;
                while (cursor < text.Length && (text[cursor] == ' ' || text[cursor] == '\t')) cursor++;
                if (cursor < text.Length && text[cursor] == '=')
                {
                    cursor++;
                    while (cursor < text.Length && (text[cursor] == ' ' || text[cursor] == '\t')) cursor++;
                    if (cursor >= text.Length || text[cursor] != '[')
                        throw new InvalidDataException("Codex 설정의 notify를 읽지 못했어요");
                    var (values, after) = ParseArray(text, cursor);
                    found = new Found(lineStart, after, values);
                    return true;
                }
            }
            if (end == text.Length) break;
            index = end + 1;
        }
        return false;
    }

    public static string Format(IReadOnlyList<string> values)
        => "[" + string.Join(", ", values.Select(Basic)) + "]";

    static string Basic(string text)
    {
        var builder = new StringBuilder("\"");
        foreach (var scalar in text)
        {
            switch (scalar)
            {
                case '"': builder.Append("\\\""); break;
                case '\\': builder.Append("\\\\"); break;
                case '\n': builder.Append("\\n"); break;
                case '\t': builder.Append("\\t"); break;
                case '\r': builder.Append("\\r"); break;
                default:
                    if (scalar < 0x20 || scalar == 0x7f) builder.AppendFormat("\\u{0:X4}", (int)scalar);
                    else builder.Append(scalar);
                    break;
            }
        }
        builder.Append('"');
        return builder.ToString();
    }

    static (List<string> Values, int End) ParseArray(string text, int start)
    {
        var values = new List<string>();
        var cursor = start + 1;
        while (cursor < text.Length)
        {
            var character = text[cursor];
            switch (character)
            {
                case ' ' or '\t' or '\n' or '\r' or ',':
                    cursor++;
                    break;
                case '#':
                    var newline = text.IndexOf('\n', cursor);
                    cursor = newline < 0 ? text.Length : newline;
                    break;
                case ']':
                    return (values, cursor + 1);
                case '"' or '\'':
                    if (cursor + 2 < text.Length && text[cursor + 1] == character && text[cursor + 2] == character)
                        throw new InvalidDataException("Codex 설정의 notify를 읽지 못했어요");
                    var (value, next) = ParseString(text, cursor, character == '\'');
                    values.Add(value);
                    cursor = next;
                    break;
                default:
                    throw new InvalidDataException("Codex 설정의 notify를 읽지 못했어요");
            }
        }
        throw new InvalidDataException("Codex 설정의 notify를 읽지 못했어요");
    }

    static (string Value, int End) ParseString(string text, int start, bool literal)
    {
        var quote = literal ? '\'' : '"';
        var cursor = start + 1;
        var value = new StringBuilder();
        while (cursor < text.Length)
        {
            var character = text[cursor];
            if (character == quote) return (value.ToString(), cursor + 1);
            if (character == '\n') break;
            if (!literal && character == '\\')
            {
                cursor++;
                if (cursor >= text.Length) break;
                switch (text[cursor])
                {
                    case '"': value.Append('"'); break;
                    case '\\': value.Append('\\'); break;
                    case 'b': value.Append('\b'); break;
                    case 't': value.Append('\t'); break;
                    case 'n': value.Append('\n'); break;
                    case 'f': value.Append('\f'); break;
                    case 'r': value.Append('\r'); break;
                    case 'u' or 'U':
                        var width = text[cursor] == 'u' ? 4 : 8;
                        if (cursor + 1 + width > text.Length)
                            throw new InvalidDataException("Codex 설정의 notify를 읽지 못했어요");
                        var digits = text.Substring(cursor + 1, width);
                        if (!int.TryParse(digits, System.Globalization.NumberStyles.HexNumber, null, out var code))
                            throw new InvalidDataException("Codex 설정의 notify를 읽지 못했어요");
                        value.Append(char.ConvertFromUtf32(code));
                        cursor += width;
                        break;
                    default:
                        throw new InvalidDataException("Codex 설정의 notify를 읽지 못했어요");
                }
            }
            else
            {
                value.Append(character);
            }
            cursor++;
        }
        throw new InvalidDataException("Codex 설정의 notify를 읽지 못했어요");
    }
}
