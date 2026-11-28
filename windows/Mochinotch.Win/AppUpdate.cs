using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using Avalonia.Threading;

namespace Mochinotch.Win;

enum UpdateLook
{
    Checking,
    Current,
    Failed,
}

/// <summary>
/// GitHub 최신 릴리즈에 윈도우 파일이 있으면 설정에서 확인하고 받을 수 있다.
/// 받기가 끝나면 지금 실행 중인 exe를 같은 자리에 덮어쓰고 다시 연다.
/// </summary>
sealed class AppUpdate : IDisposable
{
    const string Latest = "https://api.github.com/repos/sleeeppy/mochinotch/releases/latest";
    readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(12) };
    readonly HttpClient download = new(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromMinutes(4) };
    readonly string local;
    readonly bool arm;
    Timer? timer;
    int checking;
    int manualRequest;
    int requestSerial;
    int statusGeneration;
    long checkStarted;

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
    public double? Progress { get; private set; }
    public bool ProgressKnown { get; private set; }
    public UpdateLook? Status { get; private set; }
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

    /// <summary>설정의 업데이트 확인. 간격과 상관없이 바로 보고, 결과를 잠깐 보여 준다.</summary>
    public void CheckNow()
    {
        if (Busy || Status == UpdateLook.Checking) return;
        Interlocked.Increment(ref statusGeneration);
        checkStarted = Environment.TickCount64;
        manualRequest = Interlocked.Increment(ref requestSerial);
        Status = UpdateLook.Checking;
        Progress = null;
        ProgressKnown = false;
        Publish();
        Check();
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
        Progress = 0;
        ProgressKnown = false;
        Publish();
        var swapped = false;
        try
        {
            var file = await Save(offer);
            if (file == null)
            {
                Open(offer.Page);
                return;
            }
            Progress = 1;
            Publish();
            var name = Path.GetFileName(file).ToLowerInvariant();
            if (WinUpdate.IsInstaller(name))
            {
                // 설치본은 창 없이 같은 자리에 덮어쓰고 다시 켠다. portable에서 넘어가면 설치 창을 보여 준다.
                var silent = WinUpdate.IsInstalled(Environment.ProcessPath) && name.EndsWith(".exe");
                Process.Start(new ProcessStartInfo(file) { UseShellExecute = true, Arguments = silent ? "/S" : "" });
                quit();
                swapped = true;
                return;
            }
            if (name.EndsWith(".zip"))
            {
                swapped = StageZip(file, quit);
                return;
            }
            swapped = StageFile(file, quit);
        }
        catch (Exception)
        {
            Open(offer.Page);
        }
        finally
        {
            if (!swapped)
            {
                Busy = false;
                Progress = null;
                ProgressKnown = false;
                Publish();
            }
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
        WinRelease? found = null;
        var ok = false;
        try
        {
            var json = await http.GetStringAsync(Latest);
            found = WinUpdate.FromLatest(json, local, arm, WinUpdate.IsInstalled(Environment.ProcessPath));
            ok = true;
        }
        catch (Exception)
        {
            // 네트워크가 없으면 다음 확인 때 다시 본다.
        }
        finally
        {
            Interlocked.Exchange(ref checking, 0);
        }

        var clicked = Volatile.Read(ref manualRequest);
        var answered = clicked != 0 && Interlocked.CompareExchange(ref manualRequest, 0, clicked) == clicked;
        var wait = 600 - (Environment.TickCount64 - checkStarted);
        if (answered && wait > 0) await Task.Delay((int)wait);
        var release = found;
        var reached = ok;
        Dispatcher.UIThread.Post(() =>
        {
            if (reached && (release?.Version != Offer?.Version || release?.Download != Offer?.Download))
                Offer = release;
            if (!answered)
            {
                if (reached && release != null) Status = null;
                Changed?.Invoke();
                return;
            }
            if (!reached) Hold(UpdateLook.Failed);
            else if (release == null) Hold(UpdateLook.Current);
            else
            {
                Status = null;
                Changed?.Invoke();
            }
        });
    }

    void Hold(UpdateLook look)
    {
        var generation = Interlocked.Increment(ref statusGeneration);
        Status = look;
        Changed?.Invoke();
        _ = Clear(generation);
    }

    async Task Clear(int generation)
    {
        await Task.Delay(2400);
        if (generation != Volatile.Read(ref statusGeneration)) return;
        Dispatcher.UIThread.Post(() =>
        {
            if (generation != statusGeneration) return;
            Status = null;
            Changed?.Invoke();
        });
    }

    async Task<string?> Save(WinRelease offer)
    {
        if (offer.Download == null || !WinUpdate.IsAllowedDownload(offer.Download)) return null;
        var rawName = string.IsNullOrEmpty(offer.FileName)
            ? new Uri(offer.Download).LocalPath
            : offer.FileName;
        var name = Path.GetFileName(rawName);
        if (string.IsNullOrEmpty(name)) return null;
        var directory = Path.Combine(Path.GetTempPath(), "mochinotch-update");
        Directory.CreateDirectory(directory);
        var destination = Path.Combine(directory, name);
        using var response = await SendAllowed(new Uri(offer.Download));
        if (response == null) return null;
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength ?? 0;
        ProgressKnown = total > 0;
        await using (var input = await response.Content.ReadAsStreamAsync())
        await using (var output = File.Create(destination))
        {
            var buffer = new byte[81920];
            long read = 0;
            var shown = -1;
            int count;
            while ((count = await input.ReadAsync(buffer)) > 0)
            {
                await output.WriteAsync(buffer.AsMemory(0, count));
                read += count;
                if (total <= 0) continue;
                var percent = (int)Math.Min(99, read * 100 / total);
                if (percent == shown) continue;
                shown = percent;
                Progress = percent / 100d;
                Publish();
            }
        }
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

    /// <summary>리다이렉트가 걸려도 GitHub 호스트 밖으로는 따라가지 않는다.</summary>
    async Task<HttpResponseMessage?> SendAllowed(Uri start)
    {
        var current = start;
        for (var hop = 0; hop < 5; hop++)
        {
            if (!WinUpdate.IsAllowedDownload(current.AbsoluteUri)) return null;
            using var request = new HttpRequestMessage(HttpMethod.Get, current);
            if (current.Host.Equals("api.github.com", StringComparison.OrdinalIgnoreCase))
                request.Headers.Accept.ParseAdd("application/octet-stream");
            var response = await download.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
            if (response.StatusCode is HttpStatusCode.Moved or HttpStatusCode.Redirect or HttpStatusCode.RedirectMethod or HttpStatusCode.TemporaryRedirect or HttpStatusCode.PermanentRedirect)
            {
                var location = response.Headers.Location;
                response.Dispose();
                if (location == null) return null;
                current = location.IsAbsoluteUri ? location : new Uri(current, location);
                continue;
            }
            return response;
        }
        return null;
    }

    static bool StageZip(string zip, Action quit)
    {
        var staged = Path.Combine(Path.GetTempPath(), "mochinotch-update", "staged");
        if (Directory.Exists(staged)) Directory.Delete(staged, true);
        Directory.CreateDirectory(staged);
        var root = Path.GetFullPath(staged).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        using (var archive = ZipFile.OpenRead(zip))
        {
            foreach (var entry in archive.Entries)
            {
                if (string.IsNullOrEmpty(entry.Name)) continue;
                var target = Path.GetFullPath(Path.Combine(staged, entry.FullName));
                if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                {
                    Open("https://github.com/sleeeppy/mochinotch/releases/latest");
                    return false;
                }
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                entry.ExtractToFile(target, overwrite: true);
            }
        }
        var exe = Directory.GetFiles(staged, "Mochinotch.exe", SearchOption.AllDirectories).FirstOrDefault();
        if (exe == null)
        {
            Open("https://github.com/sleeeppy/mochinotch/releases/latest");
            return false;
        }
        return Replace(exe, quit);
    }

    static bool StageFile(string file, Action quit)
    {
        if (!file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
        {
            Process.Start(new ProcessStartInfo(file) { UseShellExecute = true });
            quit();
            return true;
        }
        return Replace(file, quit);
    }

    static bool Replace(string staged, Action quit)
    {
        var destination = WinUpdate.InstallTarget(Environment.ProcessPath, AppContext.BaseDirectory);
        if (!WinUpdate.CanReplace(destination))
        {
            Open("https://github.com/sleeeppy/mochinotch/releases/latest");
            return false;
        }
        var root = Path.Combine(Path.GetTempPath(), "mochinotch-update");
        Directory.CreateDirectory(root);
        var script = Path.Combine(root, "apply.ps1");
        // Windows PowerShell 5.1은 BOM 없는 UTF-8을 ANSI로 읽어 한글 경로가 깨진다.
        File.WriteAllText(script, WinUpdate.SwapScript(Environment.ProcessId, staged, destination), new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
        Process.Start(new ProcessStartInfo("powershell", $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\"")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
        });
        quit();
        return true;
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
