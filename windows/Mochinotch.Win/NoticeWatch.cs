using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace Mochinotch.Win;

/// <summary>
/// 알림 센터에서 Cursor·Claude·Codex·Kiro의 확인 요청만 읽는다.
/// 그 알림이 지워지면 답을 한 것으로 보고 오버레이를 접는다.
/// </summary>
sealed class NoticeWatch : IDisposable
{
    const int OpenReadonly = 1;
    const int OpenUri = 0x40;
    const int Row = 100;
    const int Done = 101;
    static readonly Regex TextTag = new(@"<text\b[^>]*>(.*?)</text>", RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.Compiled);
    static readonly byte[] Query = Encoding.UTF8.GetBytes("""
        SELECT n.Id, h.PrimaryId, n.ArrivalTime, n.Payload
        FROM Notification n
        JOIN NotificationHandler h ON h.RecordId = n.HandlerId
        WHERE n.Type = 'toast'
          AND (h.PrimaryId LIKE '%Cursor%' OR h.PrimaryId LIKE '%Claude%'
            OR h.PrimaryId LIKE '%Codex%' OR h.PrimaryId LIKE '%Kiro%')
        """ + "\0");

    readonly Action<IncomingEvent> publish;
    readonly byte[] databaseUri;
    readonly Dictionary<long, string> open = [];
    Timer? timer;
    int busy;
    bool primed;

    public NoticeWatch(Action<IncomingEvent> publish, string? database = null)
    {
        this.publish = publish;
        database ??= Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Microsoft", "Windows", "Notifications", "wpndatabase.db");
        var full = Path.GetFullPath(database).Replace('\\', '/');
        databaseUri = Encoding.UTF8.GetBytes("file:///" + full + "?mode=ro\0");
    }

    public void Start()
    {
        timer = new Timer(_ => Poll(), null, TimeSpan.FromMilliseconds(300), TimeSpan.FromMilliseconds(700));
    }

    public void Dispose()
    {
        timer?.Dispose();
        timer = null;
    }

    void Poll()
    {
        if (Interlocked.Exchange(ref busy, 1) == 1) return;
        try
        {
            var rows = Read();
            if (rows == null) return;
            var live = new Dictionary<long, string>();
            var fresh = new List<IncomingEvent>();
            foreach (var row in rows)
            {
                var parsed = AgentNotices.Interpret(row.AppId, row.Title, row.Body);
                if (parsed?.Tool == null || parsed.Kind != "needsInput") continue;
                if (!primed && !Recent(row.Arrival)) continue;
                live[row.Id] = parsed.Tool;
                if (open.ContainsKey(row.Id)) continue;
                fresh.Add(new IncomingEvent
                {
                    Id = "toast:" + row.Id,
                    Tool = parsed.Tool,
                    Kind = parsed.Kind,
                    Title = parsed.Title,
                    Detail = parsed.Detail,
                });
            }
            var gone = open.Where(pair => !live.ContainsKey(pair.Key)).Select(pair => pair.Value).Distinct().ToList();
            primed = true;
            open.Clear();
            foreach (var pair in live) open[pair.Key] = pair.Value;
            foreach (var tool in gone)
                publish(new IncomingEvent { Tool = tool, Kind = "resolved" });
            foreach (var incoming in fresh)
                publish(incoming);
        }
        catch (Exception)
        {
            // 알림 데이터베이스가 잠깐 잠겨도 다음 주기에 다시 본다.
        }
        finally
        {
            Interlocked.Exchange(ref busy, 0);
        }
    }

    List<ToastRow>? Read()
    {
        if (sqlite3_open_v2(databaseUri, out var db, OpenReadonly | OpenUri, 0) != 0)
            return null;
        try
        {
            sqlite3_busy_timeout(db, 200);
            if (sqlite3_prepare_v2(db, Query, Query.Length, out var statement, 0) != 0)
                return null;
            try
            {
                var rows = new List<ToastRow>();
                while (true)
                {
                    var step = sqlite3_step(statement);
                    if (step == Done) return rows;
                    if (step != Row) return null;
                    var (title, body) = Texts(Column(statement, 3));
                    rows.Add(new ToastRow(sqlite3_column_int64(statement, 0), Column(statement, 1), sqlite3_column_int64(statement, 2), title, body));
                }
            }
            finally
            {
                sqlite3_finalize(statement);
            }
        }
        finally
        {
            sqlite3_close(db);
        }
    }

    static (string Title, string Body) Texts(string xml)
    {
        var found = new List<string>();
        foreach (Match match in TextTag.Matches(xml))
            found.Add(WebUtility.HtmlDecode(match.Groups[1].Value).Trim());
        return (found.Count > 0 ? found[0] : "", found.Count > 1 ? found[1] : "");
    }

    static string Column(nint statement, int index)
    {
        var pointer = sqlite3_column_blob(statement, index);
        var count = sqlite3_column_bytes(statement, index);
        if (pointer == 0 || count <= 0)
        {
            var text = sqlite3_column_text(statement, index);
            return text == 0 ? "" : Marshal.PtrToStringUTF8(text) ?? "";
        }
        var bytes = new byte[count];
        Marshal.Copy(pointer, bytes, 0, count);
        return Encoding.UTF8.GetString(bytes);
    }

    static bool Recent(long fileTime)
    {
        if (fileTime <= 0) return false;
        try
        {
            return DateTime.UtcNow - DateTime.FromFileTimeUtc(fileTime) <= TimeSpan.FromHours(12);
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    readonly record struct ToastRow(long Id, string AppId, long Arrival, string Title, string Body);

    [DllImport("winsqlite3", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_open_v2(byte[] filename, out nint db, int flags, nint vfs);

    [DllImport("winsqlite3", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_busy_timeout(nint db, int milliseconds);

    [DllImport("winsqlite3", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_prepare_v2(nint db, byte[] sql, int length, out nint statement, nint tail);

    [DllImport("winsqlite3", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_step(nint statement);

    [DllImport("winsqlite3", CallingConvention = CallingConvention.Cdecl)]
    static extern long sqlite3_column_int64(nint statement, int index);

    [DllImport("winsqlite3", CallingConvention = CallingConvention.Cdecl)]
    static extern nint sqlite3_column_text(nint statement, int index);

    [DllImport("winsqlite3", CallingConvention = CallingConvention.Cdecl)]
    static extern nint sqlite3_column_blob(nint statement, int index);

    [DllImport("winsqlite3", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_column_bytes(nint statement, int index);

    [DllImport("winsqlite3", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_finalize(nint statement);

    [DllImport("winsqlite3", CallingConvention = CallingConvention.Cdecl)]
    static extern int sqlite3_close(nint db);
}
