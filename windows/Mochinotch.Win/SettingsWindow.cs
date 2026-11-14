using Avalonia;
using Avalonia.Animation;
using Avalonia.Animation.Easings;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Threading;

namespace Mochinotch.Win;

/// <summary>트레이 아이콘 위에 뜨는 작은 설정 팝오버. 바깥을 누르면 닫힌다.</summary>
sealed class SettingsWindow : Window
{
    const double Gap = 14;
    static readonly Rgb Green = new(0.204, 0.780, 0.349);
    static readonly Rgb Danger = new(1, 0.271, 0.227);

    readonly IslandModel model;
    readonly Border card;
    readonly TranslateTransform slide = new();
    readonly TextBlock hint = Secondary(12);
    readonly TextBlock effectTitle = Primary();
    readonly TextBlock effectDetail = Secondary(11.5);
    readonly MiniSwitch effectSwitch = new();
    readonly TextBlock launchTitle = Primary();
    readonly MiniSwitch launchSwitch = new();
    readonly TextBlock languageTitle = Primary();
    readonly TextBlock languageValue = Secondary(13);
    readonly TextBlock languageChevron = new() { Text = "▾", FontSize = 11, Foreground = Paint.Brush(Rgb.White, 0.4), VerticalAlignment = VerticalAlignment.Center };
    readonly StackPanel languageMenu = new() { Margin = new Thickness(8, 0, 8, 8), Spacing = 2, Opacity = 0 };
    readonly Border languageClip = new() { ClipToBounds = true, Height = 0 };
    readonly TranslateTransform languageShift = new(0, -8);
    readonly Dictionary<Lang, Border> languageItems = [];
    readonly StackPanel body = new() { Spacing = 12 };
    readonly TextBlock updateLabel = new() { FontSize = 11, VerticalAlignment = VerticalAlignment.Center };
    readonly TextBlock updateIcon;
    readonly RotateTransform updateSpin = new();
    readonly DispatcherTimer updateSpinTimer;
    readonly Border updateFill;
    readonly Border updateChip;
    bool updateHovered;
    double updateWidth;
    static readonly Rgb UpdateOrange = new(1, 0.52, 0.22);
    Lang? paintedLanguage;
    readonly TextBlock agentsLabel = Caption();
    readonly TextBlock agentsStatus = Primary();
    readonly TextBlock connectText = new() { FontSize = 12, FontWeight = FontWeight.SemiBold, Foreground = Brushes.White };
    readonly TextBlock linkMessage = Secondary(11.5);
    readonly TextBlock failure = new() { FontSize = 11.5, TextWrapping = TextWrapping.Wrap, Foreground = Paint.Brush(Danger) };
    readonly TextBlock quitText = new() { FontSize = 12, FontWeight = FontWeight.SemiBold, Foreground = Paint.Brush(Rgb.White, 0.62) };
    int drawn = -1;
    long hiddenAt;
    bool fromTop;

    public Action? Quit { get; set; }
    public Action? LanguageChanged { get; set; }
    public AppUpdate? Updates { get; set; }

    public SettingsWindow(IslandModel model)
    {
        this.model = model;
        updateIcon = new TextBlock
        {
            FontSize = 11,
            FontFamily = new FontFamily("Segoe UI Symbol, Segoe UI"),
            VerticalAlignment = VerticalAlignment.Center,
            RenderTransform = updateSpin,
            RenderTransformOrigin = new RelativePoint(0.5, 0.5, RelativeUnit.Relative),
        };
        updateSpinTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(32) };
        updateSpinTimer.Tick += (_, _) => updateSpin.Angle = (updateSpin.Angle + 24) % 360;
        updateFill = new Border { HorizontalAlignment = HorizontalAlignment.Left, IsVisible = false };
        updateChip = new Border
        {
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            CornerRadius = new CornerRadius(11),
            ClipToBounds = true,
            Cursor = new Cursor(StandardCursorType.Hand),
            Child = new Panel
            {
                Children =
                {
                    updateFill,
                    new StackPanel
                    {
                        Orientation = Orientation.Horizontal,
                        Spacing = 4,
                        Margin = new Thickness(9, 3.5, 8, 3.5),
                        Children = { updateLabel, updateIcon },
                    },
                },
            },
        };
        updateChip.SizeChanged += (_, eventArgs) =>
        {
            updateWidth = eventArgs.NewSize.Width;
            LayoutFill();
        };
        updateChip.PointerEntered += (_, _) =>
        {
            updateHovered = true;
            ShowUpdate();
        };
        updateChip.PointerExited += (_, _) =>
        {
            updateHovered = false;
            ShowUpdate();
        };
        updateChip.PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(updateChip).Properties.IsLeftButtonPressed) return;
            eventArgs.Handled = true;
            PressUpdate();
        };
        Title = "Mochinotch";
        Width = 340 + Gap * 2;
        SizeToContent = SizeToContent.Height;
        CanResize = false;
        Topmost = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        SystemDecorations = SystemDecorations.None;
        Background = Brushes.Transparent;
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        ExtendClientAreaToDecorationsHint = true;
        ExtendClientAreaChromeHints = Avalonia.Platform.ExtendClientAreaChromeHints.NoChrome;
        FontFamily = AppFont.Family;
        ShowInTaskbar = false;

        body.Children.Add(Header());
        body.Children.Add(Group(
            Row(Stack(effectTitle, effectDetail), effectSwitch, () => model.ToggleEdge()),
            LoginStart.Supported ? Row(launchTitle, launchSwitch, () => model.ToggleLaunch()) : null,
            LanguageBlock()));
        body.Children.Add(agentsLabel);
        var connect = Capsule(connectText, Paint.Color(Rgb.White, 0.12), Paint.Color(Rgb.White, 0.2), () =>
        {
            if (!model.Connecting) model.Connect(0);
        });
        connect.VerticalAlignment = VerticalAlignment.Center;
        var agents = new Grid { ColumnDefinitions = { new ColumnDefinition(GridLength.Star), new ColumnDefinition(GridLength.Auto) } };
        agentsStatus.TextWrapping = TextWrapping.Wrap;
        agentsStatus.Margin = new Thickness(0, 0, 10, 0);
        agentsStatus.VerticalAlignment = VerticalAlignment.Center;
        agents.Children.Add(agentsStatus);
        Grid.SetColumn(connect, 1);
        agents.Children.Add(connect);
        agentsLabel.Margin = new Thickness(4, 2, 0, -6);
        body.Children.Add(Group(Pad(agents)));
        linkMessage.Margin = new Thickness(4, -4, 4, 0);
        failure.Margin = new Thickness(4, -4, 4, 0);
        body.Children.Add(linkMessage);
        body.Children.Add(failure);
        body.Children.Add(Footer());
        body.Transitions = [new DoubleTransition { Property = OpacityProperty, Duration = TimeSpan.FromSeconds(0.22), Easing = new CubicEaseOut() }];

        card = new Border
        {
            Margin = new Thickness(Gap),
            Padding = new Thickness(14, 14, 14, 10),
            CornerRadius = new CornerRadius(16),
            Background = Paint.Brush(new Rgb(0.075, 0.075, 0.082)),
            BorderBrush = Paint.Brush(Rgb.White, 0.1),
            BorderThickness = new Thickness(1),
            BoxShadow = new BoxShadows(new BoxShadow { Blur = 26, OffsetY = 8, Color = Color.FromArgb(110, 0, 0, 0) }),
            Child = body,
            RenderTransform = slide,
            Opacity = 0,
        };
        Content = card;

        Opened += (_, _) => WindowChrome.Bare(this);
        LayoutUpdated += (_, _) =>
        {
            if (IsVisible) Place();
        };
        Deactivated += (_, _) => Dismiss();
        KeyDown += (_, eventArgs) =>
        {
            if (eventArgs.Key == Key.Escape) Dismiss();
        };
        Closing += (_, eventArgs) =>
        {
            if (eventArgs.IsProgrammatic) return;
            eventArgs.Cancel = true;
            Dismiss();
        };
    }

    public void Toggle()
    {
        if (IsVisible)
        {
            Dismiss();
            return;
        }
        if (Environment.TickCount64 - hiddenAt < 350) return;
        Open();
    }

    public void Open()
    {
        drawn = -1;
        Updates?.Check();
        Sync();
        if (IsVisible)
        {
            Activate();
            return;
        }
        card.Transitions = null;
        card.Opacity = 0;
        slide.Transitions = null;
        Show();
        Activate();
        Dispatcher.UIThread.Post(() =>
        {
            Place();
            slide.Y = fromTop ? -10 : 10;
            var ease = new CubicEaseOut();
            card.Transitions = [new DoubleTransition { Property = OpacityProperty, Duration = TimeSpan.FromSeconds(0.18), Easing = ease }];
            slide.Transitions = [new DoubleTransition { Property = TranslateTransform.YProperty, Duration = TimeSpan.FromSeconds(0.32), Easing = new BackEaseOut() }];
            card.Opacity = 1;
            slide.Y = 0;
        }, DispatcherPriority.Loaded);
    }

    public void Sync()
    {
        if (!IsVisible && drawn >= 0) return;
        if (drawn == model.Revision) return;
        drawn = model.Revision;
        var lang = model.Language;
        hint.Text = Copy.Get(Phrase.OverlayHint, lang);
        effectTitle.Text = Copy.Get(Phrase.Effect, lang);
        effectDetail.Text = Copy.Get(model.EdgeEnabled ? Phrase.EffectOn : Phrase.EffectOff, lang);
        effectSwitch.IsOn = model.EdgeEnabled;
        launchTitle.Text = Copy.Get(Phrase.Launch, lang);
        launchSwitch.IsOn = model.LaunchAtLogin;
        languageTitle.Text = Copy.Get(Phrase.Language, lang);
        languageValue.Text = Copy.Native(lang);
        foreach (var (itemLang, item) in languageItems)
            item.Background = itemLang == lang ? Paint.Brush(Rgb.White, 0.1) : Brushes.Transparent;
        agentsLabel.Text = Copy.Get(Phrase.Agents, lang);
        agentsStatus.Text = AgentStatus(lang);
        connectText.Text = Copy.Get(model.Connecting ? Phrase.Connecting : Phrase.Connect, lang);
        linkMessage.Text = model.LinkMessage;
        linkMessage.IsVisible = model.LinkMessage.Length > 0;
        failure.Text = model.ServerFailure ?? "";
        failure.IsVisible = !string.IsNullOrEmpty(model.ServerFailure);
        quitText.Text = Copy.Get(Phrase.Quit, lang);
        if (paintedLanguage is { } previous && previous != lang && IsVisible)
            FadeBody();
        paintedLanguage = lang;
        ShowUpdate();
    }

    public void ShowUpdate()
    {
        var offer = Updates?.Offer;
        var busy = Updates?.Busy == true;
        var status = Updates?.Status;
        var installing = busy || offer != null;
        updateLabel.Text = UpdateLabel(installing, busy, offer, status);
        updateLabel.FontWeight = installing ? FontWeight.SemiBold : FontWeight.Medium;
        if (installing)
        {
            updateIcon.IsVisible = false;
            updateLabel.Foreground = Paint.Brush(UpdateOrange);
            updateChip.Background = Paint.Brush(UpdateOrange, busy ? 0.16 : updateHovered ? 0.28 : 0.16);
            updateChip.BorderThickness = new Thickness(0);
            updateFill.Background = Paint.Brush(UpdateOrange, 0.3);
        }
        else
        {
            updateIcon.IsVisible = true;
            updateIcon.Text = status switch
            {
                UpdateLook.Current => "✓",
                UpdateLook.Failed => "!",
                _ => "↻",
            };
            var lit = updateHovered && status == null;
            updateLabel.Foreground = Paint.Brush(Rgb.White, lit ? 0.8 : 0.68);
            updateIcon.Foreground = updateLabel.Foreground;
            updateChip.Background = Paint.Brush(Rgb.White, lit ? 0.11 : 0.075);
            updateChip.BorderBrush = Paint.Brush(Rgb.White, 0.05);
            updateChip.BorderThickness = new Thickness(1);
        }
        if (status == UpdateLook.Checking && !installing)
        {
            if (!updateSpinTimer.IsEnabled) updateSpinTimer.Start();
        }
        else
        {
            updateSpinTimer.Stop();
            updateSpin.Angle = 0;
        }
        LayoutFill();
    }

    string UpdateLabel(bool installing, bool busy, WinRelease? offer, UpdateLook? status)
    {
        var lang = model.Language;
        if (installing)
        {
            var progress = Updates?.Progress;
            if (progress is >= 1) return Copy.Get(Phrase.Installing, lang);
            if (busy && Updates?.ProgressKnown == true)
                return Copy.Format(Phrase.Receiving, lang, (int)Math.Clamp((progress ?? 0) * 100, 0, 99));
            if (busy) return Copy.Get(Phrase.Updating, lang);
            return offer == null ? Copy.Get(Phrase.Update, lang) : Copy.Format(Phrase.UpdateReady, lang, offer.Version);
        }
        return status switch
        {
            UpdateLook.Checking => Copy.Get(Phrase.Checking, lang),
            UpdateLook.Current => Copy.Get(Phrase.Latest, lang),
            UpdateLook.Failed => Copy.Get(Phrase.CheckFailed, lang),
            _ => Copy.Get(Phrase.Update, lang),
        };
    }

    void PressUpdate()
    {
        if (Updates == null || Updates.Busy || Updates.Status == UpdateLook.Checking) return;
        if (Updates.Offer != null)
            _ = Updates.Install(() => Quit?.Invoke());
        else
            Updates.CheckNow();
        ShowUpdate();
    }

    void LayoutFill()
    {
        var progress = Updates?.Progress;
        var show = Updates?.Busy == true && progress != null;
        updateFill.IsVisible = show;
        if (!show || updateWidth <= 0) return;
        updateFill.Width = Math.Max(updateChip.Bounds.Height, updateWidth * Math.Clamp(progress.Value, 0, 1));
    }

    void FadeBody()
    {
        body.Opacity = 0.38;
        Dispatcher.UIThread.Post(() => body.Opacity = 1, DispatcherPriority.Background);
    }

    void Dismiss()
    {
        if (!IsVisible) return;
        CloseLanguageMenu();
        hiddenAt = Environment.TickCount64;
        Hide();
    }

    void Place()
    {
        var screen = Screens?.Primary;
        if (screen == null) return;
        var area = screen.WorkingArea;
        var bounds = screen.Bounds;
        var scale = screen.Scaling;
        var width = Bounds.Width * scale;
        var height = Bounds.Height * scale;
        fromTop = area.Y > bounds.Y;
        var x = area.X > bounds.X ? area.X : area.Right - width;
        var y = fromTop ? area.Y : area.Bottom - height;
        Position = new PixelPoint((int)Math.Round(x), (int)Math.Round(y));
    }

    Control Header()
    {
        var grid = new Grid
        {
            ColumnDefinitions = { new ColumnDefinition(GridLength.Auto), new ColumnDefinition(GridLength.Star), new ColumnDefinition(GridLength.Auto) },
            Margin = new Thickness(2, 0, 0, 2),
        };
        var image = Bundled.Image("MochinotchIcon.png");
        var logo = new Border
        {
            Width = 34,
            Height = 34,
            CornerRadius = new CornerRadius(8),
            ClipToBounds = true,
            VerticalAlignment = VerticalAlignment.Top,
            Child = image == null ? null : new Image { Source = image, Stretch = Stretch.UniformToFill },
        };
        grid.Children.Add(logo);
        var text = new StackPanel { Spacing = 2, Margin = new Thickness(11, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock { Text = "Mochinotch", FontSize = 15, FontWeight = FontWeight.SemiBold, Foreground = Brushes.White });
        text.Children.Add(hint);
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        var version = typeof(SettingsWindow).Assembly.GetName().Version;
        var badge = new Border
        {
            Padding = new Thickness(7, 2),
            CornerRadius = new CornerRadius(8),
            Background = Paint.Brush(Rgb.White, 0.08),
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 2, 0, 0),
            Child = new TextBlock
            {
                Text = version == null ? "" : $"{version.Major}.{version.Minor}.{version.Build}",
                FontSize = 10.5,
                FontWeight = FontWeight.SemiBold,
                Foreground = Paint.Brush(Rgb.White, 0.5),
            },
        };
        Grid.SetColumn(badge, 2);
        grid.Children.Add(badge);
        return grid;
    }

    Control Footer()
    {
        var quit = Capsule(quitText, Paint.Color(Rgb.White, 0), Paint.Color(Danger, 0.16), () => Quit?.Invoke());
        quit.HorizontalAlignment = HorizontalAlignment.Right;
        quit.PointerEntered += (_, _) => quitText.Foreground = Paint.Brush(Danger);
        quit.PointerExited += (_, _) => quitText.Foreground = Paint.Brush(Rgb.White, 0.62);
        var row = new Grid
        {
            ColumnDefinitions = { new ColumnDefinition(GridLength.Auto), new ColumnDefinition(GridLength.Star) },
            Margin = new Thickness(2, 0, 0, 0),
        };
        row.Children.Add(updateChip);
        Grid.SetColumn(quit, 1);
        row.Children.Add(quit);
        return row;
    }

    string AgentStatus(Lang lang)
    {
        var present = model.Links.Where(link => link.Present).ToList();
        if (present.Count == 0) return Copy.Get(Phrase.Missing, lang);
        var connected = present.Where(link => link.Connected).Select(link => AgentPalette.DisplayName(ToolOf(link.Tool))).ToList();
        return connected.Count == 0
            ? string.Join(" · ", present.Select(link => AgentPalette.DisplayName(ToolOf(link.Tool))))
            : Copy.Format(Phrase.Connected, lang, string.Join(", ", connected));
    }

    static Border Group(params Control?[] rows)
    {
        var stack = new StackPanel();
        foreach (var row in rows.Where(row => row != null))
        {
            if (stack.Children.Count > 0)
                stack.Children.Add(new Border { Height = 1, Margin = new Thickness(12, 0), Background = Paint.Brush(Rgb.White, 0.07) });
            stack.Children.Add(row!);
        }
        return new Border
        {
            CornerRadius = new CornerRadius(11),
            Background = Paint.Brush(Rgb.White, 0.055),
            ClipToBounds = true,
            Child = stack,
        };
    }

    Border Row(Control label, Control accessory, Action click)
    {
        var grid = new Grid { ColumnDefinitions = { new ColumnDefinition(GridLength.Star), new ColumnDefinition(GridLength.Auto) } };
        label.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(label);
        accessory.VerticalAlignment = VerticalAlignment.Center;
        accessory.Margin = new Thickness(12, 0, 0, 0);
        Grid.SetColumn(accessory, 1);
        grid.Children.Add(accessory);
        var row = Pad(grid);
        row.Background = Brushes.Transparent;
        row.Cursor = new Cursor(StandardCursorType.Hand);
        row.PointerEntered += (_, _) => row.Background = Paint.Brush(Rgb.White, 0.04);
        row.PointerExited += (_, _) => row.Background = Brushes.Transparent;
        row.PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(row).Properties.IsLeftButtonPressed) return;
            click();
            Sync();
            eventArgs.Handled = true;
        };
        return row;
    }

    static Border Pad(Control child) => new() { Padding = new Thickness(12, 10), Child = child };

    static StackPanel Stack(params Control[] children)
    {
        var stack = new StackPanel { Spacing = 2 };
        foreach (var child in children) stack.Children.Add(child);
        return stack;
    }

    Control LanguageBlock()
    {
        foreach (var lang in new[] { Lang.Ko, Lang.Ja, Lang.En, Lang.Zh })
            languageMenu.Children.Add(LanguageItem(lang));
        var ease = new CubicEaseOut();
        languageMenu.RenderTransform = languageShift;
        languageMenu.Transitions = [new DoubleTransition { Property = OpacityProperty, Duration = TimeSpan.FromSeconds(0.2), Easing = ease }];
        languageShift.Transitions = [new DoubleTransition { Property = TranslateTransform.YProperty, Duration = TimeSpan.FromSeconds(0.26), Easing = ease }];
        languageClip.Child = languageMenu;
        languageClip.Transitions = [new DoubleTransition { Property = HeightProperty, Duration = TimeSpan.FromSeconds(0.26), Easing = ease }];
        var block = new StackPanel();
        block.Children.Add(Row(languageTitle, LanguageAccessory(), ToggleLanguageMenu));
        block.Children.Add(languageClip);
        return block;
    }

    Control LanguageAccessory()
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        row.Children.Add(languageValue);
        row.Children.Add(languageChevron);
        return row;
    }

    Border LanguageItem(Lang lang)
    {
        var item = new Border
        {
            Padding = new Thickness(10, 7),
            CornerRadius = new CornerRadius(8),
            Background = Brushes.Transparent,
            Cursor = new Cursor(StandardCursorType.Hand),
            Child = new TextBlock
            {
                Text = Copy.Native(lang),
                FontSize = 13,
                Foreground = Paint.Brush(Rgb.White, 0.92),
            },
        };
        item.PointerEntered += (_, _) =>
        {
            if (model.Language != lang) item.Background = Paint.Brush(Rgb.White, 0.05);
        };
        item.PointerExited += (_, _) =>
        {
            item.Background = model.Language == lang ? Paint.Brush(Rgb.White, 0.1) : Brushes.Transparent;
        };
        item.PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(item).Properties.IsLeftButtonPressed) return;
            ChooseLanguage(lang);
            eventArgs.Handled = true;
        };
        languageItems[lang] = item;
        return item;
    }

    void ToggleLanguageMenu()
    {
        if (languageClip.Height < 1) OpenLanguageMenu();
        else CloseLanguageMenu();
    }

    void OpenLanguageMenu()
    {
        languageMenu.Measure(new Size(280, double.PositiveInfinity));
        var height = Math.Max(languageMenu.DesiredSize.Height, 36);
        languageChevron.Text = "▴";
        languageShift.Y = -8;
        languageMenu.Opacity = 0;
        languageClip.Height = height;
        Dispatcher.UIThread.Post(() =>
        {
            languageShift.Y = 0;
            languageMenu.Opacity = 1;
        });
    }

    void ChooseLanguage(Lang lang)
    {
        CloseLanguageMenu();
        if (lang != model.Language)
        {
            model.SetLanguage(lang);
            LanguageChanged?.Invoke();
        }
        Sync();
    }

    void CloseLanguageMenu()
    {
        languageChevron.Text = "▾";
        languageShift.Y = -6;
        languageMenu.Opacity = 0;
        languageClip.Height = 0;
    }

    Border Capsule(TextBlock text, Color rest, Color hover, Action click)
    {
        var capsule = new Border
        {
            Padding = new Thickness(12, 4.5),
            CornerRadius = new CornerRadius(12),
            Background = new SolidColorBrush(rest),
            Cursor = new Cursor(StandardCursorType.Hand),
            Child = text,
        };
        capsule.PointerEntered += (_, _) => capsule.Background = new SolidColorBrush(hover);
        capsule.PointerExited += (_, _) => capsule.Background = new SolidColorBrush(rest);
        capsule.PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(capsule).Properties.IsLeftButtonPressed) return;
            click();
            Sync();
            eventArgs.Handled = true;
        };
        return capsule;
    }

    static TextBlock Primary() => new() { FontSize = 13, FontWeight = FontWeight.Medium, Foreground = Paint.Brush(Rgb.White, 0.94) };

    static TextBlock Secondary(double size) => new() { FontSize = size, TextWrapping = TextWrapping.Wrap, Foreground = Paint.Brush(Rgb.White, 0.5) };

    static TextBlock Caption() => new() { FontSize = 11, FontWeight = FontWeight.SemiBold, Foreground = Paint.Brush(Rgb.White, 0.42) };

    static AgentTool ToolOf(HookTool tool) => tool switch
    {
        HookTool.Claude => AgentTool.Claude,
        HookTool.Cursor => AgentTool.Cursor,
        HookTool.Codex => AgentTool.Codex,
        HookTool.Kiro => AgentTool.Kiro,
        _ => AgentTool.Custom,
    };

    /// <summary>맥 설정과 같은 초록 스위치. 손잡이가 미끄러진다.</summary>
    sealed class MiniSwitch : Border
    {
        readonly Border fill;
        readonly TranslateTransform knob;

        public MiniSwitch()
        {
            Width = 36;
            Height = 20;
            CornerRadius = new CornerRadius(10);
            Background = Paint.Brush(Rgb.White, 0.16);
            var ease = new CubicEaseOut();
            fill = new Border
            {
                CornerRadius = new CornerRadius(10),
                Background = Paint.Brush(Green),
                Opacity = 0,
                Transitions = [new DoubleTransition { Property = OpacityProperty, Duration = TimeSpan.FromSeconds(0.2), Easing = ease }],
            };
            knob = new TranslateTransform
            {
                Transitions = [new DoubleTransition { Property = TranslateTransform.XProperty, Duration = TimeSpan.FromSeconds(0.26), Easing = new BackEaseOut() }],
            };
            var handle = new Border
            {
                Width = 16,
                Height = 16,
                Margin = new Thickness(2),
                CornerRadius = new CornerRadius(8),
                Background = Brushes.White,
                HorizontalAlignment = HorizontalAlignment.Left,
                BoxShadow = new BoxShadows(new BoxShadow { Blur = 3, OffsetY = 1, Color = Color.FromArgb(70, 0, 0, 0) }),
                RenderTransform = knob,
            };
            Child = new Panel { Children = { fill, handle } };
        }

        public bool IsOn
        {
            set
            {
                fill.Opacity = value ? 1 : 0;
                knob.X = value ? 16 : 0;
            }
        }
    }
}
