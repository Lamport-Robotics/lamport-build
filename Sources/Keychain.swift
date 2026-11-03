import Foundation
import Security

/// the app's own key lives in the login keychain, never in defaults or files.
/// the item is stored so that an update of the app can read it back: a keychain item's default access list names the
/// exact binary that made it, and for an app signed outside Apple's program every update is a new binary, so the
/// login keychain would ask again after each one. the item's own access list is opened instead; the keychain still
/// keeps it encrypted and locked with the login keychain.
enum Keychain {
    private static let service = "si.lamport.build"
    private static let label = "Lamport Build"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = label
        if let access = openAccess() { add[kSecAttrAccess as String] = access }
        SecItemAdd(add as CFDictionary, nil)
        UserDefaults.standard.set(true, forKey: "keychain.open." + key)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data, let s = String(data: d, encoding: .utf8) else { return nil }
        // an item from an older build still carries the per-binary list; once it has been read, store it the new way
        if !UserDefaults.standard.bool(forKey: "keychain.open." + key) { set(s, for: key) }
        return s
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "keychain.open." + key)
    }

    /// an access list whose read side names no particular binary
    private static func openAccess() -> SecAccess? {
        var access: SecAccess?
        guard SecAccessCreate(label as CFString, nil, &access) == errSecSuccess, let access else { return nil }
        for auth in [kSecACLAuthorizationDecrypt, kSecACLAuthorizationExportClear, kSecACLAuthorizationExportWrapped, kSecACLAuthorizationAny] {
            guard let list = SecAccessCopyMatchingACLList(access, auth) as? [SecACL] else { continue }
            for acl in list {
                var apps: CFArray?; var desc: CFString?; var prompt = SecKeychainPromptSelector()
                guard SecACLCopyContents(acl, &apps, &desc, &prompt) == errSecSuccess else { continue }
                let auths = SecACLCopyAuthorizations(acl) as? [String] ?? []
                // the owner's right to change the list itself stays as it is
                if auths.contains(kSecACLAuthorizationChangeACL as String) { continue }
                SecACLSetContents(acl, nil, desc ?? label as CFString, SecKeychainPromptSelector())
            }
        }
        return access
    }
}
