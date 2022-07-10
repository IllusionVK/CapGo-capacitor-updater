import Foundation
import SSZipArchive
import Alamofire

extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
    var exist: Bool {
        return FileManager().fileExists(atPath: self.path)
    }
}
extension Date {
    func adding(minutes: Int) -> Date {
        return Calendar.current.date(byAdding: .minute, value: minutes, to: self)!
    }
}
struct AppVersionDec: Decodable {
    let version: String?
    let url: String?
    let message: String?
    let major: Bool?
}
public class AppVersion: NSObject {
    var version: String = ""
    var url: String = ""
    var message: String?
    var major: Bool?
}

extension AppVersion {
    func toDict() -> [String:Any] {
        var dict = [String:Any]()
        let otherSelf = Mirror(reflecting: self)
        for child in otherSelf.children {
            if let key = child.label {
                dict[key] = child.value
            }
        }
        return dict
    }
}

extension OperatingSystemVersion {
    func getFullVersion(separator: String = ".") -> String {
        return "\(majorVersion)\(separator)\(minorVersion)\(separator)\(patchVersion)"
    }
}
extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

extension ISO8601DateFormatter {
    convenience init(_ formatOptions: Options) {
        self.init()
        self.formatOptions = formatOptions
    }
}
extension Formatter {
    static let iso8601withFractionalSeconds = ISO8601DateFormatter([.withInternetDateTime, .withFractionalSeconds])
}
extension Date {
    var iso8601withFractionalSeconds: String { return Formatter.iso8601withFractionalSeconds.string(from: self) }
}
extension String {
    
    var fileURL: URL {
        return URL(fileURLWithPath: self)
    }
    
    var lastPathComponent:String {
        get {
            return fileURL.lastPathComponent
        }
    }
    var iso8601withFractionalSeconds: Date? {
        return Formatter.iso8601withFractionalSeconds.date(from: self)
    }
    func trim(using characterSet: CharacterSet = .whitespacesAndNewlines) -> String {
        return trimmingCharacters(in: characterSet)
    }
}

enum CustomError: Error {
    // Throw when an unzip fail
    case cannotUnzip
    case cannotUnflat
    case cannotCreateDirectory
    case cannotDeleteDirectory

    // Throw in all other cases
    case unexpected(code: Int)
}

extension CustomError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cannotUnzip:
            return NSLocalizedString(
                "The file cannot be unzip",
                comment: "Invalid zip"
            )
        case .cannotCreateDirectory:
            return NSLocalizedString(
                "The folder cannot be created",
                comment: "Invalid folder"
            )
        case .cannotDeleteDirectory:
            return NSLocalizedString(
                "The folder cannot be deleted",
                comment: "Invalid folder"
            )
        case .cannotUnflat:
            return NSLocalizedString(
                "The file cannot be unflat",
                comment: "Invalid folder"
            )
        case .unexpected(_):
            return NSLocalizedString(
                "An unexpected error occurred.",
                comment: "Unexpected Error"
            )
        }
    }
}

@objc public class CapacitorUpdater: NSObject {
    
    private let versionBuild = Bundle.main.releaseVersionNumber ?? ""
    private let versionCode = Bundle.main.buildVersionNumber ?? ""
    private let versionOs = ProcessInfo().operatingSystemVersion.getFullVersion()
    private let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
    private let bundleDirectoryHot = "versions"
    private let DEFAULT_FOLDER = ""
    private let bundleDirectory = "NoCloud/ionic_built_snapshots"
    private let INFO_SUFFIX = "_info"
    private let FALLBACK_VERSION = "pastVersion"
    private let NEXT_VERSION = "nextVersion"

    private var lastPathHot = ""
    private var lastPathPersist = ""
    
    public let TAG = "✨  Capacitor-updater:";
    public let CAP_SERVER_PATH = "serverBasePath"
    public let pluginVersion = "4.0.0-alpha.15"
    public var statsUrl = ""
    public var appId = ""
    public var deviceID = UIDevice.current.identifierForVendor?.uuidString ?? ""
    
    public var notifyDownload: (String, Int) -> Void = { _,_  in }

    private func calcTotalPercent(percent: Int, min: Int, max: Int) -> Int {
        return (percent * (max - min)) / 100 + min;
    }
    
    private func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
    // Persistent path /var/mobile/Containers/Data/Application/8C0C07BE-0FD3-4FD4-B7DF-90A88E12B8C3/Library/NoCloud/ionic_built_snapshots/FOLDER
    // Hot Reload path /var/mobile/Containers/Data/Application/8C0C07BE-0FD3-4FD4-B7DF-90A88E12B8C3/Documents/FOLDER
    // Normal /private/var/containers/Bundle/Application/8C0C07BE-0FD3-4FD4-B7DF-90A88E12B8C3/App.app/public
    
    private func prepareFolder(source: URL) throws {
        if (!FileManager.default.fileExists(atPath: source.path)) {
            do {
                try FileManager.default.createDirectory(atPath: source.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("\(self.TAG) Cannot createDirectory \(source.path)")
                throw CustomError.cannotCreateDirectory
            }
        }
    }
    
    private func deleteFolder(source: URL) throws {
        do {
            try FileManager.default.removeItem(atPath: source.path)
        } catch {
            print("\(self.TAG) File not removed. \(source.path)")
            throw CustomError.cannotDeleteDirectory
        }
    }
    
    private func unflatFolder(source: URL, dest: URL) throws -> Bool {
        let index = source.appendingPathComponent("index.html")
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: source.path)
            if (files.count == 1 && source.appendingPathComponent(files[0]).isDirectory && !FileManager.default.fileExists(atPath: index.path)) {
                try FileManager.default.moveItem(at: source.appendingPathComponent(files[0]), to: dest)
                return true
            } else {
                try FileManager.default.moveItem(at: source, to: dest)
                return false
            }
        } catch {
            print("\(self.TAG) File not moved. source: \(source.path) dest: \(dest.path)")
            throw CustomError.cannotUnflat
        }
    }
    
    private func saveDownloaded(sourceZip: URL, id: String, base: URL) throws {
        try prepareFolder(source: base)
        let destHot = base.appendingPathComponent(id)
        let destUnZip = documentsDir.appendingPathComponent(randomString(length: 10))
        if (!SSZipArchive.unzipFile(atPath: sourceZip.path, toDestination: destUnZip.path)) {
            throw CustomError.cannotUnzip
        }
        if (try unflatFolder(source: destUnZip, dest: destHot)) {
            try deleteFolder(source: destUnZip)
        }
    }

    public func getLatest(url: URL) -> AppVersion? {
        let semaphore = DispatchSemaphore(value: 0)
        let latest = AppVersion()
        let parameters: [String: String] = [
            "platform": "ios",
            "device_id": self.deviceID,
            "app_id": self.appId,
            "version_build": self.versionBuild,
            "version_code": self.versionCode,
            "version_os": self.versionOs,
            "plugin_version": self.pluginVersion,
            "version_name": self.getCurrentBundle().getVersionName()
        ]
        let request = AF.request(url, method: .post,parameters: parameters, encoder: JSONParameterEncoder.default)

        request.validate().responseDecodable(of: AppVersionDec.self) { response in
            switch response.result {
                case .success:
                    if let url = response.value?.url {
                        latest.url = url
                    }
                    if let version = response.value?.version {
                        latest.version = version
                    }
                    if let major = response.value?.major {
                        latest.major = major
                    }
                    if let message = response.value?.message {
                        latest.message = message
                        print("\(self.TAG) Auto-update message: \(message)")
                    }
                case let .failure(error):
                    print("\(self.TAG) Error getting Latest", error )
            }
            semaphore.signal()
        }
        semaphore.wait()
        return latest.url != "" ? latest : nil
    }
    
    private func setCurrentBundle(bundle: String) {
        UserDefaults.standard.set(bundle, forKey: self.CAP_SERVER_PATH)
        print("\(self.TAG) Current bundle set to: \(bundle)")
        UserDefaults.standard.synchronize()
    }

    public func download(url: URL, version: String) throws -> BundleInfo {
        let semaphore = DispatchSemaphore(value: 0)
        let id: String = self.randomString(length: 10)
        var mainError: NSError? = nil
        let destination: DownloadRequest.Destination = { _, _ in
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsURL.appendingPathComponent(self.randomString(length: 10))

            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }
        let request = AF.download(url, to: destination)
        
        request.downloadProgress { progress in
            let percent = self.calcTotalPercent(percent: Int(progress.fractionCompleted * 100), min: 10, max: 70)
            self.notifyDownload(id, percent)
        }
        request.responseURL { (response) in
            if let fileURL = response.fileURL {
                switch response.result {
                case .success:
                    self.notifyDownload(id, 71)
                    do {
                        try self.saveDownloaded(sourceZip: fileURL, id: id, base: self.documentsDir.appendingPathComponent(self.bundleDirectoryHot))
                        self.notifyDownload(id, 85)
                        try self.saveDownloaded(sourceZip: fileURL, id: id, base: self.libraryDir.appendingPathComponent(self.bundleDirectory))
                        self.notifyDownload(id, 100)
                        try self.deleteFolder(source: fileURL)
                    } catch {
                        print("\(self.TAG) download unzip error", error)
                        mainError = error as NSError
                    }
                case let .failure(error):
                    print("\(self.TAG) download error", error)
                    mainError = error as NSError
                }
            }
            semaphore.signal()
        }
        self.saveBundleInfo(id: id, bundle: BundleInfo(id: id, version: version, status: BundleStatus.DOWNLOADING, downloaded: Date()))
        self.notifyDownload(id, 0)
        semaphore.wait()
        if (mainError != nil) {
            throw mainError!
        }
        let info: BundleInfo = BundleInfo(id: id, version: version, status: BundleStatus.PENDING, downloaded: Date())
        self.saveBundleInfo(id: id, bundle: info)
        return info
    }

    public func list() -> [BundleInfo] {
        let dest = documentsDir.appendingPathComponent(bundleDirectoryHot)
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: dest.path)
            var res: [BundleInfo] = []
            print("\(self.TAG) list File : \(dest.path)")
            if (dest.exist) {
                for id in files {
                    res.append(self.getBundleInfo(id: id));
                }
            }
            return res
        } catch {
            print("\(self.TAG) No version available \(dest.path)")
            return []
        }
    }
    
    public func delete(id: String) -> Bool {
        let deleted: BundleInfo = self.getBundleInfo(id: id)
        let destHot = documentsDir.appendingPathComponent(bundleDirectoryHot).appendingPathComponent(id)
        let destPersist = libraryDir.appendingPathComponent(bundleDirectory).appendingPathComponent(id)
        do {
            try FileManager.default.removeItem(atPath: destHot.path)
        } catch {
            print("\(self.TAG) Hot Folder \(destHot.path), not removed.")
        }
        do {
            try FileManager.default.removeItem(atPath: destPersist.path)
        } catch {
            print("\(self.TAG) Folder \(destPersist.path), not removed.")
            return false
        }
        self.removeBundleInfo(id: id)
        self.sendStats(action: "delete", versionName: deleted.getVersionName())
        return true
    }

    public func getBundleDirectory(id: String) -> URL {
        return libraryDir.appendingPathComponent(self.bundleDirectory).appendingPathComponent(id)
    }

    public func set(bundle: BundleInfo) -> Bool {
        return self.set(id: bundle.getId());
    }

    private func bundleExists(id: String) -> Bool {
        let destHot = self.getPathHot(id: id)
        let destHotPersist = self.getPathPersist(id: id)
        let indexHot = destHot.appendingPathComponent("index.html")
        let indexPersist = destHotPersist.appendingPathComponent("index.html")
        let url: URL = self.getBundleDirectory(id: id)
        if(url.isDirectory && destHotPersist.isDirectory && indexHot.exist && indexPersist.exist) {
            return true;
        }
        return false;
    }

    public func set(id: String) -> Bool {
        let newBundle: BundleInfo = self.getBundleInfo(id: id)
        if (bundleExists(id: id)) {
            let url: URL = self.getBundleDirectory(id: id)
            self.setCurrentBundle(bundle: String(url.path.suffix(10)))
            self.setBundleStatus(id: id, status: BundleStatus.PENDING)
            sendStats(action: "set", versionName: newBundle.getVersionName())
            return true
        }
        sendStats(action: "set_fail", versionName: newBundle.getVersionName())
        return false
    }
    
    public func getPathHot(id: String) -> URL {
        return documentsDir.appendingPathComponent(self.bundleDirectoryHot).appendingPathComponent(id)
    }
    
    public func getPathPersist(id: String) -> URL {
        return libraryDir.appendingPathComponent(self.bundleDirectory).appendingPathComponent(id)
    }
    
    public func reset() {
        self.reset(isInternal: false)
    }
    
    public func reset(isInternal: Bool) {
        self.setCurrentBundle(bundle: "")
        self.setFallbackVersion(fallback: Optional<BundleInfo>.none)
        let _ = self.setNextVersion(next: Optional<String>.none)
        UserDefaults.standard.synchronize()
        if(!isInternal) {
            sendStats(action: "reset", versionName: self.getCurrentBundle().getVersionName())
        }
    }
    
    public func commit(bundle: BundleInfo) {
        self.setBundleStatus(id: bundle.getId(), status: BundleStatus.SUCCESS)
        self.setFallbackVersion(fallback: bundle)
    }
    
    public func rollback(bundle: BundleInfo) {
        self.setBundleStatus(id: bundle.getId(), status: BundleStatus.ERROR);
    }

    func sendStats(action: String, versionName: String) {
        if (statsUrl == "") { return }
        let parameters: [String: String] = [
            "platform": "ios",
            "action": action,
            "device_id": self.deviceID,
            "version_name": versionName,
            "version_build": self.versionBuild,
            "version_code": self.versionCode,
            "version_os": self.versionOs,
            "plugin_version": self.pluginVersion,
            "app_id": self.appId
        ]

        DispatchQueue.global(qos: .background).async {
            let _ = AF.request(self.statsUrl, method: .post,parameters: parameters, encoder: JSONParameterEncoder.default)
            print("\(self.TAG) Stats send for \(action), version \(versionName)")
        }
    }

    public func getBundleInfo(id: String = BundleInfo.ID_BUILTIN) -> BundleInfo {
        print("\(self.TAG) Getting info for bundle [\(id)]")
        if(BundleInfo.ID_BUILTIN == id) {
            return BundleInfo(id: id, version: "", status: BundleStatus.SUCCESS)
        }
        do {
            let result: BundleInfo = try UserDefaults.standard.getObj(forKey: "\(id)\(self.INFO_SUFFIX)", castTo: BundleInfo.self)
            print("\(self.TAG) Returning info bundle [\(id)]", result.toString())
            return result
        } catch {
            print("\(self.TAG) Failed to parse info for bundle [\(id)]", error.localizedDescription)
            return BundleInfo(id: id, version: "", status: BundleStatus.PENDING)
        }
    }

    public func getBundleInfoByVersionName(version: String) -> BundleInfo? {
        let installed : Array<BundleInfo> = self.list()
        for i in installed {
            if(i.getVersionName() == version) {
                return i
            }
        }
        return nil
    }

    private func removeBundleInfo(id: String) {
        self.saveBundleInfo(id: id, bundle: nil)
    }

    private func saveBundleInfo(id: String, bundle: BundleInfo?) {
        if (bundle != nil && (bundle!.isBuiltin() || bundle!.isUnknown())) {
            print("\(self.TAG) Not saving info for bundle [\(id)]", bundle!.toString())
            return
        }
        if(bundle == nil) {
            print("\(self.TAG) Removing info for bundle [\(id)]")
            UserDefaults.standard.removeObject(forKey: "\(id)\(self.INFO_SUFFIX)")
        } else {
            let update = bundle!.setId(id: id)
            print("\(self.TAG) Storing info for bundle [\(id)]", update.toString())
            do {
                try UserDefaults.standard.setObj(update, forKey: "\(id)\(self.INFO_SUFFIX)")
            } catch {
                print("\(self.TAG) Failed to save info for bundle [\(id)]", error.localizedDescription)
            }
        }
        UserDefaults.standard.synchronize()
    }

    public func setVersionName(id: String, version: String) {
        print("\(self.TAG) Setting version for folder [\(id)] to \(version)")
        let info = self.getBundleInfo(id: id)
        self.saveBundleInfo(id: id, bundle: info.setVersionName(version: version))
    }

    private func setBundleStatus(id: String, status: BundleStatus) {
        print("\(self.TAG) Setting status for bundle [\(id)] to \(status)")
        let info = self.getBundleInfo(id: id)
        self.saveBundleInfo(id: id, bundle: info.setStatus(status: status.localizedString))
    }

    private func getCurrentBundleVersion() -> String {
        if(self.isUsingBuiltin()) {
            return BundleInfo.ID_BUILTIN
        } else {
            let path: String = self.getCurrentBundleId()
            return path.lastPathComponent
        }
    }

    public func getCurrentBundle() -> BundleInfo {
        return self.getBundleInfo(id: self.getCurrentBundleId());
    }

    public func getCurrentBundleId() -> String {
        return UserDefaults.standard.string(forKey: self.CAP_SERVER_PATH) ?? self.DEFAULT_FOLDER
    }

    public func isUsingBuiltin() -> Bool {
        return self.getCurrentBundleId() == self.DEFAULT_FOLDER
    }

    public func getFallbackVersion() -> BundleInfo {
        let id: String = UserDefaults.standard.string(forKey: self.FALLBACK_VERSION) ?? BundleInfo.ID_BUILTIN
        return self.getBundleInfo(id: id)
    }

    private func setFallbackVersion(fallback: BundleInfo?) {
        UserDefaults.standard.set(fallback == nil ? BundleInfo.ID_BUILTIN : fallback!.getId(), forKey: self.FALLBACK_VERSION)
    }

    public func getNextVersion() -> BundleInfo? {
        let id: String = UserDefaults.standard.string(forKey: self.NEXT_VERSION) ?? ""
        if(id != "") {
            return self.getBundleInfo(id: id)
        } else {
            return nil
        }
    }

    public func setNextVersion(next: String?) -> Bool {
        if (next == nil) {
            UserDefaults.standard.removeObject(forKey: self.NEXT_VERSION)
        } else {
            let bundle: URL = self.getBundleDirectory(id: next!)
            if (!bundle.exist) {
                return false
            }
            UserDefaults.standard.set(next, forKey: self.NEXT_VERSION)
            self.setBundleStatus(id: next!, status: BundleStatus.PENDING);
        }
        UserDefaults.standard.synchronize()
        return true
    }
}
