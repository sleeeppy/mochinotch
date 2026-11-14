using System.Text.Json;

namespace Mochinotch.Win;

public sealed record WinRelease(string Version, string Page, string? Download, string? FileName, string? Sha256);

/// <summary>
/// GitHub 최신 릴리즈에서 윈도우 설치 파일만 고른다.
/// 맥용 dmg는 받지 않는다. 자산 이름에 win이 들어가고 exe, msi, zip인 파일을 쓴다.
/// </summary>
public static class WinUpdate
{
    public static WinRelease? FromLatest(string json, string localVersion, bool arm = false)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            var tag = root.TryGetProperty("tag_name", out var tagValue) ? tagValue.GetString() ?? "" : "";
            if (!Newer(tag, localVersion)) return null;
            if (!root.TryGetProperty("assets", out var assets)) return null;
            var chosen = Choose(assets, arm);
            if (chosen == null) return null;
            var page = PageOf(root) ?? "https://github.com/sleeeppy/mochinotch/releases/latest";
            var version = tag.Trim().TrimStart('v', 'V');
            var dash = version.IndexOfAny(['-', '+']);
            if (dash > 0) version = version[..dash];
            return new WinRelease(version, page, chosen.Value.Url, chosen.Value.Name, chosen.Value.Sha256);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static bool Newer(string tag, string local)
        => TryVersion(tag, out var remote) && TryVersion(local, out var here) && remote > here;

    static bool TryVersion(string text, out Version version)
    {
        version = new Version(0, 0);
        var clean = text.Trim().TrimStart('v', 'V');
        var cut = clean.IndexOfAny(['-', '+']);
        if (cut >= 0) clean = clean[..cut];
        return Version.TryParse(clean, out version!);
    }

    static (string Url, string Name, string? Sha256)? Choose(JsonElement assets, bool arm)
    {
        (string Url, string Name, string? Sha256, int Score)? best = null;
        foreach (var asset in assets.EnumerateArray())
        {
            var name = asset.TryGetProperty("name", out var nameValue) ? nameValue.GetString() ?? "" : "";
            var lowered = name.ToLowerInvariant();
            if (!IsWindowsPackage(lowered)) continue;
            var url = AssetUrl(asset);
            if (url == null) continue;
            var score = ScoreOf(lowered, arm);
            if (best == null || score > best.Value.Score)
                best = (url, name, Digest(asset), score);
        }
        return best == null ? null : (best.Value.Url, best.Value.Name, best.Value.Sha256);
    }

    static bool IsWindowsPackage(string name)
    {
        if (!(name.Contains("win") || name.Contains("windows"))) return false;
        return name.EndsWith(".exe") || name.EndsWith(".msi") || name.EndsWith(".zip");
    }

    static int ScoreOf(string name, bool arm)
    {
        var score = name.EndsWith(".exe") ? 30 : name.EndsWith(".msi") ? 20 : 10;
        if (name.Contains("mochinotch")) score += 20;
        var wantsArm = name.Contains("arm64") || name.Contains("aarch64");
        var wantsIntel = name.Contains("x64") || name.Contains("win64") || name.Contains("x86_64");
        if (arm && wantsArm) score += 40;
        if (!arm && wantsIntel) score += 40;
        if (arm && wantsIntel) score -= 40;
        if (!arm && wantsArm) score -= 40;
        return score;
    }

    /// <summary>releases/download는 한국 엣지에서 504가 난다. 자산 API 주소를 먼저 쓴다.</summary>
    static string? AssetUrl(JsonElement asset)
    {
        foreach (var key in new[] { "url", "browser_download_url" })
        {
            if (!asset.TryGetProperty(key, out var value)) continue;
            var raw = value.GetString();
            if (Allowed(raw)) return raw;
        }
        return null;
    }

    static string? Digest(JsonElement asset)
    {
        if (!asset.TryGetProperty("digest", out var digestValue)) return null;
        var text = (digestValue.GetString() ?? "").Trim().ToLowerInvariant();
        if (!text.StartsWith("sha256:", StringComparison.Ordinal)) return null;
        var hex = text["sha256:".Length..];
        return hex.Length == 64 && hex.All(Uri.IsHexDigit) ? hex : null;
    }

    static string? PageOf(JsonElement root)
    {
        var raw = root.TryGetProperty("html_url", out var page) ? page.GetString() : null;
        if (raw == null || !Uri.TryCreate(raw, UriKind.Absolute, out var uri)) return null;
        if (uri.Scheme != "https" || !string.Equals(uri.Host, "github.com", StringComparison.OrdinalIgnoreCase))
            return null;
        return uri.AbsoluteUri;
    }

    /// <summary>업데이트가 덮어쓸 파일. 받아 둔 이름이 달라도 지금 실행 중인 exe를 바꾼다.</summary>
    public static string InstallTarget(string? processPath, string baseDirectory)
    {
        if (!string.IsNullOrWhiteSpace(processPath)) return processPath;
        var directory = baseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return Path.Combine(directory, "Mochinotch.exe");
    }

    /// <summary>실행 중인 파일이 잠겨 있으므로, 앱이 꺼진 뒤에 같은 경로로 덮어쓰고 다시 연다.</summary>
    public static string SwapScript(int processId, string staged, string destination)
        => $"""
            Wait-Process -Id {processId} -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 400
            Copy-Item -LiteralPath {Quote(staged)} -Destination {Quote(destination)} -Force
            Start-Process -FilePath {Quote(destination)}
            """;

    public static bool CanReplace(string destination)
    {
        try
        {
            var directory = Path.GetDirectoryName(destination);
            if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory)) return false;
            var probe = Path.Combine(directory, ".mochinotch-write-" + Environment.ProcessId);
            using var stream = new FileStream(probe, FileMode.Create, FileAccess.Write, FileShare.None, 1, FileOptions.DeleteOnClose);
            return stream.CanWrite;
        }
        catch (Exception)
        {
            return false;
        }
    }

    static string Quote(string path) => "'" + path.Replace("'", "''") + "'";

    static bool Allowed(string? raw)
    {
        if (raw == null || !Uri.TryCreate(raw, UriKind.Absolute, out var uri)) return false;
        if (!string.Equals(uri.Scheme, "https", StringComparison.OrdinalIgnoreCase)) return false;
        var host = uri.Host.ToLowerInvariant();
        return host == "github.com" || host.EndsWith(".github.com")
            || host == "githubusercontent.com" || host.EndsWith(".githubusercontent.com");
    }
}
