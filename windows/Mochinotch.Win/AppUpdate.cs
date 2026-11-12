using System.Diagnostics;
using System.IO.Compression;
using System.Security.Cryptography;
using Avalonia.Threading;

namespace Mochinotch.Win;

/// <summary>
/// GitHub 최신 릴리즈에 윈도우 파일이 있으면 설정에서 받을 수 있게 한다.
/// 설치 파일이면 실행하고, 압축이면 이 앱이 꺼진 뒤 같은 자리에 덮어쓰고 다시 연다.
/// </summary>
sealed class AppUpdate : IDisposable
{
    const string Latest = "https://api.github.com/repos/sleeeppy/mochinotch/releases/latest";
    readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(12) };
    readonly HttpClient download = new() { Timeout = TimeSpan.FromMinutes(4) };
    readonly string local;
    readonly bool arm;
    Timer? timer;
    int checking;

    public AppUpdate()
    {
        var version = typeof(AppUpdate).Assembly.GetName().Version;
        local = version == null ? "0.0.0" : $"{version.Major}.{version.Minor}.{Math.Max(version.Build, 0)}";
        arm = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64;
        http.DefaultRequestHeaders.UserAgent.ParseAdd("Mochinotch");
        http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        download.DefaultRequestHeaders.UserAgent.ParseAdd("Mochinotch");
    }

    public WinRelease? Offer { get; private set; }
    public bool Busy { get; private set; }
    public event Action? Changed;

    public void Start()
    {
        Check();
        timer = new Timer(_ => Check(), null, TimeSpan.FromMinutes(50), TimeSpan.FromMinutes(50));
    }

    public void Check()
    {
        if (Interlocked.Exchange(ref checking, 1) == 1) return;
        _ = Read();
    }

    public async Task Install(Action quit)
    {
        var offer = Offer;
        if (offer == null || Busy) return;
        if (string.IsNullOrEmpty(offer.Download))
        {
            Open(offer.Page);
            return;
        }
        Busy = true;
        Publish();
        try
        {
            var file = await Save(offer);
            if (file == null)
            {
                Open(offer.Page);
                return;
            }
            var name = Path.GetFileName(file).ToLowerInvariant();
            if (name.EndsWith(".msi") || name.Contains("setup") || name.Contains("install"))
            {
                Process.Start(new ProcessStartInfo(file) { UseShellExecute = true });
                quit();
                return;
            }
            if (name.EndsWith(".zip"))
            {
                StageZip(file, quit);
                return;
            }
            StageFile(file, quit);
        }
        catch (Exception)
        {
            Open(offer.Page);
        }
        finally
        {
            Busy = false;
            Publish();
        }
    }

    public void Dispose()
    {
        timer?.Dispose();
        http.Dispose();
        download.Dispose();
    }

    async Task Read()
    {
        try
        {
            var json = await http.GetStringAsync(Latest);
            var found = WinUpdate.FromLatest(json, local, arm);
            if (found?.Version != Offer?.Version || found?.Download != Offer?.Download)
            {
                Offer = found;
                Publish();
            }
        }
        catch (Exception)
        {
            // 네트워크가 없으면 다음 확인 때 다시 본다.
        }
        finally
        {
            Interlocked.Exchange(ref checking, 0);
        }
    }

    async Task<string?> Save(WinRelease offer)
    {
        if (offer.Download == null) return null;
        var name = string.IsNullOrEmpty(offer.FileName)
            ? Path.GetFileName(new Uri(offer.Download).LocalPath)
            : offer.FileName;
        if (string.IsNullOrEmpty(name)) return null;
        var directory = Path.Combine(Path.GetTempPath(), "mochinotch-update");
        Directory.CreateDirectory(directory);
        var destination = Path.Combine(directory, name);
        using var request = new HttpRequestMessage(HttpMethod.Get, offer.Download);
        if (request.RequestUri?.Host.Equals("api.github.com", StringComparison.OrdinalIgnoreCase) == true)
            request.Headers.Accept.ParseAdd("application/octet-stream");
        using var response = await download.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();
        await using (var input = await response.Content.ReadAsStreamAsync())
        await using (var output = File.Create(destination))
            await input.CopyToAsync(output);
        if (offer.Sha256 != null)
        {
            var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(destination))).ToLowerInvariant();
            if (!string.Equals(hash, offer.Sha256, StringComparison.Ordinal))
            {
                File.Delete(destination);
                return null;
            }
        }
        return destination;
    }

    static void StageZip(string zip, Action quit)
    {
        var staged = Path.Combine(Path.GetTempPath(), "mochinotch-update", "staged");
        if (Directory.Exists(staged)) Directory.Delete(staged, true);
        ZipFile.ExtractToDirectory(zip, staged);
        var exe = Directory.GetFiles(staged, "Mochinotch.exe", SearchOption.AllDirectories).FirstOrDefault();
        if (exe == null)
        {
            Open("https://github.com/sleeeppy/mochinotch/releases/latest");
            return;
        }
        Swap(Path.GetDirectoryName(exe)!, quit);
    }

    static void StageFile(string file, Action quit)
    {
        if (!file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
        {
            Process.Start(new ProcessStartInfo(file) { UseShellExecute = true });
            quit();
            return;
        }
        var folder = Path.Combine(Path.GetTempPath(), "mochinotch-update", "staged");
        Directory.CreateDirectory(folder);
        var target = Path.Combine(folder, "Mochinotch.exe");
        File.Copy(file, target, true);
        Swap(folder, quit);
    }

    static void Swap(string staged, Action quit)
    {
        var dest = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        var script = Path.Combine(Path.GetTempPath(), "mochinotch-update", "apply.ps1");
        File.WriteAllText(script, $$"""
            Wait-Process -Id {{Environment.ProcessId}} -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            Copy-Item -Path '{{staged}}\*' -Destination '{{dest}}' -Recurse -Force
            Start-Process -FilePath '{{Path.Combine(dest, "Mochinotch.exe")}}'
            """);
        Process.Start(new ProcessStartInfo("powershell", $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\"")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
        });
        quit();
    }

    static void Open(string page)
    {
        try
        {
            Process.Start(new ProcessStartInfo(page) { UseShellExecute = true });
        }
        catch (Exception)
        {
            // 브라우저를 못 열어도 설정은 그대로 둔다.
        }
    }

    void Publish() => Dispatcher.UIThread.Post(() => Changed?.Invoke());
}
