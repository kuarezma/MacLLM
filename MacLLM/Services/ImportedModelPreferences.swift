import Foundation

/// v1.14.14: Eski içe aktarılmış modeller için Flash Attention tek seferlik geçişi.
enum ImportedModelPreferences {
    private static let migrationKey = "importedFlashAttentionMigrated_v11414"
    private static let bannerDismissedKey = "importedFlashBannerDismissed_v11414"

    static var flashMigrationCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: migrationKey) }
        set { UserDefaults.standard.set(newValue, forKey: migrationKey) }
    }

    static var flashBannerDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: bannerDismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: bannerDismissedKey) }
    }
}
