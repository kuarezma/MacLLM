import Foundation

@main
struct HuggingFaceCredentialsTests {
    static func main() {
        testKeychainRoundTrip()
        print("HuggingFaceCredentialsTests: OK")
    }

    private static func testKeychainRoundTrip() {
        let account = "test_hf_token_\(UUID().uuidString)"
        KeychainStorage.delete(account: account)
        assert(KeychainStorage.read(account: account) == nil)
        KeychainStorage.write(account: account, value: "hf_test_secret")
        assert(KeychainStorage.read(account: account) == "hf_test_secret")
        KeychainStorage.delete(account: account)
        assert(KeychainStorage.read(account: account) == nil)
    }
}
