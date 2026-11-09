using System.Text.Json;

namespace Mochinotch.Win;

public sealed class AgentNote
{
    public Guid Id { get; } = Guid.NewGuid();
    public string? Dedupe { get; init; }
    public AgentTool Tool { get; init; }
    public AgentOutcome Outcome { get; init; }
    public string Title { get; init; } = "";
    public string Detail { get; init; } = "";
    public DateTime Created { get; init; } = DateTime.Now;
    public double Arrived { get; init; }
    /// <summary>null이면 직접 확인할 때까지 오버레이에 둔다.</summary>
    public double? Until { get; init; }
    /// <summary>그 탭을 앞으로 가져와 완료를 확인했다.</summary>
    public bool Checked { get; set; }
    /// <summary>알림이 왔을 때 그 에이전트 창이 이미 앞에 있었다.</summary>
    public bool AlreadyFocused { get; init; }
    public bool HidesPeek { get; set; }
    public bool StaysOnLeft => AgentPalette.PlaysEdge(Tool) && Outcome != AgentOutcome.Cancelled;

    public bool OnOverlay(double now) => !Checked && (Until == null || Until > now);
}

public sealed class IslandSettings
{
    public bool Edge { get; set; } = true;
    public string Language { get; set; } = Copy.Code(Copy.Detect());

    public static string PathName { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Mochinotch",
        "windows.json");

    public static IslandSettings Load()
    {
        try
        {
            if (!File.Exists(PathName)) return new IslandSettings();
            return JsonSerializer.Deserialize<IslandSettings>(File.ReadAllText(PathName)) ?? new IslandSettings();
        }
        catch
        {
            return new IslandSettings();
        }
    }

    public void Save()
    {
        var directory = Path.GetDirectoryName(PathName)!;
        Directory.CreateDirectory(directory);
        File.WriteAllText(PathName, JsonSerializer.Serialize(this));
    }
}

/// <summary>
/// 에이전트 알림만 다룬다. 다른 앱의 시스템 알림은 받지 않는다.
/// </summary>
public sealed class IslandModel
{
    readonly bool persist;
    readonly List<AgentNote> notes = [];
    readonly Dictionary<string, double> recent = [];
    IslandMetrics from;
    IslandMetrics goal;
    double springStart;
    double springResponse = 0.46;
    double springDamping = 0.74;
    bool springing;
    bool hovering;
    double? hoverSince;
    double? leaveSince;
    bool edgePlaying;
    double edgeStart;
    double boingStart = double.NegativeInfinity;
    double shakeStart = double.NegativeInfinity;
    double nextFocus;
    AgentTool? latchedForeground;
    bool foregroundLatched;
    AgentNote? featured;

    public IslandModel(bool persist = true)
    {
        this.persist = persist;
        var stored = persist ? IslandSettings.Load() : new IslandSettings();
        EdgeEnabled = stored.Edge;
        Language = Copy.Parse(stored.Language);
        LaunchAtLogin = LoginStart.Enabled;
        goal = IslandMetrics.Resolve(Presentation.Idle, 0, 0, false);
        from = goal;
        Shown = goal;
        if (persist) RefreshLinks();
    }

    public int Revision { get; private set; } = 1;
    public Presentation Presentation { get; private set; } = Presentation.Idle;
    public bool ShowSettings { get; private set; }
    public bool EdgeEnabled { get; private set; } = true;
    public bool LaunchAtLogin { get; private set; }
    public Lang Language { get; private set; }
    public IslandMetrics Shown { get; private set; }
    public IslandMetrics Goal => goal;
    public string LinkMessage { get; private set; } = "";
    public bool Connecting { get; private set; }
    public IReadOnlyList<ToolLink> Links { get; private set; } = [];
    public IReadOnlyList<AgentNote> Notes => notes;
    public AgentNote? Featured => featured;
    public bool EdgeVisible { get; private set; }
    public double EdgeSeconds { get; private set; }
    public double EdgeWindowOpacity { get; private set; }
    public double EdgeStrength { get; private set; }
    public Rgb EdgeTint { get; private set; } = Rgb.White;
    public double EdgeRim { get; private set; } = 1;
    public double GlowEnvelope { get; private set; }
    public double GlowTravel { get; private set; }
    public Rgb GlowColor { get; private set; } = Rgb.White;
    public double StretchY { get; private set; } = 1;
    public double ShakeX { get; private set; }
    public string? ServerFailure { get; set; }

    /// <summary>확인 요청과 완료만 화면 위에 띄운다. 확인이 완료보다 앞이다.</summary>
    public IReadOnlyList<AgentNote> Toasts(double now)
        => notes.Where(note => note.OnOverlay(now) && note.Outcome is AgentOutcome.Completed or AgentOutcome.NeedsInput)
            .OrderBy(note => note.Outcome == AgentOutcome.NeedsInput ? 0 : 1)
            .ThenByDescending(note => note.Arrived)
            .Take(2)
            .ToList();

    public IReadOnlyList<AgentNote> LeftIcons()
    {
        var groups = new List<AgentNote>();
        foreach (var note in notes.Where(item => item.StaysOnLeft && !item.HidesPeek).Reverse())
        {
            var index = groups.FindIndex(item => item.Tool == note.Tool);
            if (index >= 0) groups[index] = note;
            else groups.Add(note);
        }
        if (groups.Count > IslandMetrics.MaxAgents)
            groups = groups.GetRange(groups.Count - IslandMetrics.MaxAgents, IslandMetrics.MaxAgents);
        return groups;
    }

    public void Ingest(IncomingEvent incoming, double now)
    {
        if (string.Equals(incoming.Kind, "update", StringComparison.OrdinalIgnoreCase))
            return;
        var tool = AgentPalette.Parse(incoming.Tool);
        if (string.Equals(incoming.Kind, "resolved", StringComparison.OrdinalIgnoreCase))
        {
            ResolveWaiting(tool, now);
            return;
        }
        var outcome = AgentPalette.ParseOutcome(incoming.Kind, incoming.Success);
        var title = NonEmpty(incoming.Title) ?? $"{AgentPalette.DisplayName(tool)} {Copy.Short(outcome, Language)}";
        var detail = incoming.Detail?.Trim() ?? "";
        foreach (var key in recent.Where(pair => pair.Value <= now).Select(pair => pair.Key).ToList())
            recent.Remove(key);
        var dedupe = NonEmpty(incoming.Id) ?? $"{AgentPalette.Wire(tool)}|{incoming.Kind}|{title}|{detail}";
        if (recent.ContainsKey(dedupe)) return;
        recent[dedupe] = now + (string.IsNullOrEmpty(incoming.Id) ? 2 : 60);
        if (outcome != AgentOutcome.NeedsInput)
            RemoveWaiting(tool, keepToasts: true);
        var seconds = outcome switch
        {
            AgentOutcome.NeedsInput or AgentOutcome.Completed => (double?)null,
            AgentOutcome.Failed => 6.2,
            AgentOutcome.Cancelled => 3.2,
            _ => 5.4,
        };
        var note = new AgentNote
        {
            Dedupe = incoming.Id,
            Tool = tool,
            Outcome = outcome,
            Title = title,
            Detail = detail,
            Arrived = now,
            Until = seconds is { } stay ? now + stay : null,
            AlreadyFocused = ForegroundAgent.Current() == tool,
        };
        notes.Insert(0, note);
        if (notes.Count > 30) notes.RemoveRange(30, notes.Count - 30);
        featured = note;
        if (outcome == AgentOutcome.Completed && AgentPalette.PlaysEdge(tool))
        {
            StartEdge(tool, outcome, now);
            boingStart = now;
        }
        if (hovering || ShowSettings)
            SetPresentation(Presentation.Expanded, now);
        else
            SetPresentation(Presentation.Idle, now);
        Revision++;
    }

    public void SetPointer(bool inside, double now)
    {
        if (inside)
        {
            hovering = true;
            leaveSince = null;
            hoverSince ??= now;
        }
        else
        {
            hovering = false;
            hoverSince = null;
            leaveSince ??= now;
        }
    }

    public void ToggleSettings(double now)
    {
        ShowSettings = !ShowSettings;
        if (ShowSettings) SetPresentation(Presentation.Expanded, now);
        Revision++;
        Retarget(now);
    }

    public void CloseSettings(double now)
    {
        if (!ShowSettings) return;
        ShowSettings = false;
        Revision++;
        Retarget(now);
    }

    public void Clear(double now)
    {
        notes.Clear();
        featured = null;
        ShowSettings = false;
        if (!hovering) SetPresentation(Presentation.Idle, now);
        Revision++;
    }

    public void ToggleEdge()
    {
        EdgeEnabled = !EdgeEnabled;
        Save();
        Revision++;
    }

    public void ToggleLaunch()
    {
        if (!LoginStart.Supported) return;
        LaunchAtLogin = !LaunchAtLogin;
        var exe = Environment.ProcessPath ?? "";
        if (exe.Length > 0) LoginStart.Set(LaunchAtLogin, exe);
        Revision++;
    }

    public void SetLanguage(Lang lang)
    {
        if (Language == lang) return;
        Language = lang;
        Save();
        Revision++;
    }

    public void Activate(AgentNote note, double now)
    {
        ForegroundAgent.Focus(note.Tool);
        NoteForeground(note.Tool, now);
    }

    public void NoteForeground(AgentTool? tool, double now)
    {
        if (tool == null) return;
        var changed = false;
        foreach (var note in notes)
        {
            if (note.Tool != tool) continue;
            if (note.Outcome is AgentOutcome.Completed or AgentOutcome.NeedsInput && !note.Checked)
            {
                note.Checked = true;
                changed = true;
            }
            if (note.HidesPeek || !note.StaysOnLeft) continue;
            note.HidesPeek = true;
            changed = true;
        }
        if (featured?.Tool == tool && featured.Outcome != AgentOutcome.NeedsInput && !hovering && !ShowSettings)
        {
            SetPresentation(Presentation.Idle, now);
            changed = true;
        }
        if (changed) Revision++;
    }

    public void Connect(double now)
    {
        _ = now;
        if (!OperatingSystem.IsWindows())
        {
            LinkMessage = Copy.Get(Phrase.WindowsOnly, Language);
            Revision++;
            return;
        }
        var exe = Environment.ProcessPath ?? "";
        if (exe.Length == 0)
        {
            LinkMessage = Copy.Get(Phrase.WindowsOnly, Language);
            Revision++;
            return;
        }
        Connecting = true;
        Revision++;
        var present = ScanPresent();
        var result = HookInstaller.Install(HookInstaller.Home, exe, present);
        Connecting = false;
        RefreshLinks();
        if (result.Failures.Count > 0)
            LinkMessage = result.Failures[0].Problem;
        else if (result.Changed.Count == 0)
            LinkMessage = Copy.Get(Phrase.Already, Language);
        else
        {
            var names = string.Join(", ", result.Changed.Select(Name));
            LinkMessage = Copy.Get(Phrase.Linked, Language) + "\n" + Copy.Format(Phrase.Restart, Language, names);
        }
        Revision++;
    }

    public void Tick(double now)
    {
        if (hovering && hoverSince is { } entered && now - entered >= 0.16 && Presentation != Presentation.Expanded)
        {
            SetPresentation(Presentation.Expanded, now);
            Revision++;
        }
        if (!hovering && leaveSince is { } left && now - left >= 0.22)
        {
            leaveSince = null;
            Collapse(now);
            Revision++;
        }
        StepSpring(now);
        StepEdge(now);
        StepSquash(now);
        if (OperatingSystem.IsWindows() && now >= nextFocus)
        {
            nextFocus = now + 0.4;
            var current = ForegroundAgent.Current();
            if (!foregroundLatched)
            {
                foregroundLatched = true;
                latchedForeground = current;
            }
            else if (current != latchedForeground)
            {
                latchedForeground = current;
                NoteForeground(current, now);
            }
        }
    }

    public void RefreshLinks()
    {
        Links = HookInstaller.Scan();
    }

    void Collapse(double now)
    {
        if (ShowSettings)
        {
            ShowSettings = false;
            Retarget(now);
        }
        SetPresentation(Presentation.Idle, now);
    }

    void ResolveWaiting(AgentTool tool, double now)
    {
        var was = featured?.Tool == tool && featured.Outcome == AgentOutcome.NeedsInput;
        if (!RemoveWaiting(tool, keepToasts: false)) return;
        if (was && !hovering && !ShowSettings)
            SetPresentation(Presentation.Idle, now);
        Revision++;
    }

    /// <param name="keepToasts">알림 센터에 아직 떠 있는 확인은 작업이 끝나도 남긴다.</param>
    bool RemoveWaiting(AgentTool tool, bool keepToasts)
    {
        var removed = notes.RemoveAll(note =>
            note.Tool == tool
            && note.Outcome == AgentOutcome.NeedsInput
            && !(keepToasts && note.Dedupe != null && note.Dedupe.StartsWith("toast:", StringComparison.Ordinal)));
        if (removed > 0 && featured?.Tool == tool && featured.Outcome == AgentOutcome.NeedsInput)
            featured = notes.FirstOrDefault();
        return removed > 0;
    }

    void StartEdge(AgentTool tool, AgentOutcome outcome, double now)
    {
        edgePlaying = true;
        edgeStart = now;
        EdgeTint = AgentPalette.EdgeTint(tool, outcome);
        EdgeRim = AgentPalette.Rim(tool, outcome);
        GlowColor = EdgeTint.Lift(0.42);
        EdgeVisible = EdgeEnabled;
        EdgeSeconds = 0;
    }

    void StepEdge(double now)
    {
        if (!edgePlaying)
        {
            EdgeVisible = false;
            EdgeSeconds = 0;
            EdgeWindowOpacity = 0;
            EdgeStrength = 0;
            GlowEnvelope = 0;
            GlowTravel = 0;
            return;
        }
        var seconds = now - edgeStart;
        if (seconds >= EdgeMotion.Duration)
        {
            edgePlaying = false;
            EdgeVisible = false;
            GlowEnvelope = 0;
            GlowTravel = 0;
            return;
        }
        EdgeSeconds = seconds;
        EdgeWindowOpacity = EdgeMotion.WindowOpacity(seconds);
        EdgeStrength = EdgeMotion.Strength(seconds);
        GlowEnvelope = EdgeMotion.Level(seconds);
        GlowTravel = EdgeMotion.Travel(seconds);
        EdgeVisible = EdgeEnabled;
    }

    void StepSquash(double now)
    {
        StretchY = Sample(now - boingStart, (0, 1), (0.08, 1), (0.25, 1.2), (0.45, 1), (0.60, 1.065), (0.82, 1));
        ShakeX = Sample(now - shakeStart, (0, 0), (0.08, 7), (0.16, -6), (0.23, 4), (0.35, 0));
    }

    static double Sample(double t, params (double At, double Value)[] keys)
    {
        if (t < 0 || t >= keys[^1].At) return t < 0 ? keys[0].Value : keys[^1].Value;
        for (var index = 1; index < keys.Length; index++)
        {
            if (t > keys[index].At) continue;
            var from = keys[index - 1];
            var to = keys[index];
            var span = to.At - from.At;
            var p = span <= 0 ? 1 : (t - from.At) / span;
            return from.Value + (to.Value - from.Value) * p;
        }
        return keys[^1].Value;
    }

    void SetPresentation(Presentation presentation, double now)
    {
        if (Presentation == presentation && presentation != Presentation.Expanded)
        {
            Retarget(now);
            return;
        }
        Presentation = presentation;
        Retarget(now);
    }

    void Retarget(double now)
    {
        var rows = Math.Max(notes.Count, 1);
        var next = IslandMetrics.Resolve(Presentation, LeftIcons().Count, rows, ShowSettings);
        if (Near(Shown, next))
        {
            Shown = next;
            goal = next;
            from = next;
            springing = false;
            return;
        }
        from = Shown;
        goal = next;
        springStart = now;
        var shrinking = next.Height + 4 < Shown.Height || next.Width + 8 < Shown.Width;
        springResponse = 0.46;
        springDamping = shrinking ? 1 : 0.74;
        springing = true;
    }

    void StepSpring(double now)
    {
        if (!springing) return;
        var t = now - springStart;
        var p = EdgeMotion.Spring(t, springResponse, springDamping);
        if (t > 0.95 || p >= 0.997)
        {
            Shown = goal;
            springing = false;
            return;
        }
        Shown = IslandMetrics.Lerp(from, goal, Math.Clamp(p, 0, 1));
    }

    static bool Near(IslandMetrics left, IslandMetrics right)
        => Math.Abs(left.Width - right.Width) < 0.4
           && Math.Abs(left.Height - right.Height) < 0.4
           && Math.Abs(left.Shift - right.Shift) < 0.4;

    void Save()
    {
        if (!persist) return;
        var stored = new IslandSettings
        {
            Edge = EdgeEnabled,
            Language = Copy.Code(Language),
        };
        stored.Save();
    }

    List<HookTool> ScanPresent()
        => HookInstaller.Scan().Where(link => link.Present).Select(link => link.Tool).ToList();

    static string Name(HookTool tool) => tool switch
    {
        HookTool.Claude => "Claude Code",
        HookTool.Cursor => "Cursor",
        HookTool.Codex => "Codex",
        HookTool.Kiro => "Kiro",
        _ => "",
    };

    static string? NonEmpty(string? text)
    {
        var trimmed = text?.Trim();
        return string.IsNullOrEmpty(trimmed) ? null : trimmed;
    }
}
