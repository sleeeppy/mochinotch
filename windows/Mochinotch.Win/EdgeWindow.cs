using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;

namespace Mochinotch.Win;

/// <summary>
/// 화면 가장자리를 따라 에이전트 색이 쏟아진다.
/// 가운데는 비워 두어 뒤의 화면이 그대로 보인다.
/// </summary>
sealed class EdgeCanvas : Control
{
    public double Seconds { get; set; }
    public Rgb Tint { get; set; } = Rgb.White;
    public double Rim { get; set; } = 1;

    public override void Render(DrawingContext context)
    {
        var bounds = new Rect(Bounds.Size);
        if (bounds.Width < 2 || bounds.Height < 2) return;
        var (progress, front) = EdgeMotion.Pour(Seconds);
        var strength = EdgeMotion.Strength(Seconds) * Fade;
        if (strength <= 0.001 && progress <= 0.001) return;
        var reach = Math.Sqrt(bounds.Width * bounds.Width / 4 + bounds.Height * bounds.Height) * 1.05 * progress;
        Wash(context, bounds, reach, strength, 1);
        if (front > 0.02)
            Wash(context, bounds, reach, front * Fade, 0.55);
    }

    public double Fade { get; set; } = 1;

    /// <summary>위에서 쏟아진 거리까지만 가장자리를 칠한다. 가운데는 비운다.</summary>
    void Wash(DrawingContext context, Rect bounds, double reach, double amount, double scale)
    {
        if (reach <= 1 || amount <= 0.001) return;
        var thick = (Rim > 1.2 ? 28.0 : 56) * scale;
        var alpha = 0.5 * amount;
        var topHalf = Math.Min(bounds.Width / 2, reach);
        Fill(context, new Rect(bounds.Width / 2 - topHalf, 0, topHalf * 2, thick), alpha, fadeDown: true);
        var side = Math.Sqrt(Math.Max(0, reach * reach - bounds.Width * bounds.Width / 4));
        if (side > 1)
        {
            var height = Math.Min(bounds.Height, side);
            Fill(context, new Rect(0, 0, thick, height), alpha, fadeRight: true);
            Fill(context, new Rect(bounds.Width - thick, 0, thick, height), alpha, fadeLeft: true);
        }
        if (reach > bounds.Height)
        {
            var half = Math.Min(bounds.Width / 2, Math.Sqrt(Math.Max(0, reach * reach - bounds.Height * bounds.Height)));
            Fill(context, new Rect(bounds.Width / 2 - half, bounds.Height - thick, half * 2, thick), alpha, fadeUp: true);
        }
    }

    void Fill(DrawingContext context, Rect rect, double alpha, bool fadeRight = false, bool fadeLeft = false, bool fadeDown = false, bool fadeUp = false)
    {
        if (rect.Width < 1 || rect.Height < 1) return;
        var brush = new LinearGradientBrush
        {
            StartPoint = new RelativePoint(fadeLeft ? 1 : 0, fadeUp ? 1 : 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(fadeRight || fadeLeft ? (fadeLeft ? 0 : 1) : 0.5, fadeDown || fadeUp ? (fadeUp ? 0 : 1) : 0.5, RelativeUnit.Relative),
        };
        brush.GradientStops.Add(new GradientStop(Paint.Color(Tint, alpha), 0));
        brush.GradientStops.Add(new GradientStop(Paint.Color(Tint, 0), 1));
        context.FillRectangle(brush, rect);
    }
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
