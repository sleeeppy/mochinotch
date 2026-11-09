using Avalonia.Media;

namespace Mochinotch.Win;

static class AppFont
{
    public static FontFamily Family { get; } = new("Pretendard, Segoe UI Variable Display, Segoe UI");
}

static class Paint
{
    public static Color Color(Rgb rgb, double alpha = 1)
        => Avalonia.Media.Color.FromArgb(
            (byte)Math.Clamp(alpha * 255, 0, 255),
            (byte)Math.Clamp(rgb.R * 255, 0, 255),
            (byte)Math.Clamp(rgb.G * 255, 0, 255),
            (byte)Math.Clamp(rgb.B * 255, 0, 255));

    public static SolidColorBrush Brush(Rgb rgb, double alpha = 1) => new(Color(rgb, alpha));
}
