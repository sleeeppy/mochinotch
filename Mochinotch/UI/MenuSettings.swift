import AppKit
import SwiftUI

/// 펼친 노치 안의 설정. 노치 패널은 키 창이 되지 않아 시스템 스위치가 늘 비활성 회색으로 그려진다. 컨트롤은 직접 그린다.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var introMenuOpen = false

    var body: some View {
        VStack(spacing: 10) {
            SettingsCard {
                SwitchRow(
                    title: "로그인할 때 열기",
                    subtitle: "맥을 켜면 노치가 바로 깨어나요",
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
                    title: "인트로",
                    subtitle: model.pendingIntroPreview == nil ? "앱을 켤 때 노치 인사" : "노치에서 벗어나면 보여 줘요"
                ) {
                    IntroDropdown(open: $introMenuOpen)
                }
            }

            SettingsCard {
                SwitchRow(
                    title: "화면 가장자리 연출",
                    subtitle: model.playsScreenEffect ? "작업이 끝나면 화면 테두리까지 빛나요" : "노치 테두리만 빛나요",
                    isOn: model.playsScreenEffect
                ) {
                    model.setPlaysScreenEffect(!model.playsScreenEffect)
                }
                SettingsDivider()
                ActionRow(
                    title: "권한 · AI 연결",
                    subtitle: model.setupStatus.remaining == 0
                        ? "모두 준비됐어요"
                        : "\(model.setupStatus.remaining)개가 아직 꺼져 있어요",
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
                }
                Button {
                    model.openGuide()
                } label: {
                    Text("사용방법")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .underline()
                        .foregroundStyle(Color.white.opacity(0.5))
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
            GeometryReader { proxy in
                if introMenuOpen, let anchor {
                    let button = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.001)
                            .onTapGesture { closeMenu() }
                        IntroMenu { closeMenu() }
                            .frame(width: IntroMenu.width)
                            .offset(x: button.maxX - IntroMenu.width, y: button.maxY + 6)
                            .transition(
                                .scale(scale: 0.9, anchor: .topTrailing)
                                    .combined(with: .opacity)
                            )
                    }
                }
            }
            .allowsHitTesting(introMenuOpen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func closeMenu() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            introMenuOpen = false
        }
    }
}

enum SettingsLayout {
    static let horizontal: CGFloat = 14
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
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IslandColor.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(IslandColor.secondary)
                        .lineLimit(2)
                        .contentTransition(.opacity)
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
    var title: String
    var subtitle: String
    var highlighted = true
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        let tint = highlighted ? IslandColor.warning : IslandColor.secondary
        Button(action: action) {
            SettingsRow(title: title, subtitle: subtitle) {
                Text("열기")
                    .font(.system(size: 11.5, weight: .semibold))
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
private struct IntroDropdown: View {
    @Environment(AppModel.self) private var model
    @Binding var open: Bool
    @State private var hovered = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                open.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.introStudy.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IslandColor.primary)
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
        .anchorPreference(key: IntroAnchorKey.self, value: .bounds) { $0 }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { hovered = hovering }
        }
    }
}

private struct IntroMenu: View {
    static let width: CGFloat = 132
    @Environment(AppModel.self) private var model
    var onPick: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(IntroStudy.allCases, id: \.self) { study in
                IntroMenuItem(study: study, selected: model.introStudy == study) {
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

private struct IntroMenuItem: View {
    var study: IntroStudy
    var selected: Bool
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .opacity(selected ? 1 : 0)
                Text(study.title)
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
    var progress: Double?
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(IslandColor.warning)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: label)
                .frame(minWidth: 40)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(IslandColor.warning.opacity(hovered && progress == nil ? 0.28 : 0.16))
                            if let progress {
                                Capsule()
                                    .fill(IslandColor.warning.opacity(0.3))
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
        guard let progress else { return "업데이트" }
        return progress < 1 ? "\(Int(progress * 100))%" : "설치 중"
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
                Text("종료")
                    .font(.system(size: 11.5, weight: .semibold))
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
