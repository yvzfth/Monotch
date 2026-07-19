import Combine
import Darwin
import Foundation
import IOKit
import ServiceManagement

final class SystemMonitorManager: ObservableObject {
    static let shared = SystemMonitorManager()

    struct FanReading: Identifiable, Equatable {
        let id: Int
        let name: String
        let currentRPM: Double
        let minimumRPM: Double
        let maximumRPM: Double
        let targetRPM: Double?
    }

    struct TemperatureReading: Identifiable, Equatable {
        enum Kind: String, CaseIterable, Hashable {
            case cpu
            case gpu
            case ssd
            case battery
            case memory
            case wifi
        }

        let kind: Kind
        let celsius: Double

        var id: Kind { kind }
    }

    struct StorageCategory: Identifiable, Equatable {
        enum Kind: String, CaseIterable {
            case photos
            case applications
            case documents
            case developer
            case mail
            case systemData
        }

        let kind: Kind
        let bytes: UInt64

        var id: Kind { kind }
    }

    enum FanMode: String {
        case automatic = "Auto"
        case silent = "Silent"
        case balanced = "Balanced"
        case performance = "Performance"
        case maximum = "Max"

        var title: String {
            switch self {
            case .automatic: return String(localized: "Auto", comment: "The automatic fan mode.")
            case .silent: return String(localized: "Silent", comment: "The silent fan mode.")
            case .balanced: return String(localized: "Balanced", comment: "The balanced fan mode.")
            case .performance: return String(localized: "Performance", comment: "The performance fan mode.")
            case .maximum: return String(localized: "Max", comment: "The maximum fan mode.")
            }
        }
    }

    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var cpuUserUsage: Double = 0
    @Published private(set) var cpuSystemUsage: Double = 0
    @Published private(set) var cpuIdleUsage: Double = 1
    @Published private(set) var threadCount: Int = 0
    @Published private(set) var processCount: Int = 0
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryFree: UInt64 = 0
    @Published private(set) var memoryApp: UInt64 = 0
    @Published private(set) var memoryWired: UInt64 = 0
    @Published private(set) var memoryCompressed: UInt64 = 0
    @Published private(set) var memoryCached: UInt64 = 0
    @Published private(set) var memorySwapUsed: UInt64 = 0
    @Published private(set) var diskUsed: UInt64 = 0
    @Published private(set) var diskFree: UInt64 = 0
    @Published private(set) var diskTotal: UInt64 = 0
    @Published private(set) var diskCategories: [StorageCategory] = []
    @Published private(set) var fanAvailable = false
    @Published private(set) var fanControlAvailable = false
    @Published private(set) var fanMode: FanMode = .automatic
    @Published private(set) var fanCurrentRPM: Double = 0
    @Published private(set) var fanMaximumRPM: Double = 0
    @Published private(set) var fanReadings: [FanReading] = []
    @Published private(set) var fanAccessDenied = false
    @Published private(set) var fanLastWriteFailed = false
    @Published private(set) var fanWriteAccessDenied = false
    @Published private(set) var fanHelperRequiresApproval = false
    @Published private(set) var temperatureReadings: [TemperatureReading] = []

    private var timer: Timer?
    private var previousCPUTicks: host_cpu_load_info = host_cpu_load_info()
    private var hasPreviousCPUTicks = false
    private let smc = AppleSMCController()
    private let coreTelemetryQueue = DispatchQueue(label: "fatihyavuz.Monotch.core-telemetry", qos: .utility)
    private let fanTelemetryQueue = DispatchQueue(label: "fatihyavuz.Monotch.fan-telemetry", qos: .utility)
    private let storageScanQueue = DispatchQueue(label: "fatihyavuz.Monotch.storage-scan", qos: .utility)
    private var lastStorageCategoryScan = Date.distantPast
    private var isReadingCoreTelemetry = false
    private var isReadingFanTelemetry = false
    private var isScanningStorageCategories = false
    private var isMonitoringActive = false
    private var lastProcessCountScan = Date.distantPast
    private var pendingFanMode: FanMode?
    private var pendingFanModeUntil = Date.distantPast
    static let quietFanModeThermalLimitCelsius = 75.0

    private init() {}

    func setMonitoringActive(_ active: Bool) {
        guard isMonitoringActive != active else { return }
        isMonitoringActive = active

        if active {
            startTimer()
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 0.6
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    func setFanMode(_ requestedMode: FanMode) -> FanMode {
        guard fanControlAvailable else {
            fanMode = .automatic
            pendingFanMode = nil
            return .automatic
        }

        let mode = thermallySafeFanMode(for: requestedMode)
        fanMode = mode
        pendingFanMode = mode
        pendingFanModeUntil = Date().addingTimeInterval(2.0)
        fanLastWriteFailed = false
        fanWriteAccessDenied = false
        let directSuccess: Bool
        directSuccess = smc.setFanMode(mode)

        if directSuccess {
            fanMode = mode
            refresh()
            return mode
        }

        switch PrivilegedFanDaemon.setFanMode(mode) {
        case .success:
            fanMode = mode
            fanWriteAccessDenied = false
            fanHelperRequiresApproval = false
            refresh()
            return mode
        case .requiresApproval:
            applyAutomaticFanFallback()
            fanHelperRequiresApproval = true
            refresh()
            return .automatic
        case .denied:
            applyAutomaticFanFallback()
            fanLastWriteFailed = true
            fanWriteAccessDenied = true
            refresh()
            return .automatic
        case .unavailable:
            applyAutomaticFanFallback()
            fanLastWriteFailed = true
            refresh()
            return .automatic
        }
    }

    private func thermallySafeFanMode(for mode: FanMode) -> FanMode {
        guard mode == .silent || mode == .balanced else { return mode }
        return isCPUTooHotForQuietFanMode(temperatureReadings) ? .automatic : mode
    }

    private func shouldReturnToAutomaticForThermalSafety(mode: FanMode, readings: [TemperatureReading]) -> Bool {
        guard mode == .silent || mode == .balanced else { return false }
        return isCPUTooHotForQuietFanMode(readings)
    }

    private func isCPUTooHotForQuietFanMode(_ readings: [TemperatureReading]) -> Bool {
        guard let cpuTemperature = readings.first(where: { $0.kind == .cpu })?.celsius else { return false }
        return cpuTemperature >= Self.quietFanModeThermalLimitCelsius
    }

    private func applyAutomaticFanFallback() {
        pendingFanMode = nil
        fanMode = .automatic

        if smc.setFanMode(.automatic) == false {
            _ = PrivilegedFanDaemon.setFanMode(.automatic)
        }
    }

    func refresh() {
        readCoreTelemetry()
        readFanTelemetry()
    }

    private func readCoreTelemetry() {
        guard isReadingCoreTelemetry == false else { return }
        isReadingCoreTelemetry = true

        let fallbackCPU = CPUSnapshot(
            usage: cpuUsage,
            userUsage: cpuUserUsage,
            systemUsage: cpuSystemUsage,
            idleUsage: cpuIdleUsage
        )

        coreTelemetryQueue.async { [weak self] in
            guard let self else { return }

            let cpu = self.readCPUSnapshot(fallback: fallbackCPU)
            let now = Date()
            let shouldReadProcessCounts = now.timeIntervalSince(self.lastProcessCountScan) >= 12
                || self.processCount == 0
                || self.threadCount == 0
            let processCounts = shouldReadProcessCounts
                ? Self.readProcessCountsSnapshot()
                : ProcessCountSnapshot(processes: self.processCount, threads: self.threadCount)
            let memory = Self.readMemorySnapshot()
            let disk = Self.readDiskSnapshot()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                self.cpuUsage = cpu.usage
                self.cpuUserUsage = cpu.userUsage
                self.cpuSystemUsage = cpu.systemUsage
                self.cpuIdleUsage = cpu.idleUsage
                self.threadCount = processCounts.threads
                self.processCount = processCounts.processes
                if shouldReadProcessCounts {
                    self.lastProcessCountScan = now
                }
                self.memoryFree = memory.free
                self.memoryUsed = memory.used
                self.memoryApp = memory.app
                self.memoryWired = memory.wired
                self.memoryCompressed = memory.compressed
                self.memoryCached = memory.cached
                self.memorySwapUsed = memory.swapUsed
                self.diskTotal = disk.total
                self.diskFree = disk.free
                self.diskUsed = disk.used

                if disk.total == 0 {
                    self.diskCategories = []
                }

                self.isReadingCoreTelemetry = false
            }
        }
    }

    private struct CPUSnapshot {
        let usage: Double
        let userUsage: Double
        let systemUsage: Double
        let idleUsage: Double
    }

    private struct ProcessCountSnapshot {
        let processes: Int
        let threads: Int
    }

    private struct MemorySnapshot {
        let used: UInt64
        let free: UInt64
        let app: UInt64
        let wired: UInt64
        let compressed: UInt64
        let cached: UInt64
        let swapUsed: UInt64
    }

    private struct DiskSnapshot {
        let used: UInt64
        let free: UInt64
        let total: UInt64
    }

    private func readCPUSnapshot(fallback: CPUSnapshot) -> CPUSnapshot {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return fallback }

        defer {
            previousCPUTicks = load
            hasPreviousCPUTicks = true
        }

        guard hasPreviousCPUTicks else {
            return CPUSnapshot(usage: 0, userUsage: 0, systemUsage: 0, idleUsage: 1)
        }

        let user = Double(load.cpu_ticks.0 - previousCPUTicks.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1 - previousCPUTicks.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2 - previousCPUTicks.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3 - previousCPUTicks.cpu_ticks.3)
        let total = user + system + idle + nice

        guard total > 0 else { return fallback }

        let userUsage = min(1, max(0, user / total))
        let systemUsage = min(1, max(0, (system + nice) / total))
        let idleUsage = min(1, max(0, idle / total))
        let usage = min(1, max(0, (user + system + nice) / total))

        return CPUSnapshot(
            usage: usage,
            userUsage: userUsage,
            systemUsage: systemUsage,
            idleUsage: idleUsage
        )
    }

    private static func readProcessCountsSnapshot() -> ProcessCountSnapshot {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: size_t = 0

        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return ProcessCountSnapshot(processes: 0, threads: 0)
        }

        let capacity = max(1, size / MemoryLayout<kinfo_proc>.stride)
        var processes = Array(repeating: kinfo_proc(), count: capacity)
        let result = processes.withUnsafeMutableBufferPointer { buffer in
            sysctl(&mib, u_int(mib.count), buffer.baseAddress, &size, nil, 0)
        }

        guard result == 0 else {
            return ProcessCountSnapshot(processes: 0, threads: 0)
        }

        let actualCount = min(processes.count, size / MemoryLayout<kinfo_proc>.stride)
        var threads = 0

        for process in processes.prefix(actualCount) {
            var taskInfo = proc_taskallinfo()
            let infoSize = Int32(MemoryLayout<proc_taskallinfo>.stride)
            let readSize = proc_pidinfo(process.kp_proc.p_pid, PROC_PIDTASKALLINFO, 0, &taskInfo, infoSize)

            if readSize == infoSize {
                threads += max(0, Int(taskInfo.ptinfo.pti_threadnum))
            }
        }

        return ProcessCountSnapshot(processes: actualCount, threads: threads)
    }

    private static func readMemorySnapshot() -> MemorySnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemorySnapshot(used: 0, free: 0, app: 0, wired: 0, compressed: 0, cached: 0, swapUsed: 0)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let physical = ProcessInfo.processInfo.physicalMemory
        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let cachedPages = UInt64(stats.external_page_count) + purgeablePages

        let app = appPages * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = min(physical, app + wired + compressed)
        let free = physical > used ? physical - used : 0
        let cached = min(cachedPages * pageSize, free)

        return MemorySnapshot(
            used: used,
            free: free,
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cached,
            swapUsed: readSwapUsedSnapshot()
        )
    }

    private static func readDiskSnapshot() -> DiskSnapshot {
        do {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try homeURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])

            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let free = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
            let used = total > free ? total - free : 0

            return DiskSnapshot(used: used, free: free, total: total)
        } catch {
            return DiskSnapshot(used: 0, free: 0, total: 0)
        }
    }

    private static func readSwapUsedSnapshot() -> UInt64 {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else {
            return 0
        }

        return UInt64(swap.xsu_used)
    }

    func refreshStorageCategoriesIfNeeded() {
        let now = Date()
        guard diskTotal > 0 else {
            diskCategories = []
            return
        }
        guard isScanningStorageCategories == false else { return }
        guard now.timeIntervalSince(lastStorageCategoryScan) > 300 || diskCategories.isEmpty else { return }

        isScanningStorageCategories = true
        lastStorageCategoryScan = now

        let diskUsedSnapshot = diskUsed
        storageScanQueue.async { [weak self] in
            let categories = autoreleasepool {
                Self.scanStorageCategories(diskUsed: diskUsedSnapshot)
            }

            DispatchQueue.main.async {
                self?.diskCategories = categories
                self?.isScanningStorageCategories = false
            }
        }
    }

    private static func scanStorageCategories(diskUsed: UInt64) -> [StorageCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let developerPathPrefixes = [
            home.appendingPathComponent("Developer").standardizedFileURL.path,
            home.appendingPathComponent("Documents/Codes").standardizedFileURL.path,
            home.appendingPathComponent(".gradle").standardizedFileURL.path,
            home.appendingPathComponent(".npm").standardizedFileURL.path,
            home.appendingPathComponent(".pub-cache").standardizedFileURL.path,
            home.appendingPathComponent(".cargo").standardizedFileURL.path,
            home.appendingPathComponent(".rustup").standardizedFileURL.path,
            home.appendingPathComponent(".swiftpm").standardizedFileURL.path
        ]
        let photoLibraryURLs = [
            home.appendingPathComponent("Pictures")
        ]
        let mediaSearchURLs = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Movies"),
            home.appendingPathComponent("Music")
        ]
        let pathsByKind: [(StorageCategory.Kind, [URL])] = [
            (.developer, [
                URL(fileURLWithPath: "/Library/Developer"),
                home.appendingPathComponent("Developer"),
                home.appendingPathComponent("Documents/Codes"),
                home.appendingPathComponent(".gradle"),
                home.appendingPathComponent(".npm"),
                home.appendingPathComponent(".pub-cache"),
                home.appendingPathComponent(".cargo"),
                home.appendingPathComponent(".rustup"),
                home.appendingPathComponent(".swiftpm")
            ]),
            (.applications, [
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications"),
                home.appendingPathComponent("Applications")
            ]),
            (.documents, [
                home.appendingPathComponent("Documents"),
                home.appendingPathComponent("Desktop"),
                home.appendingPathComponent("Downloads"),
                home.appendingPathComponent("Movies"),
                home.appendingPathComponent("Music")
            ])
        ]

        var seenPaths = Set<String>()
        var categories: [StorageCategory] = []
        var categorizedBytes: UInt64 = 0

        let photosBytes = photoLibraryURLs.reduce(UInt64(0)) { total, url in
            total + allocatedSize(of: url, seenPaths: &seenPaths)
        } + mediaSearchURLs.reduce(UInt64(0)) { total, url in
            total + mediaAllocatedSize(
                of: url,
                seenPaths: &seenPaths,
                excludedPathPrefixes: developerPathPrefixes
            )
        }
        categorizedBytes += photosBytes
        categories.append(StorageCategory(kind: .photos, bytes: photosBytes))

        for (kind, urls) in pathsByKind {
            let bytes = urls.reduce(UInt64(0)) { total, url in
                total + allocatedSize(of: url, seenPaths: &seenPaths)
            }

            categorizedBytes += bytes
            categories.append(StorageCategory(kind: kind, bytes: bytes))
        }

        if categorizedBytes > diskUsed, categorizedBytes > 0 {
            categories = categories.map { category in
                StorageCategory(
                    kind: category.kind,
                    bytes: UInt64((Double(category.bytes) / Double(categorizedBytes)) * Double(diskUsed))
                )
            }
            categorizedBytes = categories.reduce(UInt64(0)) { $0 + $1.bytes }
        }

        let systemDataBytes = diskUsed > categorizedBytes ? diskUsed - categorizedBytes : 0
        categories.append(StorageCategory(kind: .systemData, bytes: systemDataBytes))

        return categories
    }

    private static func mediaAllocatedSize(
        of url: URL,
        seenPaths: inout Set<String>,
        excludedPathPrefixes: [String]
    ) -> UInt64 {
        let rootPath = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: rootPath) else { return 0 }
        guard isPath(rootPath, insideAnyOf: excludedPathPrefixes) == false else { return 0 }

        let mediaExtensions: Set<String> = [
            "jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "raw", "dng",
            "webp", "bmp", "psd", "ai", "svg", "mov", "mp4", "m4v", "avi", "mkv", "hevc"
        ]
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            let path = fileURL.standardizedFileURL.path
            if isPath(path, insideAnyOf: excludedPathPrefixes) {
                enumerator.skipDescendants()
                continue
            }

            guard mediaExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            guard seenPaths.insert(path).inserted else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }

            total += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        return total
    }

    private static func allocatedSize(of url: URL, seenPaths: inout Set<String>) -> UInt64 {
        let path = url.standardizedFileURL.path
        guard seenPaths.insert(path).inserted else { return 0 }
        guard FileManager.default.fileExists(atPath: path) else { return 0 }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]

        if let values = try? url.resourceValues(forKeys: Set(keys)),
           values.isRegularFile == true {
            return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard seenPaths.insert(fileURL.standardizedFileURL.path).inserted else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }

            total += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        return total
    }

    private static func isPath(_ path: String, insideAnyOf prefixes: [String]) -> Bool {
        prefixes.contains { prefix in
            path == prefix || path.hasPrefix(prefix + "/")
        }
    }

    private func readFanTelemetry() {
        guard isReadingFanTelemetry == false else { return }
        isReadingFanTelemetry = true

        let helperRequiresApprovalSnapshot = fanHelperRequiresApproval
        fanTelemetryQueue.async { [weak self] in
            guard let self else { return }

            let readings = self.smc.fanReadings
            let currentRPM = readings.first?.currentRPM ?? self.smc.currentRPM
            let maximumRPM = readings.first?.maximumRPM ?? self.smc.maximumRPM
            let hasFanTelemetry = readings.isEmpty == false || currentRPM != nil || maximumRPM != nil
            let hasFanMetadata = self.smc.fanCount > 0
            let hasFanHardware = hasFanTelemetry || hasFanMetadata || (self.smc.isOpen && Self.modelUsuallyHasFan)
            let fanControlAvailable = hasFanTelemetry && self.smc.isOpen && readings.isEmpty == false
            let detectedMode = hasFanHardware && fanControlAvailable ? self.smc.currentFanMode : nil
            let shouldClearApproval = helperRequiresApprovalSnapshot && PrivilegedFanDaemon.isEnabled
            let temperatures = self.smc.temperatureReadings

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                if shouldClearApproval {
                    self.fanHelperRequiresApproval = false
                    self.fanLastWriteFailed = false
                }

                self.fanAvailable = hasFanHardware
                self.fanControlAvailable = fanControlAvailable
                self.fanAccessDenied = hasFanHardware && hasFanTelemetry == false
                self.fanCurrentRPM = currentRPM ?? 0
                self.fanMaximumRPM = maximumRPM ?? 0
                self.fanReadings = readings
                self.temperatureReadings = temperatures

                if let pendingFanMode = self.pendingFanMode, self.pendingFanModeUntil > Date() {
                    self.fanMode = pendingFanMode
                } else {
                    self.pendingFanMode = nil
                    if hasFanHardware == false || fanControlAvailable == false {
                        self.fanMode = .automatic
                    } else if let detectedMode {
                        self.fanMode = detectedMode
                    }
                }

                self.isReadingFanTelemetry = false

                if self.shouldReturnToAutomaticForThermalSafety(mode: self.fanMode, readings: temperatures) {
                    self.setFanMode(.automatic)
                }
            }
        }
    }

    static let modelLikelyHasFan: Bool = modelUsuallyHasFan

    private static var modelUsuallyHasFan: Bool {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return false }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return false }

        let model = String(cString: buffer)
        if model.contains("MacBookAir") || model.contains("Mac") == false {
            return false
        }

        return model.contains("MacBookPro")
            || model.contains("Macmini")
            || model.contains("MacStudio")
            || model.contains("iMac")
            || model.contains("MacPro")
    }
}

private extension SystemMonitorManager.FanMode {
    var commandString: String {
        switch self {
        case .automatic:
            return "auto"
        case .silent:
            return "silent"
        case .balanced:
            return "balanced"
        case .performance:
            return "performance"
        case .maximum:
            return "max"
        }
    }
}

private enum BundledFanTool {
    static func setFanMode(_ mode: SystemMonitorManager.FanMode) -> Bool {
        guard let helperURL = Bundle.main.url(forResource: "MonotchFanTool", withExtension: nil) else {
            return false
        }

        return runDirect(helperURL: helperURL, argument: mode.commandString)
    }

    private static func runDirect(helperURL: URL, argument: String) -> Bool {
        let process = Process()
        process.executableURL = helperURL
        process.arguments = [argument]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

}

private enum FanDaemonCommandResult: Equatable {
    case success
    case denied
    case requiresApproval
    case unavailable
}

private enum PrivilegedFanDaemon {
    private static let currentPlistName = "fatihyavuz.Monotch.FanDaemon.v4.plist"
    private static let currentSocketPath = "/var/run/fatihyavuz.Monotch.FanDaemon.v4.sock"
    private static let legacyPlistName = "fatihyavuz.Monotch.FanDaemon.v2.plist"
    private static let legacySocketPath = "/var/run/fatihyavuz.Monotch.FanDaemon.v2.sock"

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.daemon(plistName: currentPlistName).status == .enabled
    }

    static func setFanMode(_ mode: SystemMonitorManager.FanMode) -> FanDaemonCommandResult {
        switch mode {
        case .automatic, .balanced, .maximum:
            let legacyResult = run(mode.commandString, socketPath: legacySocketPath, plistName: legacyPlistName, shouldRegister: false)
            if legacyResult == .success || legacyResult == .denied {
                return legacyResult
            }

            return run(mode.commandString, socketPath: currentSocketPath, plistName: currentPlistName, shouldRegister: true)
        case .silent, .performance:
            return run(mode.commandString, socketPath: currentSocketPath, plistName: currentPlistName, shouldRegister: true)
        }
    }

    private static func run(
        _ command: String,
        socketPath: String,
        plistName: String,
        shouldRegister: Bool
    ) -> FanDaemonCommandResult {
        let firstAttempt = send(command, socketPath: socketPath)
        if firstAttempt != .unavailable {
            return firstAttempt
        }

        guard shouldRegister else { return .unavailable }

        switch registerIfNeeded(plistName: plistName) {
        case .success:
            for _ in 0..<12 {
                Thread.sleep(forTimeInterval: 0.25)
                let retry = send(command, socketPath: socketPath)
                if retry != .unavailable {
                    return retry
                }
            }
            return .unavailable
        case .requiresApproval:
            return .requiresApproval
        case .denied:
            return .denied
        case .unavailable:
            return .unavailable
        }
    }

    private static func registerIfNeeded(plistName: String) -> FanDaemonCommandResult {
        guard #available(macOS 13.0, *) else { return .unavailable }

        let service = SMAppService.daemon(plistName: plistName)
        switch service.status {
        case .enabled:
            return .success
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            do {
                try service.register()
            } catch {
                return .unavailable
            }

            switch service.status {
            case .enabled:
                return .success
            case .requiresApproval:
                return .requiresApproval
            case .notRegistered, .notFound:
                return .unavailable
            @unknown default:
                return .unavailable
            }
        @unknown default:
            return .unavailable
        }
    }

    private static func send(_ command: String, socketPath: String) -> FanDaemonCommandResult {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return .unavailable }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            return .unavailable
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            for (index, byte) in pathBytes.enumerated() {
                rawBuffer[index] = byte
            }
            rawBuffer[pathBytes.count] = 0
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connected == 0 else { return .unavailable }

        let payload = Array("\(command)\n".utf8)
        let written = payload.withUnsafeBytes { buffer in
            Darwin.write(descriptor, buffer.baseAddress, buffer.count)
        }
        guard written == payload.count else { return .unavailable }

        var response = [UInt8](repeating: 0, count: 64)
        let received = response.withUnsafeMutableBytes { buffer in
            Darwin.read(descriptor, buffer.baseAddress, buffer.count - 1)
        }
        guard received > 0 else { return .unavailable }

        let text = String(decoding: response.prefix(received), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch text {
        case "ok":
            return .success
        case "denied", "unauthorized":
            return .denied
        default:
            return .unavailable
        }
    }
}

private final class AppleSMCController {
    private let kernelIndexSMC: UInt32 = 2
    private let commandReadBytes: UInt8 = 5
    private let commandWriteBytes: UInt8 = 6
    private let commandReadKeyInfo: UInt8 = 9
    private var connection: io_connect_t = 0

    init() {
        open()
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    var fanCount: Int {
        Int(readUInt8("FNum") ?? 0)
    }

    var canControlFan: Bool {
        isOpen && fanReadings.isEmpty == false
    }

    var isOpen: Bool {
        connection != 0
    }

    var currentRPM: Double? {
        readFanNumber("F0Ac")
    }

    var maximumRPM: Double? {
        readFanNumber("F0Mx")
    }

    var fanReadings: [SystemMonitorManager.FanReading] {
        let count = detectedFanCount
        guard count > 0 else { return [] }

        return (0..<count).compactMap { index in
            guard let current = readFanNumber("F\(index)Ac"),
                  let maximum = readFanNumber("F\(index)Mx") else {
                return nil
            }

            let resolvedMaximum = maximum > 0 ? maximum : fallbackMaximumRPM
            let minimum = readFanNumber("F\(index)Mn") ?? (resolvedMaximum * 0.28)

            return SystemMonitorManager.FanReading(
                id: index,
                name: fanName(for: index, count: count),
                currentRPM: current,
                minimumRPM: min(max(0, minimum), resolvedMaximum),
                maximumRPM: resolvedMaximum,
                targetRPM: readFanNumber("F\(index)Tg")
            )
        }
    }

    var temperatureReadings: [SystemMonitorManager.TemperatureReading] {
        SystemMonitorManager.TemperatureReading.Kind.allCases.compactMap { kind in
            guard let celsius = readTemperature(for: kind) else {
                return nil
            }

            return SystemMonitorManager.TemperatureReading(kind: kind, celsius: celsius)
        }
    }

    var isFanForced: Bool? {
        if let modeKey = fanModeKey(for: 0), let mode = readUInt8(modeKey) {
            return mode == 1
        }

        guard let mask = readUInt16("FS!") else { return nil }
        return (mask & 0x0001) != 0
    }

    var currentFanMode: SystemMonitorManager.FanMode? {
        guard let isForced = isFanForced else { return nil }
        guard isForced else { return .automatic }

        let readings = fanReadings
        guard readings.isEmpty == false else { return .maximum }

        let normalizedTargets = readings.compactMap { manualTargetRatio(for: $0) }
        guard normalizedTargets.isEmpty == false else { return .maximum }

        let averageTarget = normalizedTargets.reduce(0, +) / Double(normalizedTargets.count)
        if averageTarget <= 0.38 {
            return .silent
        }

        if averageTarget >= 0.90 {
            return .maximum
        }

        if averageTarget >= 0.62 {
            return .performance
        }

        if averageTarget >= 0.43 {
            return .balanced
        }

        return .silent
    }

    func setFanMode(_ mode: SystemMonitorManager.FanMode) -> Bool {
        switch mode {
        case .automatic:
            return setAutomaticFanMode()
        case .silent, .balanced, .performance, .maximum:
            return setManualFanMode(mode)
        }
    }

    func setAutomaticFanMode() -> Bool {
        let count = detectedFanCount
        var usedModernKeys = false
        var success = true

        for index in 0..<count {
            guard let modeKey = fanModeKey(for: index) else { continue }
            usedModernKeys = true
            success = writeUInt8(modeKey, value: 0) && success
        }

        if usedModernKeys {
            if readKeyInfo("Ftst") != nil {
                _ = writeUInt8("Ftst", value: 0)
            }

            return success
        }

        return writeUInt16("FS!", value: 0)
    }

    func setMaximumFanMode() -> Bool {
        return setManualFanMode(.maximum)
    }

    private func setManualFanMode(_ mode: SystemMonitorManager.FanMode) -> Bool {
        let readings = fanReadings
        guard readings.isEmpty == false else { return false }

        var usedModernKeys = false
        var modernSuccess = true
        for reading in readings {
            guard let modeKey = fanModeKey(for: reading.id) else { continue }
            usedModernKeys = true

            let targetRPM = fanTargetRPM(for: mode, reading: reading)
            let modeWritten = writeUInt8(modeKey, value: 1)
            let targetWritten = writeFanNumber("F\(reading.id)Tg", value: targetRPM)
            modernSuccess = modeWritten && targetWritten && modernSuccess
        }

        if usedModernKeys {
            return modernSuccess
        }

        let manualMask = UInt16(readings.reduce(0) { mask, reading in
            mask | (1 << UInt16(reading.id))
        })

        let targetWritten = readings.reduce(true) { success, reading in
            let targetRPM = fanTargetRPM(for: mode, reading: reading)
            return writeFanNumber("F\(reading.id)Tg", value: targetRPM) && success
        }

        let modeWritten = writeUInt16("FS!", value: manualMask)
        return targetWritten && modeWritten
    }

    private func fanTargetRPM(for mode: SystemMonitorManager.FanMode, reading: SystemMonitorManager.FanReading) -> Double {
        switch mode {
        case .silent:
            return reading.minimumRPM
        case .balanced:
            return max(reading.minimumRPM, reading.maximumRPM * 0.50)
        case .performance:
            return reading.minimumRPM + ((reading.maximumRPM - reading.minimumRPM) * 0.70)
        case .maximum:
            return reading.maximumRPM
        case .automatic:
            return reading.currentRPM
        }
    }

    private func manualTargetRatio(for reading: SystemMonitorManager.FanReading) -> Double? {
        guard let targetRPM = reading.targetRPM else { return nil }

        guard reading.maximumRPM > 0 else { return nil }

        return min(1, max(0, targetRPM / reading.maximumRPM))
    }

    func canWriteCurrentFanTargets() -> Bool {
        let count = detectedFanCount
        guard count > 0 else { return false }

        var testedTarget = false
        for index in 0..<count {
            let targetKey = "F\(index)Tg"
            guard let currentTarget = readFanNumber(targetKey) else {
                continue
            }

            testedTarget = true
            guard writeFanNumber(targetKey, value: currentTarget) else {
                return false
            }
        }

        return testedTarget
    }

    private var fallbackMaximumRPM: Double {
        6200
    }

    private var detectedFanCount: Int {
        let explicitCount = fanCount
        if explicitCount > 0 {
            return min(explicitCount, 8)
        }

        for index in (0..<8).reversed() {
            if readKey("F\(index)Ac") != nil || readKey("F\(index)Mx") != nil {
                return index + 1
            }
        }

        return 0
    }

    private func fanName(for index: Int, count: Int) -> String {
        if count == 2 {
            return index == 0 ? "Left" : "Right"
        }

        return "Fan \(index + 1)"
    }

    private func open() {
        let serviceNames: [String] = ["AppleSMCKeysEndpoint", "AppleSMC"]
        let service = serviceNames
            .lazy
            .map { IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching($0)) }
            .first { $0 != 0 } ?? 0

        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        if result != KERN_SUCCESS {
            connection = 0
        }
    }

    private func readUInt8(_ key: String) -> UInt8? {
        readKey(key)?.first
    }

    private func readUInt16(_ key: String) -> UInt16? {
        guard let bytes = readKey(key), bytes.count >= 2 else { return nil }
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }

    private func readFanNumber(_ key: String) -> Double? {
        guard let keyInfo = readKeyInfo(key),
              let bytes = readKey(key, keyInfo: keyInfo),
              bytes.count >= 2 else {
            return nil
        }

        if keyInfo.dataType == smcKey("fpe2") {
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0
        }

        if keyInfo.dataType == smcKey("flt "), bytes.count >= 4 {
            let bitPattern = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            let value = Float(bitPattern: bitPattern)
            guard value.isFinite, value >= 0 else { return nil }
            return Double(value)
        }

        return nil
    }

    private func readTemperature(_ keys: [String]) -> Double? {
        for key in keys {
            guard let value = readTemperature(key), isUsableTemperature(value) else {
                continue
            }

            return value
        }

        return nil
    }

    private func readTemperature(for kind: SystemMonitorManager.TemperatureReading.Kind) -> Double? {
        let keys = candidateTemperatureKeys(for: kind)

        switch kind {
        case .gpu, .memory:
            return readHottestComponentTemperature(keys)
        default:
            return readTemperature(keys)
        }
    }

    private func readHottestComponentTemperature(_ keys: [String]) -> Double? {
        keys.compactMap { key in
            guard let value = readTemperature(key), isUsableTemperature(value) else {
                return nil
            }

            return value
        }
        .max()
    }

    private func isUsableTemperature(_ value: Double) -> Bool {
        value.isFinite && value > 0 && value < 130
    }

    private func readTemperature(_ key: String) -> Double? {
        guard let keyInfo = readKeyInfo(key),
              let bytes = readKey(key, keyInfo: keyInfo),
              bytes.count >= 2 else {
            return nil
        }

        if keyInfo.dataType == smcKey("sp78") {
            return Double(Int8(bitPattern: bytes[0])) + Double(bytes[1]) / 256.0
        }

        if keyInfo.dataType == smcKey("flt "), bytes.count >= 4 {
            let bitPattern = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            let value = Float(bitPattern: bitPattern)
            guard value.isFinite else { return nil }
            return Double(value)
        }

        return nil
    }

    private func candidateTemperatureKeys(for kind: SystemMonitorManager.TemperatureReading.Kind) -> [String] {
        switch kind {
        case .cpu:
            return [
                "TCMb", "TCMz",
                "Tp00", "Tp01", "Tp02", "Tp04", "Tp05", "Tp06", "Tp08", "Tp09", "Tp0A",
                "Tp0C", "Tp0D", "Tp0E", "Tp0G", "Tp0H", "Tp0I", "Tp0K", "Tp0L", "Tp0M",
                "Tp0O", "Tp0P", "Tp0Q", "Tp0R", "Tp0S", "Tp0T", "Tp0U", "Tp0V", "Tp0W",
                "Tp0X", "Tp0Y", "Tp0Z", "Tp0a", "Tp0b", "Tp0c", "Tp0d", "Tp0e", "Tp0f",
                "Tp0g", "Tp0h", "Tp0i", "Tp0j", "Tp0k", "Tp0l", "Tp0m", "Tp0n", "Tp0o",
                "Tp0p", "Tp0q", "Tp0r", "Tp0s", "Tp0t", "Tp0u", "Tp0v", "Tp0w", "Tp0x",
                "Tp0y", "Tp0z", "Tp10", "Tp16", "Tp17", "Tp18", "Tp1A", "Tp1B", "Tp1C",
                "Tp1E", "Tp1F", "Tp1G", "Tp1I", "Tp1J", "Tp1K", "Tp1Q", "Tp1R", "Tp1S",
                "Tp1U", "Tp1g", "Tp1i", "Tp1j", "Tp1k", "Tp1m", "Tp1n", "Tp1o", "Tp1q",
                "Tp1t", "Tp1u", "Tp1v", "Tp1w", "Tp1x", "Tp1y", "Tp1z", "Tp20", "Tp21",
                "Tp22", "Tp23", "Tp24", "Tp25", "Tp26", "Tp27", "Tp28", "Tp29", "Tp2A",
                "Tp2B", "Tp2C", "Tp2D", "Tp2E", "Tp2G", "Tpx0", "Tpx1", "Tpx2", "Tpx3",
                "Tpx4", "Tpx5", "Tpx8", "Tpx9", "TpxA", "TpxB", "TpxC", "TpxD",
                "TC0P", "TC0E", "TC0D", "TC0F", "TC0H", "TC0C", "TC1C"
            ]
        case .gpu:
            return [
                "Tg00", "Tg01", "Tg04", "Tg05", "Tg08", "Tg0C", "Tg0D", "Tg0G", "Tg0H",
                "Tg0K", "Tg0L", "Tg0O", "Tg0P", "Tg0R", "Tg0S", "Tg0T", "Tg0U", "Tg0V",
                "Tg0X", "Tg0Y", "Tg0a", "Tg0b", "Tg0d", "Tg0e", "Tg0f", "Tg0g", "Tg0i",
                "Tg0j", "Tg0k", "Tg0m", "Tg0n", "Tg0q", "Tg0r", "Tg0u", "Tg0v", "Tg0y",
                "Tg0z", "Tg12", "Tg13", "Tg16", "Tg17", "Tg1A", "Tg1B", "Tg1E", "Tg1F",
                "Tg1I", "Tg1M", "Tg1Q", "Tg1U", "Tg1V", "Tg1Y", "Tg1c", "Tg1d", "Tg1k",
                "Tg1l", "Tg1o", "Tg1s", "Tg1t", "Tg1x", "Tg1y", "Tg21", "Tg22", "Tg29",
                "Tg2A", "Tg2D", "Tg2H", "Tg2I", "Tg2P", "Tg2Q", "Tg2T", "Tg2X", "Tg2Y",
                "Tg2b", "Tg2f", "Tg2g", "Tg2j", "Tg2n", "Tg2o", "Tg2r", "Tg33", "Tg34",
                "Tg3B", "Tg3C", "Tg3F", "Tg3J", "Tg3K", "Tg3R", "Tg3V", "Tg3Z", "Tg3a",
                "Tg3d", "Tg3h", "Tg3i", "Tg3l", "Tg3p", "Tg3q", "Tg3t", "Tg3x", "Tg3y",
                "Tg43", "TG0P", "TG0D", "TG0H", "TG0T", "TG1P", "TG1D"
            ]
        case .ssd:
            return ["TH0A", "TH0B", "TH0x", "TH1A", "TN0D", "TN0P", "Ts0P"]
        case .battery:
            return ["TB0T", "TB1T", "TB2T", "TB0Z", "TB1Z"]
        case .memory:
            return [
                "Tm00", "Tm01", "Tm02", "Tm04", "Tm05", "Tm06", "Tm08", "Tm09", "Tm0A",
                "Tm0C", "Tm0D", "Tm0E", "Tm0G", "Tm0K", "Tm0O", "Tm0R", "Tm0U", "Tm0X",
                "Tm0a", "Tm0d", "Tm0g", "Tm0j", "Tm0m", "Tm0p", "Tm0u", "Tm0y", "Tm1E",
                "Tm1I", "Tm1M", "Tm1Q", "Tm1U", "Tm1Y", "Tm1c", "Tm1g", "Tm1k", "Tm1o",
                "Tm1s", "Tm1x", "Tm21", "Tm25", "Tm29", "Tm2D", "Tm2H", "Tm2L", "Tm2P",
                "Tm2T", "Tm2j", "Tm2n", "TM0P", "TM0S", "TM0V", "TM1P", "TM1S", "TM1V"
            ]
        case .wifi:
            return ["TW0P", "TW1P", "TA0P", "Ta0P"]
        }
    }

    private func writeUInt16(_ key: String, value: UInt16) -> Bool {
        writeKey(key, bytes: [UInt8(value >> 8), UInt8(value & 0x00ff)])
    }

    private func writeUInt8(_ key: String, value: UInt8) -> Bool {
        writeKey(key, bytes: [value])
    }

    private func fanModeKey(for index: Int) -> String? {
        let uppercaseKey = "F\(index)Md"
        if readKeyInfo(uppercaseKey) != nil {
            return uppercaseKey
        }

        let lowercaseKey = "F\(index)md"
        if readKeyInfo(lowercaseKey) != nil {
            return lowercaseKey
        }

        return nil
    }

    private func writeFanNumber(_ key: String, value: Double) -> Bool {
        guard let keyInfo = readKeyInfo(key) else { return false }

        if keyInfo.dataType == smcKey("fpe2") {
            let scaled = UInt16(max(0, min(Double(UInt16.max), value * 4.0)))
            return writeUInt16(key, value: scaled)
        }

        if keyInfo.dataType == smcKey("flt ") {
            let bitPattern = Float(max(0, value)).bitPattern
            let bytes = [
                UInt8(bitPattern & 0x000000ff),
                UInt8((bitPattern >> 8) & 0x000000ff),
                UInt8((bitPattern >> 16) & 0x000000ff),
                UInt8((bitPattern >> 24) & 0x000000ff)
            ]
            return writeKey(key, bytes: bytes)
        }

        return false
    }

    private func readKey(_ key: String) -> [UInt8]? {
        guard connection != 0, let keyInfo = readKeyInfo(key) else { return nil }
        return readKey(key, keyInfo: keyInfo)
    }

    private func readKey(_ key: String, keyInfo: SMCKeyInfoData) -> [UInt8]? {
        guard connection != 0, keyInfo.dataSize <= 32 else { return nil }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = smcKey(key)
        input.keyInfo = keyInfo
        input.data8 = commandReadBytes

        guard call(input: &input, output: &output) else { return nil }
        return output.bytes.array.prefix(Int(keyInfo.dataSize)).map { $0 }
    }

    private func writeKey(_ key: String, bytes: [UInt8]) -> Bool {
        guard connection != 0, var keyInfo = readKeyInfo(key) else { return false }

        keyInfo.dataSize = UInt32(bytes.count)

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = smcKey(key)
        input.keyInfo = keyInfo
        input.data8 = commandWriteBytes
        input.bytes = SMCBytes(bytes)

        return call(input: &input, output: &output)
    }

    private func readKeyInfo(_ key: String) -> SMCKeyInfoData? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = smcKey(key)
        input.data8 = commandReadKeyInfo

        guard call(input: &input, output: &output) else { return nil }
        return output.keyInfo
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> Bool {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride

        let result = IOConnectCallStructMethod(
            connection,
            kernelIndexSMC,
            &input,
            inputSize,
            &output,
            &outputSize
        )

        return result == KERN_SUCCESS && output.result == 0
    }

    private func smcKey(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(UInt32(0)) { result, byte in
            (result << 8) | UInt32(byte)
        }
    }
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var reserved: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

private struct SMCBytes {
    var value: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    init() {}

    init(_ bytes: [UInt8]) {
        var padded = Array(bytes.prefix(32))
        padded.append(contentsOf: Array(repeating: 0, count: max(0, 32 - padded.count)))
        value = (
            padded[0], padded[1], padded[2], padded[3], padded[4], padded[5], padded[6], padded[7],
            padded[8], padded[9], padded[10], padded[11], padded[12], padded[13], padded[14], padded[15],
            padded[16], padded[17], padded[18], padded[19], padded[20], padded[21], padded[22], padded[23],
            padded[24], padded[25], padded[26], padded[27], padded[28], padded[29], padded[30], padded[31]
        )
    }

    var array: [UInt8] {
        [
            value.0, value.1, value.2, value.3, value.4, value.5, value.6, value.7,
            value.8, value.9, value.10, value.11, value.12, value.13, value.14, value.15,
            value.16, value.17, value.18, value.19, value.20, value.21, value.22, value.23,
            value.24, value.25, value.26, value.27, value.28, value.29, value.30, value.31
        ]
    }
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes = SMCBytes()
}
