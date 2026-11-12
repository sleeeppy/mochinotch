namespace Mochinotch.Win;

public enum Presentation
{
    Idle,
    Compact,
    Expanded,
}

/// <summary>
/// 노치가 없는 화면의 크기. Windows는 하드웨어 노치가 없으므로 상단 가운데 알약이다.
/// 다른 앱 알림으로 오른쪽을 늘리지 않는다.
/// </summary>
public readonly record struct IslandMetrics(
    double Width,
    double Height,
    double Radius,
    double Shoulder,
    double Shift)
{
    public const double PeekIcon = 26;
    public const double PeekSpacing = 5;
    public const int MaxAgents = 5;

    public static IslandMetrics Resolve(Presentation presentation, int agentSlots, int rows, bool settings)
    {
        const double radius = 10;
        const double shoulder = 6;
        const double expandedShoulder = 16;

        switch (presentation)
        {
            case Presentation.Idle when agentSlots > 0:
                var left = PeekEar(Math.Min(agentSlots, MaxAgents));
                return new IslandMetrics(160 + left, 32, radius, shoulder, -left / 2);
            case Presentation.Idle:
                return new IslandMetrics(160, 32, radius, shoulder, 0);
            case Presentation.Compact:
                return new IslandMetrics(312, 34, radius, shoulder, 0);
            default:
                var header = 58.0;
                var body = settings ? 300 : Math.Max(rows, 1) * 58 + 10;
                var height = Math.Min(520, header + body);
                return new IslandMetrics(418, height, 30, expandedShoulder, 0);
        }
    }

    static double PeekEar(int slots)
    {
        if (slots <= 0) return 0;
        return 6 * 2 + 6 + slots * PeekIcon + (slots - 1) * PeekSpacing;
    }

    public static IslandMetrics Lerp(IslandMetrics from, IslandMetrics to, double t)
    {
        t = Math.Clamp(t, 0, 1);
        return new IslandMetrics(
            from.Width + (to.Width - from.Width) * t,
            from.Height + (to.Height - from.Height) * t,
            from.Radius + (to.Radius - from.Radius) * t,
            from.Shoulder + (to.Shoulder - from.Shoulder) * t,
            from.Shift + (to.Shift - from.Shift) * t);
    }
}
