using System.Security.Cryptography;
using System.Text;

namespace Mochinotch.Win;

public static class EventEndpoint
{
    public const int Port = 47321;
    public const string Header = "X-Mochinotch-Token";
}

public static class EventToken
{
    public static string StoragePath { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Mochinotch",
        "event.token");

    public static string LoadOrCreate()
    {
        var existing = Read();
        if (existing != null) return existing;
        var created = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
        Write(created);
        return Read() ?? created;
    }

    public static string? Current() => Read();

    public static bool Accepts(string? presented)
    {
        var expected = Read();
        if (expected == null || string.IsNullOrEmpty(presented)) return false;
        var left = Encoding.UTF8.GetBytes(presented);
        var right = Encoding.UTF8.GetBytes(expected);
        return left.Length == right.Length && CryptographicOperations.FixedTimeEquals(left, right);
    }

    static string? Read()
    {
        if (!File.Exists(StoragePath)) return null;
        var token = File.ReadAllText(StoragePath).Trim();
        return token.Length == 0 ? null : token;
    }

    static void Write(string token)
    {
        var directory = Path.GetDirectoryName(StoragePath)!;
        Directory.CreateDirectory(directory);
        File.WriteAllText(StoragePath, token);
    }
}
