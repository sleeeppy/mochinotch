using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;

namespace Mochinotch.Win;

/// <summary>맥 IslandView의 키프레임을 그대로 옮긴 표본기.</summary>
static class Motion
{
    /// <summary>(끝 시각, 값) 목록을 부드럽게 잇는다. 첫 값은 0초부터 유지된다.</summary>
    public static double Keys(double t, double start, params (double At, double Value)[] keys)
    {
        var from = start;
        var begin = 0.0;
        foreach (var (at, value) in keys)
        {
            if (t < at)
            {
                var span = at - begin;
                if (span <= 0) return value;
                var k = Math.Clamp((t - begin) / span, 0, 1);
                return from + (value - from) * k * k * (3 - 2 * k);
            }
            from = value;
            begin = at;
        }
        return from;
    }

    public static double Lerp(double a, double b, double t) => a + (b - a) * t;
}

/// <summary>맥과 같은 실제 앱 아이콘. 없으면 색 블록에 머리글자.</summary>
sealed class AppIcon : Control
{
    static readonly Dictionary<AgentTool, Bitmap?> Cache = [];
    AgentTool tool = AgentTool.Custom;
    Bitmap? bitmap;

    public AgentTool Tool
    {
        get => tool;
        set
        {
            tool = value;
            bitmap = Load(value);
            InvalidateVisual();
        }
    }

    public override void Render(DrawingContext context)
    {
        var rect = new Rect(Bounds.Size);
        if (rect.Width < 1) return;
        var radius = rect.Width * 0.24;
        using (context.PushClip(new RoundedRect(rect, radius)))
        {
            if (bitmap != null)
            {
                var size = bitmap.Size;
                var inset = size.Width * 0.098;
                context.DrawImage(bitmap, new Rect(inset, inset, size.Width - inset * 2, size.Height - inset * 2), rect);
                return;
            }
            context.FillRectangle(Paint.Brush(AgentPalette.Icon(tool)), rect);
            var text = new FormattedText(
                AgentPalette.Mark(tool),
                System.Globalization.CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight,
                new Typeface(AppFont.Family, FontStyle.Normal, FontWeight.Bold),
                rect.Width * 0.5,
                Brushes.White);
            context.DrawText(text, new Point((rect.Width - text.Width) / 2, (rect.Height - text.Height) / 2));
        }
    }

    static Bitmap? Load(AgentTool tool)
    {
        if (Cache.TryGetValue(tool, out var cached)) return cached;
        var image = Bundled.Image($"ToolIcons/{AgentPalette.Wire(tool)}.png");
        Cache[tool] = image;
        return image;
    }
}
