using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;

namespace Mochinotch.Win;

sealed class NotchPlate : Control
{
    public Rect Plate { get; set; }
    public double Shoulder { get; set; } = 6;
    public double Radius { get; set; } = 10;
    public double Glow { get; set; }
    public double Travel { get; set; }
    public Rgb GlowTint { get; set; } = Rgb.White;
    public bool Failed { get; set; }
    public double Stretch { get; set; } = 1;
    public double Shake { get; set; }

    public override void Render(DrawingContext context)
    {
        var rect = Plate;
        if (rect.Width < 2 || rect.Height < 2) return;
        var stretch = Math.Max(1, Stretch);
        var drawn = new Rect(rect.X, rect.Y, rect.Width, rect.Height * stretch);
        using (context.PushTransform(Matrix.CreateTranslation(Shake, 0)))
        {
            var filled = NotchPath.Create(drawn, Shoulder, Radius, close: true);
            var depth = Math.Clamp((rect.Height - 40) / 140, 0, 1);
            if (depth > 0)
            {
                for (var layer = 3; layer >= 1; layer--)
                {
                    using (context.PushTransform(Matrix.CreateTranslation(0, 2 + layer * 2)))
                    {
                        context.DrawGeometry(
                            new SolidColorBrush(Color.FromArgb((byte)(22 * depth * layer), 0, 0, 0)),
                            null,
                            filled);
                    }
                }
            }
            context.DrawGeometry(Brushes.Black, null, filled);
            DrawStreak(context, drawn);
            if (Failed)
            {
                var open = NotchPath.Create(drawn, Shoulder, Radius, close: false);
                context.DrawGeometry(null, new Pen(Paint.Brush(new Rgb(1, 0.271, 0.227), 0.85), 1.5), open);
            }
        }
    }

    void DrawStreak(DrawingContext context, Rect rect)
    {
        var opacity = EdgeMotion.LineOpacity(Glow, Travel);
        if (opacity <= 0.01) return;
        var (tail, head) = EdgeMotion.Streak(Travel);
        if (head <= tail + 0.0008) return;
        var y = rect.Bottom - 1.2;
        var x0 = rect.X + rect.Width * tail;
        var x1 = rect.X + rect.Width * head;
        var color = Paint.Color(GlowTint, 0.9 * opacity);
        var soft = Paint.Color(GlowTint, 0.45 * opacity);
        context.DrawRectangle(new SolidColorBrush(soft), null, new Rect(x0, y - 3.2, Math.Max(6, x1 - x0), 6.4), 3, 3);
        context.DrawLine(
            new Pen(new SolidColorBrush(color), 1.35) { LineCap = PenLineCap.Round },
            new Point(x0, y),
            new Point(x1, y));
    }
}

static class NotchPath
{
    public static StreamGeometry Create(Rect rect, double shoulder, double radius, bool close)
    {
        var top = Math.Min(Math.Max(shoulder, 0), Math.Min(rect.Width / 4, rect.Height / 2));
        var body = rect.Width - top * 2;
        var bottom = Math.Min(Math.Max(radius, 0), Math.Min(body / 2, Math.Max(0, rect.Height - top)));
        var left = rect.X + top;
        var right = rect.Right - top;
        var floor = rect.Bottom;
        var geometry = new StreamGeometry();
        using var pen = geometry.Open();
        pen.BeginFigure(new Point(rect.X, rect.Y), close);
        pen.QuadraticBezierTo(new Point(left, rect.Y), new Point(left, rect.Y + top));
        pen.LineTo(new Point(left, floor - bottom));
        pen.QuadraticBezierTo(new Point(left, floor), new Point(left + bottom, floor));
        pen.LineTo(new Point(right - bottom, floor));
        pen.QuadraticBezierTo(new Point(right, floor), new Point(right, floor - bottom));
        pen.LineTo(new Point(right, rect.Y + top));
        pen.QuadraticBezierTo(new Point(right, rect.Y), new Point(rect.Right, rect.Y));
        pen.EndFigure(close);
        return geometry;
    }
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
