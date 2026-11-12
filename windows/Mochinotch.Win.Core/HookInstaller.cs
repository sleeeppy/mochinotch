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
}

public sealed record ToolLink(HookTool Tool, bool Present, bool Connected);

public sealed class InstallResult
{
    public List<HookTool> Changed { get; } = [];
    public List<HookTool> Connected { get; } = [];
    public List<(HookTool Tool, string Problem)> Failures { get; } = [];
}

/// <summary>
/// Cursor, Claude, Codex, Kiro의 hook만 넣는다. Windows 알림은 읽지 않는다.
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

    public static bool IsPresent(string home, HookTool tool)
    {
        var folder = Path.Combine(home, ConfigFolder(tool));
        if (Directory.Exists(folder)) return true;
        return KnownExecutable(tool).Any(File.Exists);
    }

    public static bool IsConnected(string home, HookTool tool, string exe)
    {
        _ = exe;
        try
        {
            return tool switch
            {
                HookTool.Claude => EventsConnected(Read(Path.Combine(home, ".claude", "settings.json")), "hooks", ClaudeEvents, "claude"),
                HookTool.Cursor => EventsConnected(Read(Path.Combine(home, ".cursor", "hooks.json")), "hooks", CursorEvents, "cursor"),
                HookTool.Kiro => KiroConnected(Read(Path.Combine(home, ".kiro", "hooks", "mochinotch.json"))),
                HookTool.Codex => CodexConnected(home),
                _ => false,
            };
        }
        catch
        {
            return false;
        }
    }

    static bool CodexConnected(string home)
    {
        var config = File.Exists(Path.Combine(home, ".codex", "config.toml"))
            ? File.ReadAllText(Path.Combine(home, ".codex", "config.toml"))
            : "";
        if (!config.Contains("mochinotch", StringComparison.OrdinalIgnoreCase)
            && !config.Contains("--hook", StringComparison.Ordinal)
            && !config.Contains("Mochinotch", StringComparison.Ordinal))
            return false;
        return EventsConnected(Read(Path.Combine(home, ".codex", "hooks.json")), "hooks", ["PermissionRequest"], "codex");
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
            _ => false,
        };
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
            if (hook?["enabled"]?.GetValue<bool>() == false
                && IsOurs(hook["action"]?["command"]?.GetValue<string>(), "kiro"))
                return true;
        }
        return false;
    }

    static bool KiroConnected(string? text)
    {
        if (text == null || JsonNode.Parse(text) is not JsonObject root || root["hooks"] is not JsonArray hooks)
            return false;
        foreach (var hook in hooks)
        {
            if (hook?["enabled"]?.GetValue<bool>() == false) continue;
            if (hook?["trigger"]?.GetValue<string>() == "Stop" && IsOurs(hook["action"]?["command"]?.GetValue<string>(), "kiro"))
                return true;
        }
        return false;
    }

    static bool MergeCodex(string home, string exe)
    {
        var path = Path.Combine(home, ".codex", "config.toml");
        var existing = File.Exists(path) ? File.ReadAllText(path) : "";
        var command = new List<string> { exe, "--hook", "--source", "codex" };
        string updated;
        if (!TomlNotify.TryFind(existing, out var found))
        {
            if (HeadContainsBareNotify(existing))
                throw new InvalidDataException("Codex 설정의 notify를 읽지 못했어요");
            updated = PrependNotify(existing, command);
        }
        else if (found.Values.Any(IsMochinotch))
        {
            var rebuilt = new List<string> { exe, "--hook", "--source", "codex" };
            var chainAt = found.Values.IndexOf("--chain");
            if (chainAt >= 0) rebuilt.AddRange(found.Values.Skip(chainAt));
            updated = SameCommand(found.Values, rebuilt) ? existing : ReplaceNotify(existing, found, rebuilt);
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
        var changed = false;
        if (updated != existing)
        {
            Write(path, updated, existing.Length > 0);
            changed = true;
        }
        if (MergeJson(Path.Combine(home, ".codex", "hooks.json"), root =>
        {
            var hooks = Object(root, "hooks");
            var list = Array(hooks, "PermissionRequest");
            if (!Retarget(list, "codex", Command(exe, "codex")))
            {
                list.Add(new JsonObject
                {
                    ["hooks"] = new JsonArray(new JsonObject
                    {
                        ["type"] = "command",
                        ["command"] = Command(exe, "codex"),
                    }),
                });
            }
        })) changed = true;
        return changed;
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
        => value.Contains("mochinotch", StringComparison.OrdinalIgnoreCase)
           || value.Contains("Mochinotch", StringComparison.Ordinal)
           || value.Contains("--hook", StringComparison.Ordinal);

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

    static bool EventsConnected(string? text, string hooksKey, IReadOnlyList<string> events, string source)
    {
        if (text == null || JsonNode.Parse(text) is not JsonObject root || root[hooksKey] is not JsonObject hooks)
            return false;
        return events.All(ev => ContainsOurs(hooks[ev], source));
    }

    static bool ContainsOurs(JsonNode? node, string source)
    {
        switch (node)
        {
            case JsonObject obj:
                foreach (var pair in obj)
                {
                    if (pair.Key == "command" && pair.Value is JsonValue value && value.TryGetValue<string>(out var text) && IsOurs(text, source))
                        return true;
                    if (ContainsOurs(pair.Value, source)) return true;
                }
                return false;
            case JsonArray array:
                return array.Any(item => ContainsOurs(item, source));
            default:
                return false;
        }
    }

    public static bool IsOurs(string? command, string source)
        => !string.IsNullOrEmpty(command)
           && command.Contains("--source " + source, StringComparison.Ordinal)
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
        _ => "",
    };

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
