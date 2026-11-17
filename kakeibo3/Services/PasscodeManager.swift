import Foundation
import Combine

// MARK: - セッションタイムアウト選択肢

enum SessionTimeoutOption: String, CaseIterable {
    case immediately
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case never

    /// タイムアウトまでの秒数。nil の場合は「ロックしない」
    var seconds: TimeInterval? {
        switch self {
        case .immediately:    return 0
        case .oneMinute:      return 60
        case .fiveMinutes:    return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes:  return 1800
        case .oneHour:        return 3600
        case .never:          return nil
        }
    }

    var displayName: String {
        switch self {
        case .immediately:    return "すぐにロック"
        case .oneMinute:      return "1分後"
        case .fiveMinutes:    return "5分後"
        case .fifteenMinutes: return "15分後"
        case .thirtyMinutes:  return "30分後"
        case .oneHour:        return "1時間後"
        case .never:          return "ロックしない"
        }
    }
}

final class PasscodeManager: ObservableObject {
    static let shared = PasscodeManager()

    private enum Keys {
        static let enabled            = "passcodeLockEnabled"
        static let passcode           = "appPasscode"
        static let sessionTimeout     = "passcodeSessionTimeoutOption"
        static let lastBackgroundDate = "passcodeLastBackgroundDate"
    }

    // MARK: - Published (PasscodeSettingsView の UI 更新に使用)

    @Published private(set) var isEnabled: Bool
    @Published var sessionTimeoutOption: SessionTimeoutOption {
        didSet {
            UserDefaults.standard.set(sessionTimeoutOption.rawValue, forKey: Keys.sessionTimeout)
        }
    }

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        let savedRaw = UserDefaults.standard.string(forKey: Keys.sessionTimeout)
        sessionTimeoutOption = savedRaw.flatMap(SessionTimeoutOption.init(rawValue:)) ?? .fiveMinutes
    }

    // MARK: - Computed Properties

    var hasPasscode: Bool {
        UserDefaults.standard.string(forKey: Keys.passcode) != nil
    }

    /// ロック有効かどうか（enabled かつ passcode が保存済み）
    var isPasscodeLockEnabled: Bool {
        isEnabled && hasPasscode
    }

    // MARK: - Operations

    func save(passcode: String) {
        UserDefaults.standard.set(passcode, forKey: Keys.passcode)
        UserDefaults.standard.set(true,     forKey: Keys.enabled)
        isEnabled = true
    }

    func verify(_ passcode: String) -> Bool {
        UserDefaults.standard.string(forKey: Keys.passcode) == passcode
    }

    func validate(_ passcode: String) -> Bool {
        verify(passcode)
    }

    func disable() {
        UserDefaults.standard.removeObject(forKey: Keys.passcode)
        UserDefaults.standard.set(false, forKey: Keys.enabled)
        isEnabled = false
    }

    // MARK: - セッションタイムアウト

    private var lastBackgroundDate: Date? {
        get {
            let raw = UserDefaults.standard.double(forKey: Keys.lastBackgroundDate)
            return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: Keys.lastBackgroundDate)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.lastBackgroundDate)
            }
        }
    }

    /// アプリがバックグラウンドに入った時刻を記録する
    func recordBackgroundEntry() {
        guard isPasscodeLockEnabled else { return }
        lastBackgroundDate = Date()
    }

    /// フォアグラウンド復帰時、セッションタイムアウトを超えているかどうかを判定する
    func shouldLockOnForeground() -> Bool {
        guard isPasscodeLockEnabled else { return false }

        switch sessionTimeoutOption {
        case .never:
            return false
        case .immediately:
            return true
        default:
            guard let seconds = sessionTimeoutOption.seconds, let last = lastBackgroundDate else {
                return true
            }
            return Date().timeIntervalSince(last) >= seconds
        }
    }
}
