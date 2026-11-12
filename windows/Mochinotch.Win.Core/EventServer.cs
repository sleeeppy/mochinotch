using System.Net;
using System.Text;
using System.Text.Json;

namespace Mochinotch.Win;

public sealed class IncomingEvent
{
    public string? Id { get; init; }
    public string? Tool { get; init; }
    public string? Title { get; init; }
    public string? Detail { get; init; }
    public bool? Success { get; init; }
    public string? Kind { get; init; }
    public string? BundleID { get; init; }
}

/// <summary>루프백 <c>POST /event</c>. hook이 토큰을 붙여 에이전트 상태를 보낸다.</summary>
public sealed class EventServer : IDisposable
{
    readonly int port;
    HttpListener? listener;
    CancellationTokenSource? cancel;

    public EventServer(int port) => this.port = port;

    public event Action<IncomingEvent>? OnEvent;

    public string? Failure { get; private set; }

    public void Start()
    {
        EventToken.LoadOrCreate();
        var http = new HttpListener();
        http.Prefixes.Add($"http://127.0.0.1:{port}/");
        try
        {
            http.Start();
        }
        catch (Exception ex)
        {
            Failure = ex.Message;
            http.Close();
            return;
        }
        listener = http;
        cancel = new CancellationTokenSource();
        var token = cancel.Token;
        _ = Task.Run(() => Loop(http, token));
    }

    public void Dispose()
    {
        cancel?.Cancel();
        listener?.Close();
        listener = null;
    }

    void Loop(HttpListener http, CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            HttpListenerContext context;
            try
            {
                context = http.GetContext();
            }
            catch
            {
                break;
            }
            try
            {
                Handle(context);
            }
            catch
            {
                TryStatus(context, 400);
            }
        }
    }

    void Handle(HttpListenerContext context)
    {
        var request = context.Request;
        var path = request.Url?.AbsolutePath ?? "";
        if (!string.Equals(request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase) || path != "/event")
        {
            TryStatus(context, 400);
            return;
        }
        if (request.ContentLength64 < 0 || request.ContentLength64 > 60_000)
        {
            TryStatus(context, 400);
            return;
        }
        using var reader = new StreamReader(request.InputStream, request.ContentEncoding ?? Encoding.UTF8);
        var body = reader.ReadToEnd();
        if (body.Length > 60_000)
        {
            TryStatus(context, 400);
            return;
        }
        var presented = request.Headers[EventEndpoint.Header] ?? "";
        if (!EventToken.Accepts(presented))
        {
            TryStatus(context, 401);
            return;
        }
        IncomingEvent? incoming;
        try
        {
            incoming = JsonSerializer.Deserialize<IncomingEvent>(body, JsonOptions);
        }
        catch
        {
            TryStatus(context, 401);
            return;
        }
        if (incoming == null)
        {
            TryStatus(context, 401);
            return;
        }
        TryStatus(context, 204);
        OnEvent?.Invoke(incoming);
    }

    static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    static void TryStatus(HttpListenerContext context, int status)
    {
        try
        {
            context.Response.StatusCode = status;
            context.Response.ContentLength64 = 0;
            context.Response.Close();
        }
        catch
        {
            // 상대가 이미 끊었다.
        }
    }
}
