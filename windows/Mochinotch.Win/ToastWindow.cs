using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;

namespace Mochinotch.Win;

/// <summary>
/// 스팀에서 친구가 게임을 켤 때처럼, 화면 오른쪽 아래에 카드를 띄운다.
/// 확인 요청은 답이 올 때까지 두고, 완료와 실패는 잠깐 있다 사라진다.
/// </summary>
sealed class ToastWindow : Window
{
    const double CardWidth = 332;
    const double CardHeight = 72;
    const double Gap = 8;
    const double Inset = 14;

    readonly IslandModel model;
    readonly StackPanel stack = new() { Spacing = Gap };
    string drawn = "";

    public ToastWindow(IslandModel model)
    {
        this.model = model;
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
        FontFamily = new FontFamily("Inter, Segoe UI, sans-serif");
        Width = CardWidth;
        Height = CardHeight;
        Content = stack;
        Opened += (_, _) => WindowChrome.Passive(this);
    }

    public void KeepAbove()
    {
        Topmost = false;
        Topmost = true;
    }

    double clock;

    public void Sync(double now)
    {
        clock = now;
        var toasts = model.Toasts(now);
        if (toasts.Count == 0)
        {
            if (IsVisible) Hide();
            drawn = "";
            return;
        }
        var signature = string.Join("|", toasts.Select(note => note.Id));
        if (signature != drawn)
        {
            drawn = signature;
            stack.Children.Clear();
            foreach (var note in toasts.Reverse())
                stack.Children.Add(Card(note));
        }
        var index = 0;
        foreach (var note in toasts.Reverse())
        {
            if (index >= stack.Children.Count) break;
            var card = stack.Children[index];
            var age = Math.Max(0, now - note.Arrived);
            var enter = Ease(Math.Clamp(age / 0.26, 0, 1));
            var leave = note.Until is { } until ? Math.Clamp((until - now) / 0.28, 0, 1) : 1;
            var shown = enter * leave;
            card.Opacity = shown;
            card.RenderTransform = new TranslateTransform((1 - enter) * 28, 0);
            index++;
        }
        Height = toasts.Count * CardHeight + Math.Max(0, toasts.Count - 1) * Gap;
        Width = CardWidth;
        if (!IsVisible)
        {
            Show();
            WindowChrome.Passive(this);
            KeepAbove();
        }
        Place();
    }

    void Place()
    {
        var screen = Screens?.Primary;
        if (screen == null) return;
        var area = screen.WorkingArea;
        var scale = screen.Scaling;
        var x = area.Right - (Width + Inset) * scale;
        var y = area.Bottom - (Height + Inset) * scale;
        Position = new PixelPoint((int)Math.Round(x), (int)Math.Round(y));
    }

    Control Card(AgentNote note)
    {
        var body = note.Detail.Length > 0 ? note.Detail : Copy.Detail(note.Outcome, model.Language);
        var accent = AgentPalette.Outcome(note.Tool, note.Outcome);
        var card = new Border
        {
            Width = CardWidth,
            Height = CardHeight,
            CornerRadius = new CornerRadius(4),
            Background = new SolidColorBrush(Color.FromRgb(23, 29, 37)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            BoxShadow = new BoxShadows(new BoxShadow { Blur = 18, OffsetY = 6, Color = Color.FromArgb(90, 0, 0, 0) }),
            ClipToBounds = true,
            Cursor = new Cursor(StandardCursorType.Hand),
            Child = new Grid
            {
                ColumnDefinitions =
                {
                    new ColumnDefinition(new GridLength(4)),
                    new ColumnDefinition(GridLength.Auto),
                    new ColumnDefinition(GridLength.Star),
                },
                Children =
                {
                    Accent(accent),
                    AgentMark(note),
                    Lines(note, body, accent),
                },
            },
        };
        card.PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(card).Properties.IsLeftButtonPressed) return;
            model.Activate(note, clock);
            eventArgs.Handled = true;
        };
        return card;
    }

    static Border Accent(Rgb color)
    {
        var bar = new Border { Background = Paint.Brush(color) };
        Grid.SetColumn(bar, 0);
        return bar;
    }

    static Control AgentMark(AgentNote note)
    {
        var mark = new Border
        {
            Width = 44,
            Height = 44,
            Margin = new Thickness(12, 0, 10, 0),
            CornerRadius = new CornerRadius(4),
            Background = Paint.Brush(AgentPalette.Icon(note.Tool)),
            VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock
            {
                Text = AgentPalette.Mark(note.Tool),
                Foreground = Brushes.White,
                FontSize = 18,
                FontWeight = FontWeight.Bold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        };
        Grid.SetColumn(mark, 1);
        return mark;
    }

    static StackPanel Lines(AgentNote note, string body, Rgb accent)
    {
        var muted = note.Outcome is AgentOutcome.Completed or AgentOutcome.Cancelled;
        var lines = new StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 14, 0),
            Spacing = 2,
            Children =
            {
                new TextBlock
                {
                    Text = AgentPalette.AppTitle(note.Tool),
                    Foreground = Brushes.White,
                    FontSize = 14,
                    FontWeight = FontWeight.SemiBold,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                },
                new TextBlock
                {
                    Text = body,
                    Foreground = muted ? new SolidColorBrush(Color.FromRgb(143, 152, 160)) : Paint.Brush(accent),
                    FontSize = 13,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                },
            },
        };
        Grid.SetColumn(lines, 2);
        return lines;
    }

    static double Ease(double t) => 1 - Math.Pow(1 - t, 3);
}
