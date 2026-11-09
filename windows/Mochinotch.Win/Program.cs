using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Threading;

namespace Mochinotch.Win;

public static class Launch
{
    public static int Port { get; set; } = EventEndpoint.Port;
}

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        if (args.FirstOrDefault() == "--hook")
            return HookRelay.Run(args.Skip(1).ToArray());
        if (args.FirstOrDefault() == "--install-hooks")
            return InstallHooks();
        for (var index = 0; index < args.Length; index++)
        {
            if (args[index] == "--port" && index + 1 < args.Length && int.TryParse(args[index + 1], out var port))
                Launch.Port = port;
        }

        using var mutex = new Mutex(true, "dev.sleeeppy.mochinotch.win", out var created);
        if (!created) return 0;
        try
        {
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
            return 0;
        }
        catch (Exception ex)
        {
            try
            {
                var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Mochinotch");
                Directory.CreateDirectory(directory);
                File.WriteAllText(Path.Combine(directory, "windows-crash.log"), ex.ToString());
            }
            catch
            {
                // 기록을 못 해도 프로세스는 끝낸다.
            }
            return 1;
        }
    }

    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>().UsePlatformDetect().WithInterFont().LogToTrace();

    static int InstallHooks()
    {
        if (!OperatingSystem.IsWindows())
        {
            Console.Error.WriteLine(Copy.Get(Phrase.WindowsOnly, Copy.Detect()));
            return 1;
        }
        var exe = Environment.ProcessPath ?? "";
        var present = HookInstaller.Scan().Where(link => link.Present).Select(link => link.Tool).ToList();
        if (present.Count == 0)
        {
            Console.Error.WriteLine(Copy.Get(Phrase.Missing, Copy.Detect()));
            return 1;
        }
        var result = HookInstaller.Install(HookInstaller.Home, exe, present);
        foreach (var tool in result.Connected)
            Console.WriteLine(tool + ": " + (result.Changed.Contains(tool) ? Copy.Get(Phrase.Linked, Copy.Detect()) : Copy.Get(Phrase.Already, Copy.Detect())));
        foreach (var failure in result.Failures)
            Console.WriteLine(failure.Tool + ": " + failure.Problem);
        if (result.Changed.Count > 0)
            Console.WriteLine(Copy.Format(Phrase.Restart, Copy.Detect(), string.Join(", ", result.Changed)));
        return result.Failures.Count == 0 ? 0 : 1;
    }
}

public class App : Application
{
    readonly Stopwatch clock = Stopwatch.StartNew();
    IslandModel? model;
    EventServer? server;
    EdgeWindow? edge;
    ToastWindow? toast;
    SettingsWindow? settings;
    TrayIcon? tray;
    NoticeWatch? notices;
    AppUpdate? updates;
    DispatcherTimer? timer;

    public override void Initialize()
    {
        RequestedThemeVariant = Avalonia.Styling.ThemeVariant.Dark;
        Styles.Add(new Avalonia.Themes.Fluent.FluentTheme());
    }

    public override void OnFrameworkInitializationCompleted()
    {
        WindowChrome.HideDock();
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            model = new IslandModel();
            edge = new EdgeWindow();
            toast = new ToastWindow(model, () => clock.Elapsed.TotalSeconds);
            toast.Prepare();
            settings = new SettingsWindow(model);
            updates = new AppUpdate();
            settings.Updates = updates;
            updates.Changed += () => settings.ShowUpdate();
            updates.Start();
            settings.Quit = () => desktop.Shutdown();
            settings.LanguageChanged = RefreshTray;
            var icon = LoadIcon();
            if (icon != null) settings.Icon = icon;
            edge.Raised = () => toast.KeepAbove();
            server = new EventServer(Launch.Port);
            server.OnEvent += incoming => Dispatcher.UIThread.Post(() =>
            {
                if (model == null) return;
                model.Ingest(incoming, clock.Elapsed.TotalSeconds);
                OnTick();
            });
            server.Start();
            if (server.Failure != null) model.ServerFailure = server.Failure;
            notices = new NoticeWatch(incoming => Dispatcher.UIThread.Post(() =>
            {
                if (model == null) return;
                model.Ingest(incoming, clock.Elapsed.TotalSeconds);
                OnTick();
            }));
            notices.Start();
            AttachTray(icon);
            desktop.Exit += (_, _) =>
            {
                timer?.Stop();
                notices?.Dispose();
                updates?.Dispose();
                server?.Dispose();
                tray?.Dispose();
            };
            timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
            timer.Tick += (_, _) => OnTick();
            timer.Start();
        }
        base.OnFrameworkInitializationCompleted();
    }

    void OnTick()
    {
        if (model == null || timer == null) return;
        var now = clock.Elapsed.TotalSeconds;
        model.Tick(now);
        edge?.Sync(model);
        toast?.Wake();
        settings?.Sync();
        var busy = model.EdgeVisible || model.Toasts(now).Count > 0 || toast?.Active == true;
        timer.Interval = TimeSpan.FromMilliseconds(busy ? 16 : 200);
    }

    void AttachTray(WindowIcon? icon)
    {
        if (settings == null) return;
        tray = new TrayIcon
        {
            Icon = icon,
            ToolTipText = "Mochinotch",
            IsVisible = true,
        };
        tray.Clicked += (_, _) => Dispatcher.UIThread.Post(settings.Toggle);
        RefreshTray();
        TrayIcon.SetIcons(this, new TrayIcons { tray });
    }

    void RefreshTray()
    {
        if (tray == null || model == null || settings == null) return;
        var menu = new NativeMenu();
        var open = new NativeMenuItem { Header = Copy.Get(Phrase.Settings, model.Language) };
        open.Click += (_, _) => Dispatcher.UIThread.Post(settings.Open);
        var exit = new NativeMenuItem { Header = Copy.Get(Phrase.Quit, model.Language) };
        exit.Click += (_, _) => Dispatcher.UIThread.Post(() =>
        {
            if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
                desktop.Shutdown();
        });
        menu.Items.Add(open);
        menu.Items.Add(exit);
        tray.Menu = menu;
    }

    static WindowIcon? LoadIcon()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "MochinotchIcon.png");
        return File.Exists(path) ? new WindowIcon(path) : null;
    }
}
