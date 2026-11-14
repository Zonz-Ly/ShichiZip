import Foundation
#if SHICHIZIP_DIAGNOSTICS
    import ShichiZipQuickActionCore
#endif

enum SZSharedUserDefaults {
    static let appGroupIdentifierInfoKey = "ShichiZipQuickActionAppGroupIdentifier"

    private static let migrationVersionKey = "ShichiZip.SharedUserDefaultsMigrationVersion"
    private static let currentMigrationVersion = 1

    static var defaults: UserDefaults {
        sharedDefaults ?? .standard
    }

    static let appGroupIdentifier: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: appGroupIdentifierInfoKey) as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }()

    /// Foundation documents UserDefaults as thread-safe, but does not declare it Sendable.
    nonisolated(unsafe) static let sharedDefaults: UserDefaults? = {
        guard let appGroupIdentifier else {
            return nil
        }

        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        #if SHICHIZIP_DIAGNOSTICS
            SZServiceDiagnostics.record("preferences.shared-object-created", ["group": appGroupIdentifier,
                                                                            "created": defaults != nil])
        #endif
        return defaults
    }()

    static func migrateStandardDefaultsIfNeeded() {
        #if SHICHIZIP_DIAGNOSTICS
            SZServiceDiagnostics.record("preferences.migration-check", ["group": appGroupIdentifier ?? "missing",
                "version": sharedDefaults?.integer(forKey: migrationVersionKey) ?? -1])
        #endif
        guard let appGroupIdentifier,
              let sharedDefaults,
              let appDefaultsDomainName = Bundle.main.bundleIdentifier,
              sharedDefaults.integer(forKey: migrationVersionKey) < currentMigrationVersion
        else {
            return
        }

        migrateDefaultsDomain(named: appDefaultsDomainName,
                              from: .standard,
                              to: sharedDefaults,
                              destinationDomainName: appGroupIdentifier,
                              removesSourceDomain: true)
        sharedDefaults.set(currentMigrationVersion, forKey: migrationVersionKey)
        #if SHICHIZIP_DIAGNOSTICS
            SZServiceDiagnostics.preferences("preferences.migration-finished", defaults: sharedDefaults,
                                             groupIdentifier: appGroupIdentifier)
        #endif
    }

    @discardableResult
    static func migrateDefaultsDomain(named sourceDomainName: String,
                                      from source: UserDefaults,
                                      to destination: UserDefaults,
                                      destinationDomainName: String,
                                      removesSourceDomain: Bool) -> Int
    {
        guard let sourceDomain = source.persistentDomain(forName: sourceDomainName) else {
            return 0
        }

        let destinationDomain = destination.persistentDomain(forName: destinationDomainName) ?? [:]
        var migratedCount = 0
        for (key, value) in sourceDomain {
            guard destinationDomain[key] == nil else {
                continue
            }

            destination.set(value, forKey: key)
            migratedCount += 1
        }

        if removesSourceDomain {
            #if SHICHIZIP_DIAGNOSTICS
                SZServiceDiagnostics.record("preferences.removing-source-domain", ["source": sourceDomainName,
                    "destination": destinationDomainName, "migratedCount": migratedCount])
            #endif
            source.removePersistentDomain(forName: sourceDomainName)
        }

        return migratedCount
    }
}

extension UserDefaults {
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }

    func integer(forKey key: String, default defaultValue: Int) -> Int {
        object(forKey: key) == nil ? defaultValue : integer(forKey: key)
    }

    func double(forKey key: String, default defaultValue: Double) -> Double {
        object(forKey: key) == nil ? defaultValue : double(forKey: key)
    }

    func enumValue<Value: RawRepresentable>(forKey key: String, default defaultValue: Value) -> Value
        where Value.RawValue == Int
    {
        let rawValue: Int? = switch object(forKey: key) {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): number as? Int
        case let string as String: Int(string)
        default: nil
        }
        guard let rawValue else { return defaultValue }
        return Value(rawValue: rawValue) ?? defaultValue
    }

    func enumValue<Value: RawRepresentable>(forKey key: String, default defaultValue: Value) -> Value
        where Value.RawValue == String
    {
        guard let rawValue = string(forKey: key) else { return defaultValue }
        return Value(rawValue: rawValue) ?? defaultValue
    }
}
