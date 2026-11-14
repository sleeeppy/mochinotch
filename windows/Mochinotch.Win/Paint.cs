using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;

namespace Mochinotch.Win;

/// 배포는 exe 하나라서 그림은 exe 안에 넣어 둔다.
static class Bundled
{
    public static Stream? Open(string path)
    {
        var uri = new Uri($"avares://Mochinotch/{path}");
        try
        {
            return AssetLoader.Exists(uri) ? AssetLoader.Open(uri) : null;
        }
        catch (Exception)
        {
            return null;
        }
    }

    public static Bitmap? Image(string path)
    {
        using var stream = Open(path);
        if (stream == null) return null;
        try
        {
            return new Bitmap(stream);
        }
        catch (Exception)
        {
            return null;
        }
    }
}

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
