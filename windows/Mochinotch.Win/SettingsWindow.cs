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
    readonly TextBlock updateText = new() { FontSize = 13, FontWeight = FontWeight.SemiBold, Foreground = Brushes.White };
    readonly Border updateRow;
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
        updateRow = UpdateBanner();
        body.Children.Add(updateRow);
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
        updateRow.IsVisible = busy || offer != null;
        updateText.Text = busy
            ? Copy.Get(Phrase.Updating, model.Language)
            : offer == null ? "" : Copy.Format(Phrase.UpdateReady, model.Language, offer.Version);
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
        return quit;
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

    Border UpdateBanner()
    {
        var row = new Border
        {
            Padding = new Thickness(12, 9),
            CornerRadius = new CornerRadius(11),
            Background = Paint.Brush(new Rgb(0.204, 0.780, 0.349), 0.18),
            Cursor = new Cursor(StandardCursorType.Hand),
            Child = updateText,
            IsVisible = false,
        };
        row.PointerPressed += (_, eventArgs) =>
        {
            if (!eventArgs.GetCurrentPoint(row).Properties.IsLeftButtonPressed) return;
            eventArgs.Handled = true;
            if (Updates == null || Updates.Busy) return;
            _ = Updates.Install(() => Quit?.Invoke());
            ShowUpdate();
        };
        return row;
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
