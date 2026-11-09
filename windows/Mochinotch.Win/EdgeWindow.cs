using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;

namespace Mochinotch.Win;

/// <summary>
/// 화면 가장자리에만 앱 색을 얇게 섞는다. 선으로 테두리를 긋지 않고,
/// 위쪽 가운데에서 쏟아져 모서리를 타고 내려간다.
/// </summary>
sealed class EdgeCanvas : Control
{
    const int ShortSamples = 280;
    const int LongCap = 1100;

    WriteableBitmap? bitmap;
    byte[]? pixels;
    int sampleW;
    int sampleH;

    public double Seconds { get; set; }
    public Rgb Tint { get; set; } = Rgb.White;
    public double Rim { get; set; } = 1;
    public double Fade { get; set; } = 1;

    public override void Render(DrawingContext context)
    {
        var bounds = new Rect(Bounds.Size);
        if (bounds.Width < 2 || bounds.Height < 2) return;
        var strength = EdgeMotion.Strength(Seconds) * Fade;
        var (progress, front) = EdgeMotion.Pour(Seconds);
        if (strength <= 0.001 && front <= 0.001) return;
        Ensure(bounds);
        if (bitmap == null || pixels == null) return;
        PaintFrame(bounds.Width, bounds.Height, strength, progress, front);
        context.DrawImage(bitmap, bounds);
    }

    void Ensure(Rect bounds)
    {
        int width;
        int height;
        if (bounds.Width >= bounds.Height)
        {
            height = ShortSamples;
            width = (int)Math.Clamp(Math.Round(ShortSamples * bounds.Width / bounds.Height), ShortSamples, LongCap);
        }
        else
        {
            width = ShortSamples;
            height = (int)Math.Clamp(Math.Round(ShortSamples * bounds.Height / bounds.Width), ShortSamples, LongCap);
        }
        if (bitmap != null && sampleW == width && sampleH == height) return;
        sampleW = width;
        sampleH = height;
        pixels = new byte[sampleW * sampleH * 4];
        bitmap = new WriteableBitmap(new PixelSize(sampleW, sampleH), new Vector(96, 96), PixelFormat.Bgra8888, AlphaFormat.Premul);
    }

    void PaintFrame(double width, double height, double strength, double progress, double front)
    {
        var buffer = pixels!;
        Array.Clear(buffer);
        var frameShape = EdgeFrame.Measure(width, height);
        var lift = Tint.Lift(0.48);
        var power = Rim > 1.2 ? 1.35 : 1;
        const double soft = 0.24;
        const double headBand = 0.07;
        var reach = progress * (1 + soft);
        for (var y = 0; y < sampleH; y++)
        {
            var sy = (y + 0.5) / sampleH * height;
            for (var x = 0; x < sampleW; x++)
            {
                var sx = (x + 0.5) / sampleW * width;
                var fade = EdgeFade(sx, sy, width, height, frameShape);
                if (fade < 0.015) continue;
                var edge = Math.Pow(fade, power);
                var span = EdgeFrame.Span(sx, sy, width, height);
                var reveal = progress >= 0.999 ? 1 : 1 - EdgeMotion.SmoothStep(Math.Max(0, reach - soft), reach, span);
                if (reveal <= 0.001) continue;
                var outer = 1 - EdgeMotion.SmoothStep(Math.Max(0, reach - headBand), reach, span);
                var inner = 1 - EdgeMotion.SmoothStep(Math.Max(0, reach - headBand * 4.2), Math.Max(0, reach - headBand), span);
                var head = Math.Max(0, inner - outer) * front;
                var wash = edge * reveal * strength * 0.62;
                var light = edge * head * Fade * 0.95;
                var alpha = Math.Min(1, wash + light);
                if (alpha < 0.004) continue;
                var index = (y * sampleW + x) * 4;
                buffer[index] = Channel(Tint.B * wash + lift.B * light);
                buffer[index + 1] = Channel(Tint.G * wash + lift.G * light);
                buffer[index + 2] = Channel(Tint.R * wash + lift.R * light);
                buffer[index + 3] = Channel(alpha);
            }
        }
        using var locked = bitmap!.Lock();
        Marshal.Copy(buffer, 0, locked.Address, buffer.Length);
    }

    /// <summary>가로 두께와 세로 두께가 다른 가장자리. 1이면 테두리, 0이면 화면 안쪽이다.</summary>
    static double EdgeFade(double x, double y, double width, double height, EdgeFrame frame)
    {
        var sx = (x - width / 2) / frame.BandX;
        var sy = (y - height / 2) / frame.BandY;
        var radius = Math.Min(frame.Corner / frame.BandX, frame.Corner / frame.BandY);
        var inside = Inside(sx, sy, (width / 2) / frame.BandX, (height / 2) / frame.BandY, radius);
        if (inside <= 0) return 0;
        return 1 - EdgeMotion.SmootherStep(0, 1, inside);
    }

    /// <summary>둥근 화면 안쪽까지의 거리. 가장자리가 0이고, 밖은 음수다.</summary>
    static double Inside(double x, double y, double halfWidth, double halfHeight, double radius)
    {
        var qx = Math.Abs(x) - halfWidth + radius;
        var qy = Math.Abs(y) - halfHeight + radius;
        var outside = Math.Sqrt(Math.Max(qx, 0) * Math.Max(qx, 0) + Math.Max(qy, 0) * Math.Max(qy, 0));
        var inside = Math.Min(Math.Max(qx, qy), 0);
        return -(outside + inside - radius);
    }

    static byte Channel(double value) => (byte)Math.Clamp(value * 255, 0, 255);
}

sealed class EdgeWindow : Window
{
    readonly EdgeCanvas canvas = new() { IsHitTestVisible = false };

    public Action? Raised { get; set; }

    public EdgeWindow()
    {
        SystemDecorations = SystemDecorations.None;
        Background = Brushes.Transparent;
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        ExtendClientAreaToDecorationsHint = true;
        ExtendClientAreaChromeHints = Avalonia.Platform.ExtendClientAreaChromeHints.NoChrome;
        Topmost = true;
        ShowActivated = false;
        ShowInTaskbar = false;
        CanResize = false;
        IsHitTestVisible = false;
        Content = canvas;
        Opened += (_, _) => WindowChrome.ClickThrough(this);
    }

    public void Sync(IslandModel model)
    {
        if (!model.EdgeVisible)
        {
            if (IsVisible) Hide();
            return;
        }
        if (!IsVisible)
        {
            Show();
            WindowChrome.ClickThrough(this);
            Topmost = true;
            Raised?.Invoke();
        }
        Fit();
        canvas.Width = Width;
        canvas.Height = Height;
        canvas.Seconds = model.EdgeSeconds;
        canvas.Tint = model.EdgeTint;
        canvas.Rim = model.EdgeRim;
        canvas.Fade = Math.Clamp(model.EdgeWindowOpacity, 0, 1);
        canvas.InvalidateVisual();
    }

    void Fit()
    {
        var screen = Screens?.Primary;
        if (screen == null) return;
        var bounds = OperatingSystem.IsMacOS() ? screen.WorkingArea : screen.Bounds;
        Position = bounds.Position;
        Width = Math.Max(1, bounds.Width / screen.Scaling);
        Height = Math.Max(1, bounds.Height / screen.Scaling);
    }
}
