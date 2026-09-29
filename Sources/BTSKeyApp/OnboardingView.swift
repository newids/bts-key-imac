import SwiftUI
import HIDCore

/// First-run guide. Editorial layout: accent rail on the left with the step list, content on the right.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        HStack(spacing: 0) {
            rail
            content
        }
        .frame(width: 720, height: 460)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text(AppInfo.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 28)
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 10) {
                    Circle()
                        .fill(step.rawValue <= model.step.rawValue ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 8, height: 8)
                    Text(step.title)
                        .font(.system(size: 13, weight: step == model.step ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(step == model.step ? 1 : 0.6))
                }
                .padding(.vertical, 7)
            }
            Spacer()
            Text(AppInfo.versionLine)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(28)
        .frame(width: 236, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Color(red: 0.11, green: 0.16, blue: 0.36), Color(red: 0.05, green: 0.42, blue: 0.47)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: model.step.symbolName)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.step.title).font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(model.step.summary).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 22)
            stepBody
            Spacer(minLength: 12)
            if let error = model.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(.red).padding(.bottom, 8)
            }
            navigation
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var stepBody: some View {
        switch model.step {
        case .welcome: WelcomePage()
        case .permissions: PermissionsPage(model: model)
        case .pairing: PairingPage()
        case .connect: ConnectPage(model: model)
        case .inputSource: InputSourcePage()
        case .finish: FinishPage(model: model)
        }
    }

    private var navigation: some View {
        HStack {
            if model.canGoBack {
                Button("뒤로") { model.back() }.keyboardShortcut(.cancelAction)
            }
            Spacer()
            if !model.isLast {
                Button("나중에") { model.onFinish?() }.buttonStyle(.link).foregroundStyle(.secondary)
            }
            Button(model.isLast ? "시작하기" : "다음") { model.next() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(symbol: "keyboard", title: "키보드", text: "MacBook에서 치는 모든 키가 iMac으로 갑니다. Caps Lock 한/영 전환은 연결한 뒤 iMac에서 한 번 설정합니다.")
            FeatureRow(symbol: "hand.point.up.left", title: "트랙패드", text: "이동·클릭·두 손가락 스크롤을 iMac의 마우스로 전달합니다.")
            FeatureRow(symbol: "arrow.left.arrow.right", title: "한 번에 전환", text: "단축키 하나로 MacBook과 iMac 사이를 오갑니다. 현재 상태는 메뉴바 아래 상자로 항상 보입니다.")
            FeatureRow(symbol: "lock.open.laptopcomputer", title: "iMac에는 설치 없음", text: "관리형 iMac이라도 블루투스 페어링만으로 씁니다.")
        }
    }
}

private struct PermissionsPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(AppPermission.allCases, id: \.title) { permission in
                let granted = model.permissions[permission] == true
                HStack(spacing: 12) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(granted ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(permission.title).font(.system(size: 13, weight: .semibold))
                        Text(permission.reason).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !granted {
                        Button("허용하기…") { model.requestPermission(permission) }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Text("허용한 뒤 이 창으로 돌아오면 자동으로 확인됩니다. 앱을 다시 설치하면 권한을 다시 물어볼 수 있습니다.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

private struct PairingPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepRow(number: 1, text: "MacBook의 Bluetooth 설정을 열어 둡니다. MacBook은 이 화면이 열려 있는 동안에만 iMac에서 검색됩니다.")
            StepRow(number: 2, text: "iMac에서 시스템 설정 → Bluetooth를 열고, 근처 기기에 나타난 이 MacBook 옆 연결을 누릅니다.")
            StepRow(number: 3, text: "양쪽에 같은 숫자가 보이면 승인합니다.")
            Button("MacBook의 Bluetooth 설정 열기…") { SystemSettingsLinks.open(SystemSettingsLinks.bluetooth) }
                .padding(.top, 4)
            Text("페어링이 끝나면 이 앱이 새 iMac을 알아채고 스스로 연결합니다.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

private struct ConnectPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepRow(number: 1, text: "iMac의 Bluetooth 설정에서 “\(AppInfo.name)” 옆 연결을 누르거나, 아래 버튼으로 MacBook에서 연결합니다.")
            StepRow(number: 2, text: "연결되면 메뉴바 아이콘이 외곽선 키보드로 바뀝니다.")
            HStack(spacing: 10) {
                Text(model.hotkeyText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.orange, lineWidth: 1))
                Text("로 iMac 입력과 MacBook 입력을 오갑니다. iMac 입력 중에는 메뉴바 아래에 주황색 상자가 떠 있고 MacBook 포인터는 숨겨집니다.")
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(model.targetName.map { "\($0)에 지금 연결" } ?? "메뉴바에서 iMac 선택하기") {
                    if model.targetName != nil { model.onConnect?() } else { model.onSelectTarget?() }
                }
                Text("iMac에 로그인 화면이 떠 있어도 됩니다.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }
}

/// The one setting the host needs, in the words of its own System Settings.
private struct InputSourcePage: View {
    private var macName: String { Host.current().localizedName ?? "이 MacBook" }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            StepRow(number: 1, text: "iMac에 연결된 상태에서, iMac의 시스템 설정 → 키보드 → 키보드 단축키… → 보조 키를 엽니다.")
            StepRow(number: 2, text: "맨 위 ‘키보드 선택’ 단추를 눌러 목록을 펼칩니다. 고를 이름은 “\(macName)”입니다.")
            StepRow(number: 3, text: "‘Caps Lock 키’를 ‘🌐 fn 기능’으로 바꾸고 완료를 누릅니다.")
            StepRow(number: 4, text: "iMac의 키보드 설정에서 ‘🌐 키를 누를 때’가 ‘입력 소스 변경’인지 확인합니다.")
            VStack(alignment: .leading, spacing: 4) {
                Text("iMac의 다른 키보드에 해 둔 설정은 이 MacBook에 적용되지 않습니다. iMac의 설정이 초기화되면 다시 합니다.")
                Text("이 앱의 메뉴 → 설정 → Caps Lock → iMac은 ‘Caps Lock 그대로’로 둡니다. MacBook의 한/영도 함께 바뀌지만, iMac 입력을 마치면 원래대로 돌아옵니다.")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
        }
    }
}

private struct FinishPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(symbol: "menubar.rectangle", title: "메뉴바", text: "연결한 적 있는 iMac이 목록에 남습니다. 이름을 누르면 바로 연결됩니다.")
            FeatureRow(symbol: "moon.zzz", title: "잠자기 뒤에도", text: "iMac이 깨어나면 다시 연결되고, 쓰던 중이었다면 iMac 입력으로 자동 복귀합니다.")
            Toggle("로그인할 때 \(AppInfo.name) 자동 실행", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                .toggleStyle(.switch)
                .padding(.top, 6)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
