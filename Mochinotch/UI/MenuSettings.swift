import AppKit
import SwiftUI

struct MenuContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("もちノッチ")
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.top, 8)

        if let serverError = model.serverError {
            Text("이벤트 수신 실패 · \(serverError)")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
        }

        Divider()

        Menu("인트로 변경") {
            ForEach(IntroStudy.allCases, id: \.self) { study in
                Button {
                    model.setIntro(study)
                } label: {
                    if model.introStudy == study {
                        Label(study.title, systemImage: "checkmark")
                    } else {
                        Text(study.title)
                    }
                }
            }
        }
        Button("설정…") { model.openSettings() }

        Divider()

        Button("종료") { NSApp.terminate(nil) }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("버전", value: "0.1.0")
                LabeledContent("이벤트", value: "http://127.0.0.1:\(MochinotchConfig.port)/event")
                Toggle("로그인할 때 열기", isOn: launchBinding)
                if let launchAtLoginError = model.launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("もちノッチ")
            } footer: {
                Text("노치에 마우스를 올리면 쌓인 항목이 펼쳐져요. 항목을 누르면 그 앱으로 이동해요. 시스템 알림을 받으려면 전체 디스크 접근 권한에 Mochinotch를 넣어 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("에이전트 완료 알림 연출", isOn: screenEffectBinding)
                if model.notificationAccess == .denied {
                    Button("전체 디스크 접근 권한 열기…") { model.openFullDiskAccessSettings() }
                }
                if let duoMessage = model.duoMessage {
                    Text(duoMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("화면 기록 설정 열기…") { model.openScreenRecordingSettings() }
                }
            } header: {
                Text("완료 연출")
            } footer: {
                Text("켜면 작업이 끝날 때 화면 가장자리에 빛이 흐릅니다. 꺼도 노치 테두리를 도는 빛은 그대로예요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 440, height: 420)
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }

    private var screenEffectBinding: Binding<Bool> {
        Binding(
            get: { model.playsScreenEffect },
            set: { model.setPlaysScreenEffect($0) }
        )
    }
}
