namespace Mochinotch.Win;

/// <summary>
/// Cursor는 질문 카드를 띄울 때 hook을 부르지 않고 <c>Input needed</c> 알림을 보낸다.
/// 그 알림만 확인 요청으로 받는다. 완료 알림은 hook이 이미 보낸다.
/// </summary>
public static class AgentNotices
{
    public static IncomingEvent? Interpret(string? appId, string? title, string? body)
    {
        var tool = Tool(appId);
        if (tool == null) return null;
        var headline = (title ?? "").Trim();
        var text = (body ?? "").Trim();
        if (headline.StartsWith("Input needed", StringComparison.OrdinalIgnoreCase))
        {
            var question = Question(headline);
            if (question.Length == 0) question = text;
            return new IncomingEvent
            {
                Tool = tool,
                Kind = "needsInput",
                Title = Title(tool),
                Detail = question,
            };
        }
        if ($"{headline}\n{text}".Contains("permission required", StringComparison.OrdinalIgnoreCase))
        {
            return new IncomingEvent
            {
                Tool = tool,
                Kind = "needsInput",
                Title = Title(tool),
                Detail = text.Length > 0 ? text : headline,
            };
        }
        return null;
    }

    public static string? Tool(string? appId)
    {
        var id = appId ?? "";
        if (id.Contains("cursor", StringComparison.OrdinalIgnoreCase)) return "cursor";
        if (id.Contains("claude", StringComparison.OrdinalIgnoreCase)) return "claude";
        if (id.Contains("codex", StringComparison.OrdinalIgnoreCase)) return "codex";
        if (id.Contains("kiro", StringComparison.OrdinalIgnoreCase)) return "kiro";
        return null;
    }

    static string Question(string headline)
    {
        var split = headline.Split(['•', '·'], 2);
        if (split.Length < 2) return "";
        var question = split[1].Trim();
        if (question.Length >= 2 && question[0] == '"' && question[^1] == '"')
            question = question[1..^1].Trim();
        return question;
    }

    static string Title(string tool) => tool switch
    {
        "claude" => "Claude 확인 필요",
        "cursor" => "Cursor 확인 필요",
        "codex" => "Codex 확인 필요",
        "kiro" => "Kiro 확인 필요",
        _ => "확인 필요",
    };
}
