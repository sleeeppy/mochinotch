import AppKit
import SwiftUI

/// 펼친 노치 안의 설정. 노치 패널은 키 창이 되지 않아 시스템 스위치가 늘 비활성 회색으로 그려진다. 컨트롤은 직접 그린다.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var openMenu: SettingsMenu?

    var body: some View {
        VStack(spacing: 10) {
            SettingsCard {
                SwitchRow(
                    title: model.text(.launchTitle),
                    subtitle: model.text(.launchSubtitle),
                    isOn: model.launchAtLogin
                ) {
                    model.setLaunchAtLogin(!model.launchAtLogin)
                }
                if let launchAtLoginError = model.launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.system(size: 11))
                        .foregroundStyle(IslandColor.danger)
                        .padding(.horizontal, SettingsLayout.horizontal)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                SettingsDivider()
                SettingsRow(
                    title: model.text(.introTitle),
                    subtitle: model.pendingIntroPreview == nil ? model.text(.introIdle) : model.text(.introPreview)
                ) {
                    MenuDropdown(title: model.introStudy.title(in: model.language), open: openMenu == .intro) {
                        toggle(.intro)
                    }
                    .anchorPreference(key: IntroAnchorKey.self, value: .bounds) { $0 }
                }
                SettingsDivider()
                SwitchRow(
                    title: model.text(.effectTitle),
                    subtitle: model.playsScreenEffect ? model.text(.effectOn) : model.text(.effectOff),
                    isOn: model.playsScreenEffect
                ) {
                    model.setPlaysScreenEffect(!model.playsScreenEffect)
                }
                SettingsDivider()
                SwitchRow(
                    title: model.text(.shelfSideTitle),
                    subtitle: model.shelfOnLeft ? model.text(.shelfSideOn) : model.text(.shelfSideOff),
                    isOn: model.shelfOnLeft
                ) {
                    model.setShelfOnLeft(!model.shelfOnLeft)
                }
                SettingsDivider()
                SettingsRow(
                    title: model.text(.languageTitle),
                    subtitle: model.text(.languageSubtitle)
                ) {
                    MenuDropdown(title: model.language.nativeName, open: openMenu == .language) {
                        toggle(.language)
                    }
                    .anchorPreference(key: LanguageAnchorKey.self, value: .bounds) { $0 }
                }
                SettingsDivider()
                ActionRow(
                    title: model.text(.permissionsTitle),
                    subtitle: model.setupStatus.remaining == 0
                        ? model.text(.permissionsReady)
                        : model.text(.permissionsLeft, model.setupStatus.remaining),
                    highlighted: model.setupStatus.remaining > 0
                ) {
                    model.openSetup()
                }
            }

            HStack(spacing: 8) {
                Text(verbatim: "v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.36))
                if model.updateAvailable {
                    UpdateButton(progress: model.updateProgress) {
                        model.openUpdate()
                    }
                } else {
                    CheckUpdateButton(status: model.updateCheckStatus) {
                        model.checkForUpdateNow()
                    }
                }
                Button {
                    model.openGuide()
                } label: {
                    LanguageCrossfade(model.text(.guide)) { value in
                        Text(value)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .underline()
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                QuitButton()
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: SettingsHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(SettingsHeightKey.self) { height in
            model.setSettingsHeight(height)
        }
        .overlayPreferenceValue(IntroAnchorKey.self) { anchor in
            menuLayer(.intro, anchor: anchor, width: IntroMenu.width)
        }
        .overlayPreferenceValue(LanguageAnchorKey.self) { anchor in
            menuLayer(.language, anchor: anchor, width: LanguageMenu.width, upward: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func toggle(_ menu: SettingsMenu) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            openMenu = openMenu == menu ? nil : menu
        }
    }

    private func closeMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            openMenu = nil
        }
    }

    /// 목록만 덮는다. 설정 화면 전체를 다시 넣으면 같은 화면이 끝없이 겹쳐 앱이 꺼진다.
    /// `upward`면 버튼 위로 연다. 언어 목록은 아래에 두면 노치 바닥에서 잘린다.
    private func menuLayer(_ menu: SettingsMenu, anchor: Anchor<CGRect>?, width: CGFloat, upward: Bool = false) -> some View {
        GeometryReader { proxy in
            if openMenu == menu, let anchor {
                let button = proxy[anchor]
                let y = upward ? button.minY - menuHeight(menu) - 6 : button.maxY + 6
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .onTapGesture { closeMenu() }
                    Group {
                        switch menu {
                        case .intro: IntroMenu { closeMenu() }
                        case .language: LanguageMenu { closeMenu() }
                        }
                    }
                    .frame(width: width)
                    .offset(x: button.maxX - width, y: y)
                    .transition(
                        .scale(scale: 0.9, anchor: upward ? .bottomTrailing : .topTrailing)
                            .combined(with: .opacity)
                    )
                }
            }
        }
        .allowsHitTesting(openMenu == menu)
    }

    private func menuHeight(_ menu: SettingsMenu) -> CGFloat {
        switch menu {
        case .intro: return IntroMenu.height
        case .language: return LanguageMenu.height
        }
    }
}

private enum SettingsMenu {
    case intro
    case language
}

enum SettingsLayout {
    static let horizontal: CGFloat = 14
}

/// 이전 글자와 새 글자를 겹쳐 두고 투명도만 바꾼다. 자리는 움직이지 않는다.
private struct LanguageCrossfade<Label: View>: View {
    var text: String
    @ViewBuilder var label: (String) -> Label
    @State private var front: String
    @State private var back: String
    @State private var showFront = true

    init(_ text: String, @ViewBuilder label: @escaping (String) -> Label) {
        self.text = text
        self.label = label
        _front = State(initialValue: text)
        _back = State(initialValue: text)
    }

    var body: some View {
        // 크기는 지금 글자만 잡는다. 숨은 이전 글자까지 포함하면 업데이트 버튼이 벌어지고 아이콘이 떨어진다.
        label(text)
            .opacity(0)
            .overlay(alignment: .leading) {
                ZStack(alignment: .leading) {
                    label(front).opacity(showFront ? 1 : 0)
                    label(back).opacity(showFront ? 0 : 1)
                }
                .fixedSize()
            }
            .animation(.easeInOut(duration: 0.2), value: showFront)
            .animation(.easeInOut(duration: 0.2), value: text)
        .onChange(of: text) { _, new in
            let visible = showFront ? front : back
            guard new != visible else { return }
            if showFront {
                back = new
            } else {
                front = new
            }
            showFront.toggle()
        }
    }
}

struct SettingsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct IntroAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct LanguageAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, SettingsLayout.horizontal)
    }
}

struct SettingsRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                LanguageCrossfade(title) { value in
                    Text(value)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(IslandColor.primary)
                        .lineLimit(1)
                }
                if let subtitle {
                    LanguageCrossfade(subtitle) { value in
                        Text(value)
                            .font(.system(size: 11))
                            .foregroundStyle(IslandColor.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, SettingsLayout.horizontal)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 줄 전체가 스위치다.
private struct SwitchRow: View {
    var title: String
    var subtitle: String
    var isOn: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            SettingsRow(title: title, subtitle: subtitle) {
                IslandSwitch(isOn: isOn)
            }
            .background(Color.white.opacity(hovered ? 0.04 : 0))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { hovered = hovering }
        }
    }
}

private struct ActionRow: View {
    @Environment(AppModel.self) private var model
    var title: String
    var subtitle: String
    var highlighted = true
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        let tint = highlighted ? IslandColor.warning : IslandColor.secondary
        Button(action: action) {
            SettingsRow(title: title, subtitle: subtitle) {
                LanguageCrossfade(model.text(.open)) { value in
                    Text(value)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tint.opacity(hovered ? 0.24 : 0.15)))
            }
            .background(Color.white.opacity(hovered ? 0.04 : 0))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { hovered = hovering }
        }
    }
}

private struct IslandSwitch: View {
    var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? IslandColor.charge : Color.white.opacity(0.16))
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                .padding(2)
        }
        .frame(width: 36, height: 21)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isOn)
    }
}

/// 누르면 설정 화면 위에 목록이 뜬다. 시스템 메뉴는 밝은 화면 모드에서 검은 판 위에 하얗게 떠서 쓰지 않는다.
private struct MenuDropdown: View {
    var title: String
    var open: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                LanguageCrossfade(title) { value in
                    Text(value)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IslandColor.primary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(IslandColor.secondary)
            }
            .padding(.leading, 11)
            .padding(.trailing, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(open || hovered ? 0.14 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { hovered = hovering }
        }
    }
}

private struct IntroMenu: View {
    static let width: CGFloat = 132
    /// 여백 8, 줄 2개, 줄 사이 2.
    static let height: CGFloat = 8 + 28 * 2 + 2
    @Environment(AppModel.self) private var model
    var onPick: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(IntroStudy.allCases, id: \.self) { study in
                MenuPick(title: study.title(in: model.language), selected: model.introStudy == study) {
                    model.setIntro(study)
                    onPick()
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.15))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct LanguageMenu: View {
    static let width: CGFloat = 132
    /// 여백 8, 줄 4개, 줄 사이 2가 세 번.
    static let height: CGFloat = 8 + 28 * 4 + 2 * 3
    @Environment(AppModel.self) private var model
    var onPick: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(AppLanguage.allCases) { language in
                MenuPick(title: language.nativeName, selected: model.language == language) {
                    model.setLanguage(language)
                    onPick()
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.15))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct MenuPick: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .opacity(selected ? 1 : 0)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(IslandColor.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.1 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// 받는 동안은 캡슐이 진행만큼 차오른다.
private struct UpdateButton: View {
    @Environment(AppModel.self) private var model
    var progress: Double?
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if progress == nil {
                    LanguageCrossfade(label) { value in
                        Text(value)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(IslandColor.update)
                    }
                } else {
                    Text(label)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(IslandColor.update)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.25), value: label)
                }
            }
                .frame(minWidth: 40)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(IslandColor.update.opacity(hovered && progress == nil ? 0.28 : 0.16))
                            if let progress {
                                Capsule()
                                    .fill(IslandColor.update.opacity(0.3))
                                    .frame(width: max(proxy.size.height, proxy.size.width * min(progress, 1)))
                                    .animation(.easeOut(duration: 0.2), value: progress)
                            }
                        }
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(progress != nil)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { hovered = hovering }
        }
    }

    private var label: String {
        guard let progress else { return model.text(.update) }
        return progress < 1 ? "\(Int(progress * 100))%" : model.text(.installing)
    }
}

/// 새 버전이 없을 때 그 자리에 있는 확인 버튼. 보는 동안 화살표가 돌고, 결과를 잠깐 보여 주고 돌아온다.
private struct CheckUpdateButton: View {
    @Environment(AppModel.self) private var model
    var status: AppModel.UpdateCheckStatus?
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        let lit = hovered && status == nil
        Button(action: action) {
            HStack(spacing: 4) {
                LanguageCrossfade(label) { value in
                    Text(value)
                        .font(.system(size: 10.5, weight: .medium))
                        .offset(x: 0.5, y: 0.5)
                }
                icon
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 11, height: 11)
            }
            .foregroundStyle(Color.white.opacity(lit ? 0.8 : 0.68))
            // 둥근 아이콘은 글자보다 가장자리가 비어 보여서 오른쪽을 덜 띄운다.
            .padding(.leading, 9)
            .padding(.trailing, 7.5)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(Color.white.opacity(lit ? 0.11 : 0.075)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5))
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: status)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(status != nil)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { hovered = hovering }
        }
    }

    private var icon: some View {
        ZStack {
            switch status {
            case .checking:
                TimelineView(.animation) { context in
                    Image(systemName: "arrow.counterclockwise")
                        .rotationEffect(.degrees(-(context.date.timeIntervalSinceReferenceDate * 400).truncatingRemainder(dividingBy: 360)))
                }
                .transition(.opacity)
            case .current:
                Image(systemName: "checkmark")
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            case .failed:
                Image(systemName: "exclamationmark")
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            case nil:
                Image(systemName: "arrow.counterclockwise")
                    .transition(.opacity)
            }
        }
    }

    private var label: String {
        switch status {
        case nil: model.text(.update)
        case .checking: model.text(.checking)
        case .current: model.text(.latest)
        case .failed: model.text(.checkFailed)
        }
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct QuitButton: View {
    @Environment(AppModel.self) private var model
    @State private var hovered = false

    var body: some View {
        Button {
            model.quit()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "power")
                    .font(.system(size: 9.5, weight: .bold))
                LanguageCrossfade(model.text(.quit)) { value in
                    Text(value)
                        .font(.system(size: 11.5, weight: .semibold))
                }
            }
            .foregroundStyle(IslandColor.danger)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(IslandColor.danger.opacity(hovered ? 0.26 : 0.16)))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { hovered = hovering }
        }
    }
}
