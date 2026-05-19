import Foundation

enum LoadModelOnLaunch: String, CaseIterable, Identifiable {
    case ask
    case always
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ask: return "Her açılışta sor"
        case .always: return "Otomatik yükle"
        case .never: return "Yükleme"
        }
    }
}

enum LaunchPreferences {
    private static let key = "loadModelOnLaunch"

    static var loadModelOnLaunch: LoadModelOnLaunch {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let value = LoadModelOnLaunch(rawValue: raw) else {
                return .ask
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
