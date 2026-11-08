using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;

namespace Mochinotch.Win;

sealed class IslandWindow : Window
{
    const double Pad = 14;
    readonly IslandModel model;
    readonly EdgeWindow edge;
    readonly ToastWindow toast;
    readonly NotchPlate plate = new();
    readonly Panel face = new() { Background = Brushes.Transparent };
    readonly StackPanel peek = new() { Orientation = Orientation.Horizontal, Spacing = 5 };
    readonly Grid compact = new();
    readonly Grid expanded = new();
    readonly List<Border> auras = [];
    readonly Stopwatch clock = Stopwatch.StartNew();
    int drawn = -1;
    bool demoEvent;
    bool demoOpen;
    bool loggedScreen;
    bool loggedEdge;
    readonly bool demo;

    public Action? Quit { get; set; }
    public double Now => clock.Elapsed.TotalSeconds;

    public IslandWindow(IslandModel model, EdgeWindow edge, ToastWindow toast)
    {
        this.model = model;
        this.edge = edge;
        this.toast = toast;
        demo = Environment.GetEnvironmentVariable("MOCHINOTCH_DEMO") == "1";
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
        Width = 188;
        Height = 50;
        Content = new Panel
        {
            Background = Brushes.Transparent,
            Children = { plate, face },
        };
        face.Children.Add(peek);
        face.Children.Add(compact);
        face.Children.Add(expanded);
        PointerEntered += (_, _) => model.SetPointer(true, Now);
        PointerExited += (_, _) => model.SetPointer(false, Now);
        Opened += (_, _) =>
        {
            WindowChrome.Passive(this);
            Place();
            RequestAnimationFrame(OnFrame);
        };
    }

    public void KeepAbove()
    {
        Topmost = false;
        Topmost = true;
    }

    void OnFrame(TimeSpan _)
    {
        try
        {
            var now = Now;
            if (demo && !demoEvent && now > 0.35)
            {
                demoEvent = true;
                model.Ingest(new IncomingEvent { Tool = "cursor", Kind = "completed", Title = "Cursor 작업 완료", Detail = "mochinotch" }, now);
                model.Ingest(new IncomingEvent { Tool = "claude", Kind = "needsInput", Title = "Claude 확인 필요", Detail = "배포할까요?" }, now);
            }
            if (demo && !demoOpen && now > 2.1)
            {
                demoOpen = true;
                model.SetPointer(true, now);
            }
            model.Tick(now);
            LayoutPlate();
            if (drawn != model.Revision)
            {
                drawn = model.Revision;
                Rebuild();
            }
            var breathe = 0.78 + 0.22 * (0.5 + 0.5 * Math.Sin(now * Math.PI * 2 / 2.6));
            foreach (var aura in auras) aura.Opacity = breathe;
            plate.InvalidateVisual();
            edge.Sync(model);
            toast.Sync(now);
            if (demo && model.EdgeVisible && !loggedEdge)
            {
                loggedEdge = true;
                try
                {
                    File.AppendAllText(Path.Combine(Path.GetTempPath(), "mochinotch-win-ui.log"), $"edge {edge.Position} {edge.Width:0}x{edge.Height:0} opacity {edge.Opacity:0.00} visible {edge.IsVisible}\n");
                }
                catch
                {
                    // 미리보기 로그다.
                }
            }
        }
        catch (Exception ex)
        {
            try
            {
                File.AppendAllText(Path.Combine(Path.GetTempPath(), "mochinotch-win-ui.log"), ex + "\n");
            }
            catch
            {
                // 미리보기 로그를 못 써도 다음 프레임은 계속 그린다.
            }
        }
        RequestAnimationFrame(OnFrame);
    }

    void LayoutPlate()
    {
        var shown = model.Shown;
        Width = shown.Width + Pad * 2;
        Height = shown.Height * Math.Max(1, model.StretchY) + 18;
        var rect = new Rect(Pad, 0, shown.Width, shown.Height);
        plate.Plate = rect;
        plate.Shoulder = shown.Shoulder;
        plate.Radius = shown.Radius;
        plate.Glow = model.GlowEnvelope;
        plate.Travel = model.GlowTravel;
        plate.GlowTint = model.GlowColor;
        plate.Failed = model.Featured?.Outcome == AgentOutcome.Failed && model.Presentation != Presentation.Idle;
        plate.Stretch = model.StretchY;
        plate.Shake = model.ShakeX;
        face.Clip = NotchPath.Create(rect, shown.Shoulder, shown.Radius, close: true);
        peek.Margin = new Thickness(rect.X + shown.Shoulder + 6, Math.Max(0, (rect.Height - 26) / 2), 0, 0);
        peek.IsVisible = model.Presentation == Presentation.Idle;
        var inset = shown.Shoulder + (model.Presentation == Presentation.Expanded ? 18 : 0);
        compact.Margin = new Thickness(rect.X + shown.Shoulder, rect.Y, 0, 0);
        compact.Width = Math.Max(0, rect.Width - shown.Shoulder * 2);
        compact.Height = rect.Height;
        compact.IsVisible = model.Presentation == Presentation.Compact;
        expanded.Margin = new Thickness(rect.X + inset, rect.Y + inset, 0, 0);
        expanded.Width = Math.Max(0, rect.Width - inset * 2);
        expanded.Height = Math.Max(0, rect.Height - inset);
        expanded.IsVisible = model.Presentation == Presentation.Expanded;
        Place();
    }

    void Place()
    {
        var screen = Screens?.Primary;
        if (screen == null) return;
        if (demo && !loggedScreen)
        {
            loggedScreen = true;
            try
            {
                File.AppendAllText(Path.Combine(Path.GetTempPath(), "mochinotch-win-ui.log"), $"bounds {screen.Bounds} work {screen.WorkingArea} scale {screen.Scaling}\n");
            }
            catch
            {
                // 화면 기록은 미리보기에서만 쓴다.
            }
        }
        var scale = screen.Scaling;
        var shown = model.Shown;
        var x = screen.Bounds.X + screen.Bounds.Width / 2.0
            + shown.Shift * scale
            - (Pad + shown.Width / 2.0) * scale;
        Position = new PixelPoint((int)Math.Round(x), screen.Bounds.Y);
    }

    void Rebuild()
    {
        auras.Clear();
        peek.Children.Clear();
        foreach (var note in model.LeftIcons().Reverse())
            peek.Children.Add(PeekIcon(note));

        compact.Children.Clear();
        compact.ColumnDefinitions.Clear();
        compact.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        compact.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        if (model.Featured is { } featured)
        {
            var left = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 6,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(16, 0, 0, 0),
                Children =
                {
                    Mark(featured.Tool, 22),
                    new TextBlock
                    {
                        Text = AgentPalette.DisplayName(featured.Tool),
                        Foreground = Brushes.White,
                        FontSize = 13,
                        FontWeight = FontWeight.SemiBold,
                        VerticalAlignment = VerticalAlignment.Center,
                    },
                },
            };
            var outcome = new TextBlock
            {
                Text = Copy.Short(featured.Outcome, model.Language),
                Foreground = Paint.Brush(AgentPalette.Outcome(featured.Tool, featured.Outcome)),
                FontSize = 13,
                FontWeight = FontWeight.SemiBold,
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Right,
                Margin = new Thickness(0, 0, 16, 0),
            };
            Grid.SetColumn(outcome, 1);
            compact.Children.Add(left);
            compact.Children.Add(outcome);
        }

        expanded.Children.Clear();
        expanded.RowDefinitions.Clear();
        if (model.ShowSettings) expanded.Children.Add(Settings());
        else expanded.Children.Add(History());
    }

    Control History()
    {
        var lang = model.Language;
        var root = new Grid { Margin = new Thickness(0, 10, 0, 8) };
        root.RowDefinitions.Add(new RowDefinition(GridLength.Auto));
        root.RowDefinitions.Add(new RowDefinition(GridLength.Auto));
        root.RowDefinitions.Add(new RowDefinition(GridLength.Star));
        var header = new Grid { Margin = new Thickness(18, 0, 12, 8) };
        header.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        header.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Auto));
        header.Children.Add(new TextBlock
        {
            Text = Copy.Get(Phrase.Agents, lang),
            Foreground = Brushes.White,
            FontSize = 13,
            FontWeight = FontWeight.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
        });
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        actions.Children.Add(Link(Copy.Get(Phrase.Settings, lang), () => model.ToggleSettings(Now)));
        actions.Children.Add(Link(Copy.Get(Phrase.Clear, lang), () => model.Clear(Now)));
        Grid.SetColumn(actions, 1);
        header.Children.Add(actions);
        var line = new Border
        {
            Height = 1,
            Margin = new Thickness(16, 0, 16, 6),
            Background = new SolidColorBrush(Color.FromArgb(22, 255, 255, 255)),
        };
        Grid.SetRow(line, 1);
        var list = new StackPanel { Spacing = 2 };
        if (model.Notes.Count == 0)
        {
            list.Children.Add(new TextBlock
            {
                Text = Copy.Get(Phrase.QuietTitle, lang),
                Foreground = Brushes.White,
                FontSize = 13,
                FontWeight = FontWeight.SemiBold,
                Margin = new Thickness(18, 8, 18, 0),
            });
            list.Children.Add(new TextBlock
            {
                Text = Copy.Get(Phrase.QuietBody, lang),
                Foreground = Paint.Brush(Rgb.White, 0.62),
                FontSize = 12,
                Margin = new Thickness(18, 2, 18, 8),
                TextWrapping = TextWrapping.Wrap,
            });
        }
        else
        {
            foreach (var note in model.Notes)
                list.Children.Add(Row(note));
        }
        var scroll = new ScrollViewer
        {
            Content = list,
            Background = Brushes.Transparent,
            HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled,
        };
        Grid.SetRow(scroll, 2);
        root.Children.Add(header);
        root.Children.Add(line);
        root.Children.Add(scroll);
        return root;
    }

    Control Row(AgentNote note)
    {
        var lang = model.Language;
        var title = note.Tool == AgentTool.Custom && note.Title.Length > 0
            ? note.Title
            : AgentPalette.AppTitle(note.Tool);
        var detail = Copy.Detail(note.Outcome, lang);
        if (note.Detail.Length > 0 && note.Outcome != AgentOutcome.Completed)
            detail = detail + " · " + note.Detail;
        else if (note.Outcome == AgentOutcome.Completed && note.Detail.Length > 0)
            detail = note.Detail;
        var grid = new Grid
        {
            Height = 54,
            Margin = new Thickness(8, 0, 8, 0),
            ColumnDefinitions =
            {
                new ColumnDefinition(GridLength.Auto),
                new ColumnDefinition(GridLength.Star),
                new ColumnDefinition(GridLength.Auto),
            },
            Background = Brushes.Transparent,
            Cursor = new Cursor(StandardCursorType.Hand),
        };
        var icon = Mark(note.Tool, 22);
        icon.Margin = new Thickness(8, 0, 8, 0);
        icon.VerticalAlignment = VerticalAlignment.Center;
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock
        {
            Text = title,
            Foreground = Brushes.White,
            FontSize = 13,
            FontWeight = FontWeight.SemiBold,
        });
        text.Children.Add(new TextBlock
        {
            Text = detail,
            Foreground = Paint.Brush(AgentPalette.Outcome(note.Tool, note.Outcome), 0.9),
            FontSize = 12,
            TextTrimming = TextTrimming.CharacterEllipsis,
            MaxWidth = 250,
        });
        Grid.SetColumn(text, 1);
        var when = new TextBlock
        {
            Text = Copy.When(note.Created, lang, DateTime.Now),
            Foreground = Paint.Brush(Rgb.White, 0.45),
            FontSize = 11,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(8, 0, 16, 0),
        };
        Grid.SetColumn(when, 2);
        grid.Children.Add(icon);
        grid.Children.Add(text);
        grid.Children.Add(when);
        grid.PointerEntered += (_, _) => grid.Background = new SolidColorBrush(Color.FromArgb(20, 255, 255, 255));
        grid.PointerExited += (_, _) => grid.Background = Brushes.Transparent;
        grid.PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(grid).Properties.IsLeftButtonPressed) return;
            model.Activate(note, Now);
            eventArgs.Handled = true;
        };
        return grid;
    }

    Control Settings()
    {
        var lang = model.Language;
        var stack = new StackPanel { Margin = new Thickness(18, 16, 18, 12), Spacing = 8 };
        stack.Children.Add(Header(Copy.Get(Phrase.Settings, lang), Copy.Get(Phrase.Close, lang), () => model.CloseSettings(Now)));
        stack.Children.Add(new TextBlock
        {
            Text = Copy.Get(Phrase.Effect, lang),
            Foreground = Brushes.White,
            FontSize = 13,
            FontWeight = FontWeight.SemiBold,
        });
        stack.Children.Add(new TextBlock
        {
            Text = Copy.Get(model.EdgeEnabled ? Phrase.EffectOn : Phrase.EffectOff, lang),
            Foreground = Paint.Brush(Rgb.White, 0.62),
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
        });
        stack.Children.Add(Link(model.EdgeEnabled ? Copy.Get(Phrase.EffectOff, lang) : Copy.Get(Phrase.EffectOn, lang), () => model.ToggleEdge()));
        stack.Children.Add(new TextBlock
        {
            Text = Copy.Get(Phrase.Agents, lang),
            Foreground = Brushes.White,
            FontSize = 13,
            FontWeight = FontWeight.SemiBold,
            Margin = new Thickness(0, 6, 0, 0),
        });
        var present = model.Links.Where(link => link.Present).ToList();
        if (present.Count == 0)
        {
            stack.Children.Add(new TextBlock
            {
                Text = Copy.Get(Phrase.Missing, lang),
                Foreground = Paint.Brush(Rgb.White, 0.62),
                FontSize = 12,
                TextWrapping = TextWrapping.Wrap,
            });
        }
        else
        {
            var connected = present.Where(link => link.Connected).Select(link => AgentPalette.DisplayName(ToolOf(link.Tool))).ToList();
            stack.Children.Add(new TextBlock
            {
                Text = connected.Count == 0
                    ? string.Join(" · ", present.Select(link => AgentPalette.DisplayName(ToolOf(link.Tool))))
                    : Copy.Format(Phrase.Connected, lang, string.Join(", ", connected)),
                Foreground = Paint.Brush(Rgb.White, 0.62),
                FontSize = 12,
                TextWrapping = TextWrapping.Wrap,
            });
        }
        stack.Children.Add(Link(model.Connecting ? Copy.Get(Phrase.Connecting, lang) : Copy.Get(Phrase.Connect, lang), () =>
        {
            if (!model.Connecting) model.Connect(Now);
        }));
        if (model.LinkMessage.Length > 0)
        {
            stack.Children.Add(new TextBlock
            {
                Text = model.LinkMessage,
                Foreground = Paint.Brush(Rgb.White, 0.8),
                FontSize = 12,
                TextWrapping = TextWrapping.Wrap,
            });
        }
        if (LoginStart.Supported)
            stack.Children.Add(Link(Copy.Get(Phrase.Launch, lang) + (model.LaunchAtLogin ? " · ON" : " · OFF"), () => model.ToggleLaunch()));
        stack.Children.Add(Link(Copy.Get(Phrase.Language, lang) + " · " + Copy.Native(model.Language), () => model.CycleLanguage()));
        if (!string.IsNullOrEmpty(model.ServerFailure))
        {
            stack.Children.Add(new TextBlock
            {
                Text = model.ServerFailure,
                Foreground = Paint.Brush(new Rgb(1, 0.271, 0.227)),
                FontSize = 11,
                TextWrapping = TextWrapping.Wrap,
            });
        }
        stack.Children.Add(Link(Copy.Get(Phrase.Quit, lang), () => Quit?.Invoke()));
        return stack;
    }

    static Grid Header(string title, string action, Action click)
    {
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 4) };
        grid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Star));
        grid.ColumnDefinitions.Add(new ColumnDefinition(GridLength.Auto));
        grid.Children.Add(new TextBlock
        {
            Text = title,
            Foreground = Brushes.White,
            FontSize = 13,
            FontWeight = FontWeight.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
        });
        var link = Link(action, click);
        Grid.SetColumn(link, 1);
        grid.Children.Add(link);
        return grid;
    }

    static TextBlock Link(string text, Action click)
    {
        var block = new TextBlock
        {
            Text = text,
            Foreground = Brushes.White,
            FontSize = 12,
            FontWeight = FontWeight.SemiBold,
            Padding = new Thickness(8, 4),
            Cursor = new Cursor(StandardCursorType.Hand),
        };
        block.PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(block).Properties.IsLeftButtonPressed) return;
            click();
            eventArgs.Handled = true;
        };
        return block;
    }

    Control PeekIcon(AgentNote note)
    {
        var aura = new Border
        {
            Width = 24,
            Height = 24,
            CornerRadius = new CornerRadius(6),
            Background = Paint.Brush(AgentPalette.Aura(note.Tool), 0.7),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        auras.Add(aura);
        return new Panel
        {
            Width = 26,
            Height = 26,
            Children = { aura, Mark(note.Tool, 26) },
        };
    }

    static Border Mark(AgentTool tool, double size)
    {
        return new Border
        {
            Width = size,
            Height = size,
            CornerRadius = new CornerRadius(size * 0.24),
            Background = Paint.Brush(AgentPalette.Icon(tool)),
            Child = new TextBlock
            {
                Text = AgentPalette.Mark(tool),
                Foreground = Brushes.White,
                FontSize = size * 0.46,
                FontWeight = FontWeight.Bold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        };
    }

    static AgentTool ToolOf(HookTool tool) => tool switch
    {
        HookTool.Claude => AgentTool.Claude,
        HookTool.Cursor => AgentTool.Cursor,
        HookTool.Codex => AgentTool.Codex,
        HookTool.Kiro => AgentTool.Kiro,
        _ => AgentTool.Custom,
    };
}
