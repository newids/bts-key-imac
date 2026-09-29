/// Pages of the first-run guide, in order.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case permissions
    case pairing
    case connect
    /// After connecting: the host lists this Mac under Modifier Keys only while it is connected.
    case inputSource
    case finish

    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// 0 at the first step, 1 at the last.
    public var progress: Double {
        Double(rawValue) / Double(OnboardingStep.allCases.count - 1)
    }

    public var title: String {
        switch self {
        case .welcome: return "MacBook을 iMac의 키보드로"
        case .permissions: return "권한 허용"
        case .pairing: return "iMac과 페어링"
        case .connect: return "연결하고 전환하기"
        case .inputSource: return "Caps Lock으로 한/영"
        case .finish: return "준비 완료"
        }
    }

    public var summary: String {
        switch self {
        case .welcome:
            return "BTS Key는 MacBook을 블루투스 키보드와 마우스로 만들어 iMac에 연결합니다. iMac에는 아무것도 설치하지 않습니다."
        case .permissions:
            return "키 입력과 트랙패드를 iMac으로 보내려면 macOS의 세 가지 권한이 필요합니다. 각 항목의 버튼을 눌러 시스템 설정에서 허용하세요."
        case .pairing:
            return "iMac의 시스템 설정 → Bluetooth에서 이 MacBook을 한 번 페어링합니다. 관리자 권한은 필요 없습니다."
        case .connect:
            return "iMac 쪽 Bluetooth 설정에서 BTS Key를 연결하거나, 메뉴바에서 iMac을 선택해 연결합니다. 그 뒤 단축키로 입력을 오갑니다."
        case .inputSource:
            return "iMac은 보조 키 설정을 키보드마다 따로 기억합니다. iMac에서 이 MacBook을 골라 한 번 지정하면 Caps Lock으로 iMac의 한/영이 바뀝니다."
        case .finish:
            return "메뉴바의 키보드 아이콘에서 언제든 연결 상태를 보고 바꿀 수 있습니다."
        }
    }

    public var symbolName: String {
        switch self {
        case .welcome: return "keyboard"
        case .permissions: return "lock.shield"
        case .pairing: return "link"
        case .connect: return "arrow.left.arrow.right"
        case .inputSource: return "globe"
        case .finish: return "checkmark.seal"
        }
    }
}
