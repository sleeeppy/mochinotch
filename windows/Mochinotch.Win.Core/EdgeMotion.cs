namespace Mochinotch.Win;

/// <summary>
/// macOS 가장자리 연출과 같은 시간표.
/// 빛은 위에서 쏟아지고, 2.25초부터 3초에 걸쳐 사라진다.
/// </summary>
public static class EdgeMotion
{
    public const double FallStart = 2.25;
    public const double FallLength = 3;
    public const double Duration = FallStart + FallLength;
    public const double GlowSpan = 6.2;
    public const double PourDuration = 1.35;

    public static double Spring(double t, double response, double damping)
    {
        if (t <= 0) return 0;
        var omega = 2 * Math.PI / response;
        if (damping >= 1)
            return 1 - Math.Exp(-omega * t) * (1 + omega * t);
        var damped = omega * Math.Sqrt(1 - damping * damping);
        var decay = Math.Exp(-damping * omega * t);
        return 1 - decay * (Math.Cos(damped * t) + damping * omega / damped * Math.Sin(damped * t));
    }

    public static double Level(double seconds)
    {
        var rise = SmootherStep(0, 1.74, seconds);
        var fall = 1 - SmootherStep(FallStart, FallStart + FallLength, seconds);
        return rise * fall;
    }

    public static double Swell(double seconds)
    {
        var linear = Math.Clamp(seconds / 1.45, 0, 1);
        return 1 - Math.Pow(1 - linear, 2.2);
    }

    public static double WindowOpacity(double seconds)
    {
        if (seconds >= FallStart) return Level(seconds);
        return SmoothStep(0, 0.12, seconds);
    }

    public static double Strength(double seconds)
        => seconds >= FallStart ? Level(seconds) : Swell(seconds);

    public static (double Progress, double Front) Pour(double seconds)
    {
        var linear = Math.Clamp(seconds / PourDuration, 0, 1);
        var eased = 1 - Math.Pow(1 - linear, 2);
        var front = SmoothStep(0, 0.25, linear) * Math.Pow(1 - linear, 1.3);
        return (eased, front);
    }

    public static double Travel(double seconds) => Math.Clamp(seconds / GlowSpan, 0, 1);

    public static double LineOpacity(double envelope, double travel)
    {
        if (envelope <= 0.001) return 0;
        if (travel < 0.3) return 1;
        return envelope;
    }

    /// <summary>노치 테두리를 따라가는 빛줄기. 0이 왼쪽, 1이 오른쪽.</summary>
    public static (double Tail, double Head) Streak(double travel)
    {
        const double lead = 0.055;
        const double length = 0.16;
        const double finish = 0.5;
        var phase = Math.Clamp((travel - lead) / finish, 0, 1);
        var head = Chew(EasedEnd(phase, 0.74));
        const double settle = 0.9;
        var t = Math.Clamp((head - settle) / (1 - settle), 0, 1);
        var close = t * t * (3 - 2 * t);
        var tail = Math.Max(0, head - length * (1 - close));
        return (Math.Min(tail, head), head);
    }

    public static double SmoothStep(double edge0, double edge1, double x)
    {
        var t = Math.Clamp((x - edge0) / (edge1 - edge0), 0, 1);
        return t * t * (3 - 2 * t);
    }

    public static double SmootherStep(double edge0, double edge1, double x)
    {
        var t = Math.Clamp((x - edge0) / (edge1 - edge0), 0, 1);
        return t * t * t * (t * (t * 6 - 15) + 10);
    }

    static double EasedEnd(double phase, double moveEnd)
    {
        const double endStart = 0.82;
        const double stretch = 1.15;
        var phaseAtEnd = endStart * moveEnd;
        if (phase <= phaseAtEnd) return phase / moveEnd;
        var endDuration = (1 - endStart) * moveEnd * stretch;
        var t = Math.Clamp((phase - phaseAtEnd) / endDuration, 0, 1);
        return endStart + (1 - endStart) * t;
    }

    static double Chew(double linear)
    {
        var smooth = linear * linear * (3 - 2 * linear);
        return smooth * smooth * (3 - 2 * smooth);
    }
}
