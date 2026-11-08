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
    IslandModel? model;
    EventServer? server;

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
            var edge = new EdgeWindow();
            var toast = new ToastWindow(model);
            var island = new IslandWindow(model, edge, toast);
            island.Quit = () => desktop.Shutdown();
            edge.Raised = () =>
            {
                island.KeepAbove();
                toast.KeepAbove();
            };
            server = new EventServer(Launch.Port);
            server.OnEvent += incoming => Dispatcher.UIThread.Post(() =>
            {
                if (model != null) model.Ingest(incoming, island.Now);
            });
            server.Start();
            if (server.Failure != null) model.ServerFailure = server.Failure;
            desktop.Exit += (_, _) => server?.Dispose();
            island.Show();
            desktop.MainWindow = island;
        }
        base.OnFrameworkInitializationCompleted();
    }
}
