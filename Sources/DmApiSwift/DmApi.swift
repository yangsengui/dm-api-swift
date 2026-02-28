import DmApiObjC
import Foundation

public typealias JsonMap = [String: Any]

private let dmApiSwiftErrorDomain = "com.distromate.dm-api-swift"
private let dmDevLicenseErrorText =
    "Development license is missing or corrupted. Run `distromate sdk renew` to regenerate the dev certificate."

public final class DmApi {
    private let raw: DMApiObjC

    public init(libraryPath: String? = nil) throws {
        self.raw = try DMApiObjC(libraryPath: libraryPath)
    }

    public static func shouldSkipCheck(
        appId: String? = nil,
        publicKey: String? = nil
    ) throws -> Bool {
        let env = ProcessInfo.processInfo.environment
        let endpoint = (env["DM_LAUNCHER_ENDPOINT"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let token = (env["DM_LAUNCHER_TOKEN"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpoint.isEmpty, !token.isEmpty {
            return false
        }

        let resolvedAppId = (appId ?? env["DM_APP_ID"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPublicKey = (publicKey ?? env["DM_PUBLIC_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if resolvedAppId.isEmpty || resolvedPublicKey.isEmpty {
            throw NSError(
                domain: dmApiSwiftErrorDomain,
                code: 1001,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "App identity is required for dev-license checks. Provide appId/publicKey or set DM_APP_ID and DM_PUBLIC_KEY.",
                ]
            )
        }

        let home = NSHomeDirectory()
        if home.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(
                domain: dmApiSwiftErrorDomain,
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: dmDevLicenseErrorText]
            )
        }

        let pubkeyPath = (home as NSString)
            .appendingPathComponent(".distromate-cli/dev_licenses/\(resolvedAppId)/pubkey")

        guard let devPublicKeyRaw = try? String(contentsOfFile: pubkeyPath, encoding: .utf8) else {
            throw NSError(
                domain: dmApiSwiftErrorDomain,
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: dmDevLicenseErrorText]
            )
        }

        let devPublicKey = devPublicKeyRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if devPublicKey.isEmpty || devPublicKey != resolvedPublicKey {
            throw NSError(
                domain: dmApiSwiftErrorDomain,
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: dmDevLicenseErrorText]
            )
        }

        return true
    }

    public func getLastError() -> String? {
        raw.getLastError()
    }

    public func getActivationErrorName(_ code: UInt32?) -> String? {
        guard let code else {
            return nil
        }
        return raw.getActivationErrorName(NSNumber(value: code))
    }

    public func setProductData(_ productData: String) -> Bool {
        raw.setProductData(productData)
    }

    public func setProductId(_ productId: String) -> Bool {
        raw.setProductId(productId)
    }

    public func setDataDirectory(_ directoryPath: String) -> Bool {
        raw.setDataDirectory(directoryPath)
    }

    public func setDebugMode(_ enable: Bool) -> Bool {
        raw.setDebugMode(enable)
    }

    public func setCustomDeviceFingerprint(_ fingerprint: String) -> Bool {
        raw.setCustomDeviceFingerprint(fingerprint)
    }

    public func setLicenseKey(_ licenseKey: String) -> Bool {
        raw.setLicenseKey(licenseKey)
    }

    public func setLicenseCallback(_ callback: @escaping () -> Void) -> Bool {
        raw.setLicenseCallback(callback)
    }

    public func activateLicense() -> Bool {
        raw.activateLicense()
    }

    public func getLastActivationError() -> UInt32? {
        raw.getLastActivationError()?.uint32Value
    }

    public func isLicenseGenuine() -> Bool {
        raw.isLicenseGenuine()
    }

    public func isLicenseValid() -> Bool {
        raw.isLicenseValid()
    }

    public func getServerSyncGracePeriodExpiryDate() -> UInt32? {
        raw.getServerSyncGracePeriodExpiryDate()?.uint32Value
    }

    public func getActivationMode(bufferSize: UInt32 = 64) -> [String: String]? {
        raw.getActivationMode(withBufferSize: bufferSize)
    }

    public func getLicenseKey(bufferSize: UInt32 = 256) -> String? {
        raw.getLicenseKey(withBufferSize: bufferSize)
    }

    public func getLicenseExpiryDate() -> UInt32? {
        raw.getLicenseExpiryDate()?.uint32Value
    }

    public func getLicenseCreationDate() -> UInt32? {
        raw.getLicenseCreationDate()?.uint32Value
    }

    public func getLicenseActivationDate() -> UInt32? {
        raw.getLicenseActivationDate()?.uint32Value
    }

    public func getActivationCreationDate() -> UInt32? {
        raw.getActivationCreationDate()?.uint32Value
    }

    public func getActivationLastSyncedDate() -> UInt32? {
        raw.getActivationLastSyncedDate()?.uint32Value
    }

    public func getActivationId(bufferSize: UInt32 = 256) -> String? {
        raw.getActivationId(withBufferSize: bufferSize)
    }

    public func reset() -> Bool {
        raw.reset()
    }

    public func checkForUpdates(_ options: JsonMap? = nil) -> JsonMap? {
        raw.check(forUpdates: options)
    }

    public func downloadUpdate(_ options: JsonMap? = nil) -> JsonMap? {
        raw.downloadUpdate(options)
    }

    public func cancelUpdateDownload(_ options: JsonMap? = nil) -> JsonMap? {
        raw.cancelUpdateDownload(options)
    }

    public func getUpdateState() -> JsonMap? {
        raw.getUpdateState()
    }

    public func getPostUpdateInfo() -> JsonMap? {
        raw.getPostUpdateInfo()
    }

    public func ackPostUpdateInfo(_ options: JsonMap? = nil) -> JsonMap? {
        raw.ackPostUpdateInfo(options)
    }

    public func waitForUpdateStateChange(
        lastSequence: UInt64,
        timeoutMs: UInt32 = 30_000
    ) -> JsonMap? {
        raw.wait(forUpdateStateChange: lastSequence, timeoutMs: timeoutMs)
    }

    public func quitAndInstall(_ options: JsonMap? = nil) -> Int32 {
        raw.quitAndInstall(options)
    }

    public func getLibraryVersion() -> String {
        raw.getLibraryVersion()
    }

    public func jsonToCanonical(_ jsonStr: String) -> String? {
        raw.json(toCanonical: jsonStr)
    }
}
