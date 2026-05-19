import Foundation

enum HuggingFaceCredentials {
    private static let keychainAccount = "huggingface_access_token"
    private static let legacyUserDefaultsKey = "huggingface_access_token"
    private static let migrationFlagKey = "huggingface_token_keychain_migrated"

    static var token: String? {
        get {
            migrateFromUserDefaultsIfNeeded()
            return KeychainStorage.read(account: keychainAccount)
        }
        set {
            migrateFromUserDefaultsIfNeeded()
            if let newValue, !newValue.isEmpty {
                KeychainStorage.write(account: keychainAccount, value: newValue)
            } else {
                KeychainStorage.delete(account: keychainAccount)
            }
        }
    }

    static func applyAuth(to request: inout URLRequest) {
        guard let token else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private static func migrateFromUserDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationFlagKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migrationFlagKey) }

        if let legacy = UserDefaults.standard.string(forKey: legacyUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !legacy.isEmpty,
           KeychainStorage.read(account: keychainAccount) == nil {
            KeychainStorage.write(account: keychainAccount, value: legacy)
        }
        UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
    }
}
