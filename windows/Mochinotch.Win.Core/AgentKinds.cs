namespace Mochinotch.Win;

public enum AgentTool
{
    Claude,
    Cursor,
    Codex,
    Kiro,
    Custom,
}

public enum AgentOutcome
{
    Completed,
    Failed,
    NeedsInput,
    Cancelled,
}

public readonly record struct Rgb(double R, double G, double B)
{
    public Rgb Lift(double amount) => new(
        R + (1 - R) * amount,
        G + (1 - G) * amount,
        B + (1 - B) * amount);

    public static Rgb White { get; } = new(1, 1, 1);
}

public static class AgentPalette
{
    public static bool PlaysEdge(AgentTool tool) => tool != AgentTool.Custom;

    public static string DisplayName(AgentTool tool) => tool switch
    {
        AgentTool.Claude => "Claude",
        AgentTool.Cursor => "Cursor",
        AgentTool.Codex => "Codex",
        AgentTool.Kiro => "Kiro",
        _ => "작업",
    };

    public static string AppTitle(AgentTool tool) => tool == AgentTool.Claude ? "Claude Code" : DisplayName(tool);

    public static string Mark(AgentTool tool) => tool switch
    {
        AgentTool.Claude => "A",
        AgentTool.Cursor => "C",
        AgentTool.Codex => "O",
        AgentTool.Kiro => "K",
        _ => "•",
    };

    /// <summary>아이콘에 쓰는 색.</summary>
    public static Rgb Icon(AgentTool tool) => tool switch
    {
        AgentTool.Claude => new(0.855, 0.467, 0.341),
        AgentTool.Cursor => new(0.486, 0.361, 0.988),
        AgentTool.Codex => new(0.133, 0.773, 0.369),
        AgentTool.Kiro => new(0.53, 0.30, 0.96),
        _ => new(0.85, 0.85, 0.85),
    };

    /// <summary>왼쪽 오라와 화면 가장자리. Cursor만 은빛이다.</summary>
    public static Rgb Edge(AgentTool tool) => tool switch
    {
        AgentTool.Cursor => new(0.74, 0.78, 0.86),
        AgentTool.Claude => new(0.95, 0.45, 0.27),
        AgentTool.Codex => new(1, 1, 1),
        AgentTool.Kiro => new(0.53, 0.30, 0.96),
        _ => Rgb.White,
    };

    public static Rgb Aura(AgentTool tool) => tool switch
    {
        AgentTool.Cursor => new(0.34, 0.35, 0.37),
        _ => Edge(tool),
    };

    /// <summary>1보다 크면 가장자리 색이 화면 끝에 붙는다.</summary>
    public static double Rim(AgentTool tool, AgentOutcome outcome)
        => outcome == AgentOutcome.Failed || tool != AgentTool.Cursor ? 1 : 2.2;

    public static Rgb Outcome(AgentTool tool, AgentOutcome outcome) => outcome switch
    {
        AgentOutcome.Failed => new(1, 0.271, 0.227),
        AgentOutcome.NeedsInput => new(1, 0.624, 0.039),
        AgentOutcome.Cancelled => new(1, 1, 1),
        AgentOutcome.Completed when tool == AgentTool.Cursor => new(0.73, 0.74, 0.76),
        _ => Icon(tool),
    };

    public static Rgb EdgeTint(AgentTool tool, AgentOutcome outcome)
        => outcome == AgentOutcome.Failed ? new(1, 0.271, 0.227) : Edge(tool);

    public static AgentTool Parse(string? raw) => (raw ?? "").Trim().ToLowerInvariant() switch
    {
        "claude" => AgentTool.Claude,
        "cursor" => AgentTool.Cursor,
        "codex" => AgentTool.Codex,
        "kiro" => AgentTool.Kiro,
        _ => AgentTool.Custom,
    };

    public static string Wire(AgentTool tool) => tool switch
    {
        AgentTool.Claude => "claude",
        AgentTool.Cursor => "cursor",
        AgentTool.Codex => "codex",
        AgentTool.Kiro => "kiro",
        _ => "custom",
    };

    public static AgentOutcome ParseOutcome(string? kind, bool? success)
    {
        switch ((kind ?? "").Trim().ToLowerInvariant())
        {
            case "failed":
            case "failure":
            case "error":
                return AgentOutcome.Failed;
            case "needsinput":
            case "needs_input":
            case "permission":
                return AgentOutcome.NeedsInput;
            case "cancelled":
            case "canceled":
            case "aborted":
                return AgentOutcome.Cancelled;
            default:
                return success == false ? AgentOutcome.Failed : AgentOutcome.Completed;
        }
    }
}
