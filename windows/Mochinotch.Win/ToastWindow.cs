using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;

namespace Mochinotch.Win;

/// <summary>
/// 확인과 완료만, 화면 위쪽 끝에서 자라 나오는 검은 판으로 보여 준다.
/// 맥 컴팩트 노치처럼 왼쪽은 앱, 오른쪽은 결과다.
/// </summary>
sealed class ToastWindow : Window
{
    const double FullWidth = 304;
    const double FullHeight = 36;
    const double RestWidth = 136;
    const double Shoulder = 6;
    const double Radius = 11;
    const double LeaveLength = 0.34;
    const double HoverDismiss = 0.2;
    const double ArriveSettle = 1.08;
    const double Room = 10;
    static readonly PixelPoint Offscreen = new(-32000, -32000);

    readonly IslandModel model;
    readonly Func<double> clock;
    readonly PillPlate plate = new();
    readonly Grid face = new();
    readonly AppIcon icon = new();
    readonly StackPanel name = new() { Orientation = Orientation.Horizontal, UseLayoutRounding = false };
    readonly StackPanel status = new() { Orientation = Orientation.Horizontal, UseLayoutRounding = false };
    readonly Canvas host = new();
    readonly ScaleTransform shrink = new(1, 1);
    double ui = 1;
    bool chromeReady;
    AgentNote? shown;
    double shownAt;
    double fromWidth;
    double fromHeight;
    double? leaveAt;
    double width;
    double height;
    bool looping;
    bool parked = true;
    double lastFrame;
    double? hoverSince;

    public ToastWindow(IslandModel model, Func<double> clock)
    {
        this.model = model;
        this.clock = clock;
        SystemDecorations = SystemDecorations.None;
        Background = Brushes.Transparent;
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        ExtendClientAreaToDecorationsHint = true;
        ExtendClientAreaChromeHints = Avalonia.Platform.ExtendClientAreaChromeHints.NoChrome;
        Topmost = true;
        ShowActivated = false;
        ShowInTaskbar = false;
        CanResize = false;
        WindowStartupLocation = WindowStartupLocation.Manual;
        FontFamily = AppFont.Family;
        Width = FullWidth + Room * 2;
        Height = FullHeight * 1.2 + 7;

        icon.Width = 22;
        icon.Height = 22;
        icon.VerticalAlignment = VerticalAlignment.Center;
        icon.RenderTransformOrigin = new RelativePoint(0.5, 1, RelativeUnit.Relative);
        name.VerticalAlignment = VerticalAlignment.Center;
        name.Margin = new Thickness(8, 0, 8, 0);
        name.ClipToBounds = true;
        status.VerticalAlignment = VerticalAlignment.Center;
        face.Height = FullHeight;
        face.Opacity = 0;
        face.Margin = new Thickness(Shoulder + 10, 1, Shoulder + 13, 0);
        face.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Auto));
        face.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        face.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Auto));
        face.Children.Add(icon);
        Grid.SetColumn(name, 1);
        face.Children.Add(name);
        Grid.SetColumn(status, 2);
        face.Children.Add(status);
        face.Width = FullWidth - (Shoulder + 10) - (Shoulder + 13);
        host.RenderTransformOrigin = new RelativePoint(0.5, 0, RelativeUnit.Relative);
        host.RenderTransform = shrink;
        host.Children.Add(plate);
        host.Children.Add(face);
        Canvas.SetLeft(face, Room);
        Canvas.SetTop(face, 0);
        plate.Width = Width;
        plate.Height = Height;
        Content = host;

        PointerEntered += (_, _) => hoverSince ??= clock();
        PointerExited += (_, _) => hoverSince = null;
        PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(this).Properties.IsLeftButtonPressed) return;
            if (shown != null && leaveAt == null) model.Activate(shown, clock());
            eventArgs.Handled = true;
        };
        Opened += (_, _) =>
        {
            WindowChrome.Passive(this);
            EnsureScale();
        };
    }

    public bool Active => shown != null;

    public void KeepAbove()
    {
        Topmost = false;
        Topmost = true;
    }

    /// <summary>앱 타이머가 부른다. 보이는 동안에는 화면 주사에 맞춰 스스로 돈다.</summary>
    public void Wake()
    {
        var now = clock();
        if (looping && now - lastFrame < 0.12) return;
        looping = false;
        if (Frame(now)) Loop();
    }

    void Loop()
    {
        looping = true;
        RequestAnimationFrame(_ =>
        {
            looping = false;
            if (Frame(clock())) Loop();
        });
    }

    bool Frame(double now)
    {
        lastFrame = now;
        EnsureScale();
        var top = model.Toasts(now).FirstOrDefault();
        if (top != null && top.Id != shown?.Id && (leaveAt == null || top.Arrived >= leaveAt.Value || now - leaveAt.Value >= LeaveLength))
        {
            fromWidth = shown != null ? width : RestWidth * ui;
            fromHeight = shown != null ? height : 0;
            shown = top;
            shownAt = now;
            leaveAt = null;
            hoverSince = IsPointerOver ? now : null;
            Bind(top);
        }
        if (shown == null)
        {
            Park();
            return false;
        }
        var ageNow = Math.Max(0, now - shownAt);
        if (leaveAt == null && shown.AlreadyFocused && ageNow >= ArriveSettle)
        {
            model.NoteForeground(shown.Tool, now);
            top = model.Toasts(now).FirstOrDefault();
        }
        else if (leaveAt == null && !shown.AlreadyFocused && IsPointerOver)
        {
            hoverSince ??= now;
            if (now - hoverSince >= HoverDismiss && ageNow >= 0.12)
            {
                model.NoteForeground(shown.Tool, now);
                top = model.Toasts(now).FirstOrDefault();
            }
        }
        else if (!IsPointerOver)
            hoverSince = null;
        if (leaveAt == null && (top == null || top.Id != shown.Id))
            leaveAt = now;
        if (leaveAt == null && shown.Until is { } until && now >= until - LeaveLength)
            leaveAt = until - LeaveLength;
        var leave = leaveAt is { } start ? Math.Clamp((now - start) / LeaveLength, 0, 1) : 0;
        if (leave >= 1 && (top == null || top.Id == shown.Id))
        {
            shown = null;
            leaveAt = null;
            Park();
            return false;
        }

        var age = Math.Max(0, now - shownAt);
        var grownWidth = Motion.Lerp(fromWidth, FullWidth * ui, EdgeMotion.Spring(age, 0.46, 0.72));
        var grownHeight = Motion.Lerp(fromHeight, FullHeight * ui, EdgeMotion.Spring(age, 0.36, 0.8));
        width = grownWidth;
        height = grownHeight;
        var scale = 1 - 0.64 * EdgeMotion.SmootherStep(0, 1, leave);
        shrink.ScaleX = scale;
        shrink.ScaleY = scale;
        var stretch = leave > 0 || shown.Outcome != AgentOutcome.Completed ? 1 : model.StretchY;
        plate.Unit = ui;
        plate.PlateWidth = width;
        plate.PlateHeight = height * stretch;
        var reveal = fromHeight > 0 ? 1 : EdgeMotion.SmoothStep(0, 0.07, age);
        plate.Opacity = reveal * (1 - EdgeMotion.SmoothStep(0.28, 1, leave));
        var glowing = shown.Outcome == AgentOutcome.Completed && model.EdgeVisible;
        plate.Glow = glowing ? model.GlowEnvelope : 0;
        plate.Travel = glowing ? model.GlowTravel : 0;
        plate.GlowTint = model.GlowColor;
        plate.InvalidateVisual();

        face.Opacity = 1 - EdgeMotion.SmoothStep(0, 0.55, leave);
        var left = (Width - width) / 2 - Room * ui;
        face.Clip = PillPath.Create(new Rect(left - face.Margin.Left, -face.Margin.Top, width, height), Shoulder * ui, Radius * ui);
        Animate(age);

        if (parked)
        {
            parked = false;
            Place();
            KeepAbove();
        }
        return true;
    }

    /// <summary>처음 띄울 때의 지연과 테두리 번쩍임을 없애려고 화면 밖에 미리 띄워 둔다.</summary>
    public void Prepare()
    {
        Position = Offscreen;
        Show();
    }

    void Park()
    {
        if (parked) return;
        parked = true;
        plate.PlateWidth = 0;
        plate.InvalidateVisual();
        face.Opacity = 0;
        Position = Offscreen;
    }

    void Bind(AgentNote note)
    {
        icon.Tool = note.Tool;
        Letters(name, AgentPalette.AppTitle(note.Tool), Brushes.White, 13 * ui);
        Letters(status, Copy.Short(note.Outcome, model.Language), Paint.Brush(AgentPalette.Outcome(note.Tool, note.Outcome)), 13 * ui);
    }

    void Animate(double age)
    {
        var squishX = Motion.Keys(age, 0.4, (0.1, 0.4), (0.25, 0.9), (0.35, 1.2), (0.49, 0.95), (0.65, 1));
        var squishY = Motion.Keys(age, 0.4, (0.1, 0.4), (0.25, 1.16), (0.35, 0.8), (0.49, 1.05), (0.65, 1));
        var lift = Motion.Keys(age, -9, (0.1, -9), (0.25, 0));
        icon.Opacity = Motion.Keys(age, 0, (0.1, 0), (0.18, 1));
        icon.RenderTransform = new MatrixTransform(Matrix.CreateScale(squishX, squishY) * Matrix.CreateTranslation(0, lift));

        for (var index = 0; index < name.Children.Count; index++)
        {
            var letter = name.Children[index];
            var spring = EdgeMotion.Spring(age - 0.2 - index * 0.026, 0.36, 0.62);
            letter.Opacity = Math.Clamp(spring * 1.25, 0, 1);
            letter.RenderTransform = new TranslateTransform((1 - spring) * -5, (1 - spring) * 5);
        }

        var breathe = 1.0;
        if (shown?.Outcome == AgentOutcome.NeedsInput && age > 1)
            breathe = 0.7 + 0.3 * (0.5 + 0.5 * Math.Cos((age - 1) * Math.PI * 2 / 2.4));
        for (var index = 0; index < status.Children.Count; index++)
        {
            var letter = status.Children[index];
            var spring = EdgeMotion.Spring(age - 0.34 - index * 0.06, 0.38, 0.48);
            var scale = 0.3 + 0.7 * spring;
            letter.Opacity = Math.Clamp(spring * 1.4, 0, 1) * breathe;
            letter.RenderTransform = new MatrixTransform(
                Matrix.CreateScale(scale, scale)
                * Matrix.CreateRotation(14 * (1 - spring) * Math.PI / 180)
                * Matrix.CreateTranslation(0, 4 * (1 - spring)));
        }
    }

    void EnsureScale()
    {
        var screen = Screens?.Primary;
        if (screen == null || screen.Bounds.Height < 1) return;
        var dip = screen.Bounds.Height / Math.Max(screen.Scaling, 1);
        var next = Math.Clamp(dip / 900, 0.82, 1.7);
        if (chromeReady && Math.Abs(next - ui) < 0.03) return;
        ui = next;
        chromeReady = true;
        var fullW = FullWidth * ui;
        var fullH = FullHeight * ui;
        Width = fullW + Room * 2 * ui;
        Height = fullH * 1.2 + 8 * ui;
        icon.Width = 22 * ui;
        icon.Height = 22 * ui;
        face.Height = fullH;
        face.Margin = new Thickness((Shoulder + 10) * ui, ui, (Shoulder + 13) * ui, 0);
        face.Width = fullW - face.Margin.Left - face.Margin.Right;
        name.Margin = new Thickness(8 * ui, 0, 8 * ui, 0);
        plate.Width = Width;
        plate.Height = Height;
        plate.Unit = ui;
        Canvas.SetLeft(face, Room * ui);
    }

    static void Letters(StackPanel row, string text, IBrush brush, double size)
    {
        row.Children.Clear();
        var parts = System.Globalization.StringInfo.GetTextElementEnumerator(text);
        while (parts.MoveNext())
        {
            var piece = (string)parts.Current;
            if (piece == " ")
            {
                row.Children.Add(new Border { Width = 3.6 * size / 13 });
                continue;
            }
            row.Children.Add(new TextBlock
            {
                Text = piece,
                Foreground = brush,
                FontSize = size,
                FontWeight = FontWeight.SemiBold,
                VerticalAlignment = VerticalAlignment.Center,
                UseLayoutRounding = false,
                Opacity = 0,
            });
        }
    }

    void Place()
    {
        EnsureScale();
        var screen = Screens?.Primary;
        if (screen == null) return;
        var bounds = screen.Bounds;
        var scale = screen.Scaling;
        var x = bounds.X + (bounds.Width - Width * scale) / 2;
        Position = new PixelPoint((int)Math.Round(x), bounds.Y);
    }

    sealed class PillPlate : Control
    {
        public double PlateWidth { get; set; }
        public double PlateHeight { get; set; }
        public double Unit { get; set; } = 1;
        public double Glow { get; set; }
        public double Travel { get; set; }
        public Rgb GlowTint { get; set; } = Rgb.White;

        public override void Render(DrawingContext context)
        {
            if (PlateWidth < 2 || PlateHeight < 1) return;
            var unit = Math.Max(Unit, 0.5);
            var shoulder = Shoulder * unit;
            var radius = Radius * unit;
            var rect = new Rect((Bounds.Width - PlateWidth) / 2, 0, PlateWidth, PlateHeight);
            for (var layer = 3; layer >= 1; layer--)
            {
                var spread = layer * 1.6 * unit;
                var shadow = new Rect(rect.X - spread * 0.6, 0, rect.Width + spread * 1.2, rect.Height + spread);
                context.DrawGeometry(new SolidColorBrush(Color.FromArgb((byte)(34 / layer), 0, 0, 0)), null,
                    PillPath.Create(shadow, shoulder + spread * 0.5, radius + spread));
            }
            context.DrawGeometry(Brushes.Black, null, PillPath.Create(rect, shoulder, radius));
            var opacity = EdgeMotion.LineOpacity(Glow, Travel);
            if (opacity <= 0.02) return;
            var (tail, head) = EdgeMotion.Streak(Travel);
            if (head <= tail + 0.001) return;
            var inner = rect.Deflate(new Thickness(shoulder + radius * 0.6, 0));
            var y = rect.Bottom - 1.2 * unit;
            var x0 = inner.X + inner.Width * tail;
            var x1 = inner.X + inner.Width * head;
            var color = Paint.Color(GlowTint, 0.95 * opacity);
            var soft = Paint.Color(GlowTint, 0.32 * opacity);
            context.DrawRectangle(new SolidColorBrush(soft), null, new Rect(x0, y - 2.2, Math.Max(4, x1 - x0), 4.4), 2.2, 2.2);
            context.DrawLine(new Pen(new SolidColorBrush(color), 1.2) { LineCap = PenLineCap.Round }, new Point(x0, y), new Point(x1, y));
        }
    }
}

static class PillPath
{
    public static StreamGeometry Create(Rect rect, double shoulder, double radius)
    {
        var top = Math.Min(Math.Max(shoulder, 0), Math.Min(rect.Width / 4, rect.Height / 2));
        var body = rect.Width - top * 2;
        var bottom = Math.Min(Math.Max(radius, 0), Math.Min(body / 2, Math.Max(0, rect.Height - top)));
        var left = rect.X + top;
        var right = rect.Right - top;
        var floor = rect.Bottom;
        var geometry = new StreamGeometry();
        using var pen = geometry.Open();
        pen.BeginFigure(new Point(rect.X, rect.Y), true);
        pen.QuadraticBezierTo(new Point(left, rect.Y), new Point(left, rect.Y + top));
        pen.LineTo(new Point(left, floor - bottom));
        pen.QuadraticBezierTo(new Point(left, floor), new Point(left + bottom, floor));
        pen.LineTo(new Point(right - bottom, floor));
        pen.QuadraticBezierTo(new Point(right, floor), new Point(right, floor - bottom));
        pen.LineTo(new Point(right, rect.Y + top));
        pen.QuadraticBezierTo(new Point(right, rect.Y), new Point(rect.Right, rect.Y));
        pen.EndFigure(true);
        return geometry;
    }
}
