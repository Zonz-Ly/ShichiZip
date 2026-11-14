#if SHICHIZIP_DIAGNOSTICS
import AppKit
import Foundation
import Security
import Darwin

private final class SZDiagnosticsBundleToken: NSObject {}

/// Temporary diagnostics. This file and all call sites must be removed before the PR update.
public enum SZServiceDiagnostics {
    private static let lock = NSLock()
    private static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ShichiZip-Runtime-Diagnostics", isDirectory: true)
    private static let logURL = directory.appendingPathComponent(
        "\(Bundle.main.bundleIdentifier ?? "unknown")-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).jsonl")
    @MainActor private static var exportTimer: Timer?
    @MainActor private static var reportedExportFailure = false

    private static func jsonValue(_ value: Any) -> Any {
        switch value {
        case let value as String: value
        case let value as NSNumber: value
        case let value as NSNull: value
        case let value as URL: value.absoluteString
        case let value as Date: ISO8601DateFormatter().string(from: value)
        case let value as Data: value.map { String(format: "%02x", $0) }.joined()
        case let value as [String: Any]: value.mapValues(jsonValue)
        case let value as [Any]: value.map(jsonValue)
        default: String(describing: value)
        }
    }

    public static func record(_ event: String, _ values: [String: Any] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            var row = values.mapValues(jsonValue)
            row["time"] = ISO8601DateFormatter().string(from: Date())
            row["timestamp"] = Date().timeIntervalSince1970
            row["uptime"] = ProcessInfo.processInfo.systemUptime
            row["pid"] = ProcessInfo.processInfo.processIdentifier
            row["bundle"] = Bundle.main.bundleIdentifier ?? "unknown"
            row["event"] = event
            var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            data.append(0x0a)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                guard FileManager.default.createFile(atPath: logURL.path, contents: nil,
                                                      attributes: [.posixPermissions: 0o600]) else { return }
            }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            NSLog("[ShichiZipDiagnostics] Could not write diagnostics: %@", String(describing: error))
        }
    }

    public static func bootstrap(_ role: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            let stderrURL = logURL.deletingPathExtension().appendingPathExtension("stderr.log")
            let descriptor = Darwin.open(stderrURL.path, O_WRONLY | O_CREAT | O_APPEND, mode_t(0o600))
            if descriptor >= 0 {
                _ = dup2(descriptor, STDERR_FILENO)
                Darwin.close(descriptor)
            }
        } catch { /* JSON logging below still reports its own write failures. */ }
        let core = Bundle(for: SZDiagnosticsBundleToken.self)

        var metadata: [String: Any] = [
            "role": role, "bundlePath": Bundle.main.bundlePath,
            "executable": Bundle.main.executablePath ?? "missing",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "missing",
            "appCommit": Bundle.main.object(forInfoDictionaryKey: "ShichiZipGitShortHash") ?? "missing",
            "coreCommit": core.object(forInfoDictionaryKey: "ShichiZipGitShortHash") ?? "missing",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "arguments": ProcessInfo.processInfo.arguments,
            "configuredGroup": Bundle.main.object(forInfoDictionaryKey: "ShichiZipQuickActionAppGroupIdentifier") ?? "missing",
            "services": Bundle.main.object(forInfoDictionaryKey: "NSServices") ?? [],
            "mainThread": Thread.isMainThread,
        ]
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
           SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
           SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
           let dictionary = info as? [String: Any]
        {
            metadata["team"] = dictionary[kSecCodeInfoTeamIdentifier as String] ?? "missing"
            metadata["codeHash"] = dictionary[kSecCodeInfoUnique as String] ?? "missing"
            metadata["entitlements"] = dictionary[kSecCodeInfoEntitlementsDict as String] ?? [:]
        }
        record("process.bootstrap", metadata)
    }

    public static func preferences(_ event: String, defaults: UserDefaults, groupIdentifier: String?) {
        let keys = ["FileManager.ToolbarStyle", "FileManager.ToolbarShowButtonText",
                    "FileManager.ShowArchiveToolbar", "FileManager.ShowStandardToolbar",
                    "ShichiZip.SharedUserDefaultsMigrationVersion"]
        let cached = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0) ?? NSNull()) })
        let nativeKeys = ["NSToolbar Configuration FileManagerUnifiedToolbar", "NSToolbar Configuration FileManagerToolbar"]
        let native = Dictionary(uniqueKeysWithValues: nativeKeys.map { ($0, UserDefaults.standard.object(forKey: $0) ?? NSNull()) })
        // Observe cached values only: do not synchronize, flush or repair the preference store.
        record(event, ["group": groupIdentifier ?? "missing", "cached": cached, "nativeAutosave": native])
    }

    @MainActor public static func toolbar(_ event: String, window: NSWindow?) {
        guard let window else { record(event, ["window": "nil"]); return }
        record(event, ["windowNumber": window.windowNumber,
                       "toolbar": window.toolbar?.identifier ?? "nil",
                       "mode": window.toolbar?.displayMode.rawValue ?? 0,
                       "items": window.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? [],
                       "autosaves": window.toolbar?.autosavesConfiguration ?? false,
                       "windowVisible": window.isVisible])
    }

    @MainActor public static func startDesktopExport() {
        guard exportTimer == nil else { return }
        record("desktopExport.start", ["cacheDirectory": directory.path])
        let helpers = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier?.contains("ShichiZip.FinderService.") == true ||
                $0.bundleIdentifier?.contains("ShichiZipZS.FinderService.") == true
        }.map { ["pid": $0.processIdentifier, "bundle": $0.bundleIdentifier ?? "", "path": $0.bundleURL?.path ?? "",
                 "launched": $0.launchDate?.description ?? "unknown"] as [String: Any] }
        record("helpers.alreadyRunning", ["helpers": helpers])
        exportToDesktop()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in exportToDesktop() }
        }
        RunLoop.main.add(timer, forMode: .common)
        exportTimer = timer
    }

    @MainActor public static func exportToDesktop() {
        do {
            let desktop = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
            let output = desktop.appendingPathComponent("ShichiZip-Diagnostics", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            for source in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where ["jsonl", "log"].contains(source.pathExtension)
            {
                let data = try Data(contentsOf: source)
                try data.write(to: output.appendingPathComponent(source.lastPathComponent), options: .atomic)
            }
        } catch {
            if !reportedExportFailure {
                reportedExportFailure = true
                NSLog("[ShichiZipDiagnostics] Desktop export failed: %@", String(describing: error))
            }
        }
    }
}
#endif
