using System.Globalization;

namespace Mochinotch.Win;

public enum Lang
{
    Ko,
    Ja,
    En,
    Zh,
}

public enum Phrase
{
    QuietTitle,
    QuietBody,
    Done,
    Failed,
    Confirm,
    Stopped,
    TaskDone,
    TaskFailed,
    TaskConfirm,
    TaskStopped,
    Agents,
    Settings,
    Clear,
    Close,
    Quit,
    Effect,
    EffectOn,
    EffectOff,
    Connect,
    Connected,
    Missing,
    Restart,
    Linked,
    Already,
    Connecting,
    WindowsOnly,
    JustNow,
    Minutes,
    Hours,
    Launch,
    Language,
    OverlayHint,
    UpdateReady,
    Updating,
}

public static class Copy
{
    static readonly Dictionary<(Phrase, Lang), string> Map = new()
    {
        [(Phrase.QuietTitle, Lang.Ko)] = "지금은 조용해요",
        [(Phrase.QuietTitle, Lang.Ja)] = "今は静かです",
        [(Phrase.QuietTitle, Lang.En)] = "All quiet",
        [(Phrase.QuietTitle, Lang.Zh)] = "现在很安静",
        [(Phrase.QuietBody, Lang.Ko)] = "작업 완료가 여기 쌓여요.",
        [(Phrase.QuietBody, Lang.Ja)] = "作業完了がここに残ります。",
        [(Phrase.QuietBody, Lang.En)] = "Finished work collects here.",
        [(Phrase.QuietBody, Lang.Zh)] = "完成的工作会留在这里。",
        [(Phrase.Done, Lang.Ko)] = "완료",
        [(Phrase.Done, Lang.Ja)] = "完了",
        [(Phrase.Done, Lang.En)] = "Done",
        [(Phrase.Done, Lang.Zh)] = "完成",
        [(Phrase.Failed, Lang.Ko)] = "실패",
        [(Phrase.Failed, Lang.Ja)] = "失敗",
        [(Phrase.Failed, Lang.En)] = "Failed",
        [(Phrase.Failed, Lang.Zh)] = "失败",
        [(Phrase.Confirm, Lang.Ko)] = "확인",
        [(Phrase.Confirm, Lang.Ja)] = "確認",
        [(Phrase.Confirm, Lang.En)] = "Confirm",
        [(Phrase.Confirm, Lang.Zh)] = "确认",
        [(Phrase.Stopped, Lang.Ko)] = "중단",
        [(Phrase.Stopped, Lang.Ja)] = "中断",
        [(Phrase.Stopped, Lang.En)] = "Stopped",
        [(Phrase.Stopped, Lang.Zh)] = "停止",
        [(Phrase.TaskDone, Lang.Ko)] = "작업 완료",
        [(Phrase.TaskDone, Lang.Ja)] = "作業完了",
        [(Phrase.TaskDone, Lang.En)] = "Work finished",
        [(Phrase.TaskDone, Lang.Zh)] = "工作完成",
        [(Phrase.TaskFailed, Lang.Ko)] = "작업 실패",
        [(Phrase.TaskFailed, Lang.Ja)] = "作業失敗",
        [(Phrase.TaskFailed, Lang.En)] = "Work failed",
        [(Phrase.TaskFailed, Lang.Zh)] = "工作失败",
        [(Phrase.TaskConfirm, Lang.Ko)] = "확인 필요",
        [(Phrase.TaskConfirm, Lang.Ja)] = "確認が必要",
        [(Phrase.TaskConfirm, Lang.En)] = "Needs you",
        [(Phrase.TaskConfirm, Lang.Zh)] = "需要确认",
        [(Phrase.TaskStopped, Lang.Ko)] = "작업 중단",
        [(Phrase.TaskStopped, Lang.Ja)] = "作業中断",
        [(Phrase.TaskStopped, Lang.En)] = "Work stopped",
        [(Phrase.TaskStopped, Lang.Zh)] = "工作已停止",
        [(Phrase.Agents, Lang.Ko)] = "에이전트",
        [(Phrase.Agents, Lang.Ja)] = "エージェント",
        [(Phrase.Agents, Lang.En)] = "Agents",
        [(Phrase.Agents, Lang.Zh)] = "代理",
        [(Phrase.Settings, Lang.Ko)] = "설정",
        [(Phrase.Settings, Lang.Ja)] = "設定",
        [(Phrase.Settings, Lang.En)] = "Settings",
        [(Phrase.Settings, Lang.Zh)] = "设置",
        [(Phrase.Clear, Lang.Ko)] = "지우기",
        [(Phrase.Clear, Lang.Ja)] = "消去",
        [(Phrase.Clear, Lang.En)] = "Clear",
        [(Phrase.Clear, Lang.Zh)] = "清除",
        [(Phrase.Close, Lang.Ko)] = "닫기",
        [(Phrase.Close, Lang.Ja)] = "閉じる",
        [(Phrase.Close, Lang.En)] = "Close",
        [(Phrase.Close, Lang.Zh)] = "关闭",
        [(Phrase.Quit, Lang.Ko)] = "종료",
        [(Phrase.Quit, Lang.Ja)] = "終了",
        [(Phrase.Quit, Lang.En)] = "Quit",
        [(Phrase.Quit, Lang.Zh)] = "退出",
        [(Phrase.Effect, Lang.Ko)] = "화면 가장자리 연출",
        [(Phrase.Effect, Lang.Ja)] = "画面の縁の演出",
        [(Phrase.Effect, Lang.En)] = "Screen-edge glow",
        [(Phrase.Effect, Lang.Zh)] = "屏幕边缘光效",
        [(Phrase.EffectOn, Lang.Ko)] = "화면 가장자리까지 빛나요",
        [(Phrase.EffectOn, Lang.Ja)] = "画面の縁まで光ります",
        [(Phrase.EffectOn, Lang.En)] = "Glow reaches the screen edge",
        [(Phrase.EffectOn, Lang.Zh)] = "光会亮到屏幕边缘",
        [(Phrase.EffectOff, Lang.Ko)] = "화면은 그대로 둬요",
        [(Phrase.EffectOff, Lang.Ja)] = "画面はそのままです",
        [(Phrase.EffectOff, Lang.En)] = "The screen stays still",
        [(Phrase.EffectOff, Lang.Zh)] = "屏幕保持原样",
        [(Phrase.Connect, Lang.Ko)] = "연결",
        [(Phrase.Connect, Lang.Ja)] = "接続",
        [(Phrase.Connect, Lang.En)] = "Connect",
        [(Phrase.Connect, Lang.Zh)] = "连接",
        [(Phrase.Connected, Lang.Ko)] = "{0} 연결됨",
        [(Phrase.Connected, Lang.Ja)] = "{0} 接続済み",
        [(Phrase.Connected, Lang.En)] = "{0} connected",
        [(Phrase.Connected, Lang.Zh)] = "已连接 {0}",
        [(Phrase.Missing, Lang.Ko)] = "Claude Code · Cursor · Codex · Kiro를 찾지 못했어요",
        [(Phrase.Missing, Lang.Ja)] = "Claude Code · Cursor · Codex · Kiro が見つかりません",
        [(Phrase.Missing, Lang.En)] = "Couldn’t find Claude Code, Cursor, Codex, or Kiro",
        [(Phrase.Missing, Lang.Zh)] = "没有找到 Claude Code、Cursor、Codex 或 Kiro",
        [(Phrase.Restart, Lang.Ko)] = "{0}는 직접 다시 켜 주세요",
        [(Phrase.Restart, Lang.Ja)] = "{0} は自分で起動し直してください",
        [(Phrase.Restart, Lang.En)] = "Relaunch {0} yourself",
        [(Phrase.Restart, Lang.Zh)] = "请手动重新打开 {0}",
        [(Phrase.Linked, Lang.Ko)] = "연결했어요",
        [(Phrase.Linked, Lang.Ja)] = "接続しました",
        [(Phrase.Linked, Lang.En)] = "Connected",
        [(Phrase.Linked, Lang.Zh)] = "已连接",
        [(Phrase.Already, Lang.Ko)] = "이미 연결돼 있어요",
        [(Phrase.Already, Lang.Ja)] = "すでに接続しています",
        [(Phrase.Already, Lang.En)] = "Already connected",
        [(Phrase.Already, Lang.Zh)] = "已经连接",
        [(Phrase.Connecting, Lang.Ko)] = "연결하는 중",
        [(Phrase.Connecting, Lang.Ja)] = "接続しています",
        [(Phrase.Connecting, Lang.En)] = "Connecting",
        [(Phrase.Connecting, Lang.Zh)] = "正在连接",
        [(Phrase.WindowsOnly, Lang.Ko)] = "연결은 Windows에서 적용돼요",
        [(Phrase.WindowsOnly, Lang.Ja)] = "接続は Windows で適用されます",
        [(Phrase.WindowsOnly, Lang.En)] = "Connecting applies on Windows",
        [(Phrase.WindowsOnly, Lang.Zh)] = "连接只会在 Windows 上写入",
        [(Phrase.JustNow, Lang.Ko)] = "방금",
        [(Phrase.JustNow, Lang.Ja)] = "たった今",
        [(Phrase.JustNow, Lang.En)] = "Just now",
        [(Phrase.JustNow, Lang.Zh)] = "刚刚",
        [(Phrase.Minutes, Lang.Ko)] = "{0}분",
        [(Phrase.Minutes, Lang.Ja)] = "{0}分",
        [(Phrase.Minutes, Lang.En)] = "{0}m",
        [(Phrase.Minutes, Lang.Zh)] = "{0}分钟",
        [(Phrase.Hours, Lang.Ko)] = "{0}시간",
        [(Phrase.Hours, Lang.Ja)] = "{0}時間",
        [(Phrase.Hours, Lang.En)] = "{0}h",
        [(Phrase.Hours, Lang.Zh)] = "{0}小时",
        [(Phrase.Launch, Lang.Ko)] = "로그인할 때 열기",
        [(Phrase.Launch, Lang.Ja)] = "ログイン時に開く",
        [(Phrase.Launch, Lang.En)] = "Open at login",
        [(Phrase.Launch, Lang.Zh)] = "登录时打开",
        [(Phrase.Language, Lang.Ko)] = "언어",
        [(Phrase.Language, Lang.Ja)] = "言語",
        [(Phrase.Language, Lang.En)] = "Language",
        [(Phrase.Language, Lang.Zh)] = "语言",
        [(Phrase.OverlayHint, Lang.Ko)] = "확인과 완료만 화면 위에 작게 떠요.",
        [(Phrase.OverlayHint, Lang.Ja)] = "確認と完了だけ、画面の上に小さく出ます。",
        [(Phrase.OverlayHint, Lang.En)] = "Confirms and finished work appear small at the top.",
        [(Phrase.OverlayHint, Lang.Zh)] = "只有确认和完成会在屏幕上方小幅出现。",
        [(Phrase.UpdateReady, Lang.Ko)] = "{0} 업데이트가 나왔어요",
        [(Phrase.UpdateReady, Lang.Ja)] = "{0} のアップデートがあります",
        [(Phrase.UpdateReady, Lang.En)] = "{0} is ready to install",
        [(Phrase.UpdateReady, Lang.Zh)] = "{0} 可以更新了",
        [(Phrase.Updating, Lang.Ko)] = "업데이트 받는 중",
        [(Phrase.Updating, Lang.Ja)] = "アップデートを受け取り中",
        [(Phrase.Updating, Lang.En)] = "Downloading update",
        [(Phrase.Updating, Lang.Zh)] = "正在下载更新",
    };

    public static Lang Detect()
    {
        var name = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
        return name switch
        {
            "ko" => Lang.Ko,
            "ja" => Lang.Ja,
            "zh" => Lang.Zh,
            _ => Lang.En,
        };
    }

    public static Lang Parse(string? raw) => raw switch
    {
        "ko" => Lang.Ko,
        "ja" => Lang.Ja,
        "en" => Lang.En,
        "zh" => Lang.Zh,
        _ => Detect(),
    };

    public static string Code(Lang lang) => lang switch
    {
        Lang.Ko => "ko",
        Lang.Ja => "ja",
        Lang.Zh => "zh",
        _ => "en",
    };

    public static string Native(Lang lang) => lang switch
    {
        Lang.Ko => "한국어",
        Lang.Ja => "日本語",
        Lang.Zh => "中文",
        _ => "English",
    };

    public static string Get(Phrase phrase, Lang lang)
    {
        if (Map.TryGetValue((phrase, lang), out var text)) return text;
        return Map[(phrase, Lang.Ko)];
    }

    public static string Format(Phrase phrase, Lang lang, params object[] args)
        => string.Format(Get(phrase, lang), args);

    public static string Short(AgentOutcome outcome, Lang lang) => outcome switch
    {
        AgentOutcome.Failed => Get(Phrase.Failed, lang),
        AgentOutcome.NeedsInput => Get(Phrase.Confirm, lang),
        AgentOutcome.Cancelled => Get(Phrase.Stopped, lang),
        _ => Get(Phrase.Done, lang),
    };

    public static string Detail(AgentOutcome outcome, Lang lang) => outcome switch
    {
        AgentOutcome.Failed => Get(Phrase.TaskFailed, lang),
        AgentOutcome.NeedsInput => Get(Phrase.TaskConfirm, lang),
        AgentOutcome.Cancelled => Get(Phrase.TaskStopped, lang),
        _ => Get(Phrase.TaskDone, lang),
    };

    public static string When(DateTime created, Lang lang, DateTime now)
    {
        var span = now - created;
        if (span.TotalSeconds < 45) return Get(Phrase.JustNow, lang);
        if (span.TotalMinutes < 60) return Format(Phrase.Minutes, lang, Math.Max(1, (int)span.TotalMinutes));
        if (span.TotalHours < 24) return Format(Phrase.Hours, lang, Math.Max(1, (int)span.TotalHours));
        return created.ToString("M/d", CultureInfo.CurrentCulture);
    }
}
