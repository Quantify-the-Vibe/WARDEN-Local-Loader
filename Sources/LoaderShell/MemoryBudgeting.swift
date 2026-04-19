import Darwin
import Foundation

struct MemoryBudgetConstants: Sendable {
    let loaderMemoryCeilingBytes: UInt64
    let hostReserveBytes: UInt64
    let generationHeadroomBytes: UInt64
    let reclaimSlackBytes: UInt64

    static let baseline = MemoryBudgetConstants(
        loaderMemoryCeilingBytes: 12 * 1_024 * 1_024 * 1_024,
        hostReserveBytes: 2 * 1_024 * 1_024 * 1_024,
        generationHeadroomBytes: 1 * 1_024 * 1_024 * 1_024,
        reclaimSlackBytes: 512 * 1_024 * 1_024
    )
}

struct MemoryBudgetSnapshot: Sendable {
    let measurementSource: String
    let appPID: Int32
    let helperPID: Int32?
    let appFootprintBytes: UInt64
    let helperFootprintBytes: UInt64
    let combinedFootprintBytes: UInt64
    let constants: MemoryBudgetConstants

    var asStatusPayload: [String: Any] {
        [
            "measurement_source": measurementSource,
            "app_pid": Int(appPID),
            "helper_pid": helperPID.map(Int.init) as Any,
            "app_footprint_bytes": appFootprintBytes,
            "helper_footprint_bytes": helperFootprintBytes,
            "current_footprint_bytes": combinedFootprintBytes,
            "ceiling_bytes": constants.loaderMemoryCeilingBytes,
            "host_reserve_bytes": constants.hostReserveBytes,
            "generation_headroom_bytes": constants.generationHeadroomBytes,
            "reclaim_slack_bytes": constants.reclaimSlackBytes,
        ]
    }

    var summaryText: String {
        """
        Source: \(measurementSource)
        App PID: \(appPID)
        Helper PID: \(helperPID.map(String.init) ?? "none")
        App Footprint: \(ByteCountFormatter.loaderString(for: appFootprintBytes))
        Helper Footprint: \(ByteCountFormatter.loaderString(for: helperFootprintBytes))
        Combined Footprint: \(ByteCountFormatter.loaderString(for: combinedFootprintBytes))
        Ceiling: \(ByteCountFormatter.loaderString(for: constants.loaderMemoryCeilingBytes))
        Host Reserve: \(ByteCountFormatter.loaderString(for: constants.hostReserveBytes))
        Generation Headroom: \(ByteCountFormatter.loaderString(for: constants.generationHeadroomBytes))
        Reclaim Slack: \(ByteCountFormatter.loaderString(for: constants.reclaimSlackBytes))
        """
    }
}

struct AdmissionDecision: Sendable {
    let result: String
    let reasonCode: String?
    let detail: String
    let measurementSource: String
    let currentFootprintBytes: UInt64
    let projectedModelCostBytes: UInt64
    let generationHeadroomBytes: UInt64
    let hostReserveBytes: UInt64
    let effectiveCeilingBytes: UInt64
    let projectedTotalBytes: UInt64

    var asStatusPayload: [String: Any] {
        [
            "admission_result": result,
            "reason_code": reasonCode as Any,
            "detail": detail,
            "measurement_source": measurementSource,
            "current_footprint_bytes": currentFootprintBytes,
            "projected_model_cost_bytes": projectedModelCostBytes,
            "generation_headroom_bytes": generationHeadroomBytes,
            "host_reserve_bytes": hostReserveBytes,
            "effective_ceiling_bytes": effectiveCeilingBytes,
            "projected_total_bytes": projectedTotalBytes,
        ]
    }

    var summaryText: String {
        """
        Result: \(result)
        Reason: \(reasonCode ?? "none")
        Detail: \(detail)
        Projected Model Cost: \(ByteCountFormatter.loaderString(for: projectedModelCostBytes))
        Projected Total: \(ByteCountFormatter.loaderString(for: projectedTotalBytes))
        Effective Ceiling: \(ByteCountFormatter.loaderString(for: effectiveCeilingBytes))
        """
    }
}

struct PostLoadVerificationDecision: Sendable {
    let result: String
    let reasonCode: String?
    let detail: String
    let measurementSource: String
    let measuredFootprintBytes: UInt64
    let effectiveCeilingBytes: UInt64

    var asStatusPayload: [String: Any] {
        [
            "verification_result": result,
            "reason_code": reasonCode as Any,
            "detail": detail,
            "measurement_source": measurementSource,
            "measured_footprint_bytes": measuredFootprintBytes,
            "effective_ceiling_bytes": effectiveCeilingBytes,
        ]
    }

    var summaryText: String {
        """
        Result: \(result)
        Reason: \(reasonCode ?? "none")
        Detail: \(detail)
        Measured Footprint: \(ByteCountFormatter.loaderString(for: measuredFootprintBytes))
        Effective Ceiling: \(ByteCountFormatter.loaderString(for: effectiveCeilingBytes))
        """
    }
}

struct ReclaimVerificationDecision: Sendable {
    let result: String
    let reasonCode: String?
    let detail: String
    let measurementSource: String
    let baselineFootprintBytes: UInt64
    let measuredFootprintBytes: UInt64
    let reclaimSlackBytes: UInt64

    var asStatusPayload: [String: Any] {
        [
            "verification_result": result,
            "reason_code": reasonCode as Any,
            "detail": detail,
            "measurement_source": measurementSource,
            "baseline_footprint_bytes": baselineFootprintBytes,
            "measured_footprint_bytes": measuredFootprintBytes,
            "reclaim_slack_bytes": reclaimSlackBytes,
        ]
    }

    var summaryText: String {
        """
        Result: \(result)
        Reason: \(reasonCode ?? "none")
        Detail: \(detail)
        Baseline Footprint: \(ByteCountFormatter.loaderString(for: baselineFootprintBytes))
        Measured Footprint: \(ByteCountFormatter.loaderString(for: measuredFootprintBytes))
        Reclaim Slack: \(ByteCountFormatter.loaderString(for: reclaimSlackBytes))
        """
    }
}

protocol ProcessMemoryMeasuring: Sendable {
    func footprintBytes(for pid: Int32) throws -> UInt64
}

enum ProcessMemoryMeasurementError: LocalizedError {
    case measurementUnavailable(pid: Int32)

    var errorDescription: String? {
        switch self {
        case let .measurementUnavailable(pid):
            return "resident_size measurement unavailable for pid \(pid)"
        }
    }
}

struct MacOSProcessMemoryMeasurer: ProcessMemoryMeasuring {
    func footprintBytes(for pid: Int32) throws -> UInt64 {
        var taskInfo = proc_taskinfo()
        let result = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            proc_pidinfo(
                pid,
                PROC_PIDTASKINFO,
                0,
                pointer,
                Int32(MemoryLayout<proc_taskinfo>.stride)
            )
        }
        guard result == Int32(MemoryLayout<proc_taskinfo>.stride) else {
            throw ProcessMemoryMeasurementError.measurementUnavailable(pid: pid)
        }
        return taskInfo.pti_resident_size
    }
}

protocol MemoryBudgetMonitoring: Sendable {
    func snapshot(helperPID: Int32?) throws -> MemoryBudgetSnapshot
}

protocol ModelCostEstimating: Sendable {
    func estimatedModelBytes(at modelPath: String) throws -> UInt64
}

struct LoaderMemoryBudgetMonitor: MemoryBudgetMonitoring {
    let appPID: Int32
    let constants: MemoryBudgetConstants
    let memoryMeasurer: any ProcessMemoryMeasuring

    init(
        appPID: Int32 = getpid(),
        constants: MemoryBudgetConstants = .baseline,
        memoryMeasurer: any ProcessMemoryMeasuring = MacOSProcessMemoryMeasurer()
    ) {
        self.appPID = appPID
        self.constants = constants
        self.memoryMeasurer = memoryMeasurer
    }

    func snapshot(helperPID: Int32?) throws -> MemoryBudgetSnapshot {
        let appFootprint = try memoryMeasurer.footprintBytes(for: appPID)
        let helperFootprint = try helperPID.map { try memoryMeasurer.footprintBytes(for: $0) } ?? 0
        return MemoryBudgetSnapshot(
            measurementSource: "resident_size",
            appPID: appPID,
            helperPID: helperPID,
            appFootprintBytes: appFootprint,
            helperFootprintBytes: helperFootprint,
            combinedFootprintBytes: appFootprint + helperFootprint,
            constants: constants
        )
    }
}

enum ModelCostEstimatorError: LocalizedError {
    case modelPathUnreadable(String)

    var errorDescription: String? {
        switch self {
        case let .modelPathUnreadable(path):
            return "model path unreadable: \(path)"
        }
    }
}

struct FileSystemModelCostEstimator: ModelCostEstimating {
    func estimatedModelBytes(at modelPath: String) throws -> UInt64 {
        let rootURL = URL(fileURLWithPath: modelPath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ModelCostEstimatorError.modelPathUnreadable(modelPath)
        }

        var totalBytes: UInt64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            totalBytes += UInt64(size)
        }
        return totalBytes
    }
}

struct LoadAdmissionEvaluator: Sendable {
    let constants: MemoryBudgetConstants
    let physicalMemoryBytes: UInt64

    init(
        constants: MemoryBudgetConstants = .baseline,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        self.constants = constants
        self.physicalMemoryBytes = physicalMemoryBytes
    }

    func evaluate(snapshot: MemoryBudgetSnapshot, projectedModelCostBytes: UInt64) -> AdmissionDecision {
        let effectiveCeiling = effectiveCeilingBytes()
        let projectedTotal = snapshot.combinedFootprintBytes + projectedModelCostBytes + constants.generationHeadroomBytes
        if projectedTotal <= effectiveCeiling {
            return AdmissionDecision(
                result: "allowed",
                reasonCode: nil,
                detail: "Projected total is within the effective ceiling.",
                measurementSource: snapshot.measurementSource,
                currentFootprintBytes: snapshot.combinedFootprintBytes,
                projectedModelCostBytes: projectedModelCostBytes,
                generationHeadroomBytes: constants.generationHeadroomBytes,
                hostReserveBytes: constants.hostReserveBytes,
                effectiveCeilingBytes: effectiveCeiling,
                projectedTotalBytes: projectedTotal
            )
        }

        return AdmissionDecision(
            result: "denied",
            reasonCode: "memory_ceiling_exceeded",
            detail: "Projected total exceeds the effective ceiling before helper spawn.",
            measurementSource: snapshot.measurementSource,
            currentFootprintBytes: snapshot.combinedFootprintBytes,
            projectedModelCostBytes: projectedModelCostBytes,
            generationHeadroomBytes: constants.generationHeadroomBytes,
            hostReserveBytes: constants.hostReserveBytes,
            effectiveCeilingBytes: effectiveCeiling,
            projectedTotalBytes: projectedTotal
        )
    }

    func evaluatePostLoad(snapshot: MemoryBudgetSnapshot) -> PostLoadVerificationDecision {
        let effectiveCeiling = effectiveCeilingBytes()
        if snapshot.combinedFootprintBytes <= effectiveCeiling {
            return PostLoadVerificationDecision(
                result: "within_budget",
                reasonCode: nil,
                detail: "Measured post-load footprint is within the effective ceiling.",
                measurementSource: snapshot.measurementSource,
                measuredFootprintBytes: snapshot.combinedFootprintBytes,
                effectiveCeilingBytes: effectiveCeiling
            )
        }

        return PostLoadVerificationDecision(
            result: "over_budget",
            reasonCode: "post_load_budget_verification_failed",
            detail: "Measured post-load footprint exceeds the effective ceiling after helper ready.",
            measurementSource: snapshot.measurementSource,
            measuredFootprintBytes: snapshot.combinedFootprintBytes,
            effectiveCeilingBytes: effectiveCeiling
        )
    }

    func evaluateReclaim(
        baselineFootprintBytes: UInt64,
        snapshot: MemoryBudgetSnapshot
    ) -> ReclaimVerificationDecision {
        let permittedFootprint = baselineFootprintBytes + constants.reclaimSlackBytes
        if snapshot.combinedFootprintBytes <= permittedFootprint {
            return ReclaimVerificationDecision(
                result: "reclaimed",
                reasonCode: nil,
                detail: "Measured reset footprint returned within baseline plus reclaim slack.",
                measurementSource: snapshot.measurementSource,
                baselineFootprintBytes: baselineFootprintBytes,
                measuredFootprintBytes: snapshot.combinedFootprintBytes,
                reclaimSlackBytes: constants.reclaimSlackBytes
            )
        }

        return ReclaimVerificationDecision(
            result: "insufficient_reclaim",
            reasonCode: "reclaim_verification_failed",
            detail: "Measured reset footprint remains above baseline plus reclaim slack.",
            measurementSource: snapshot.measurementSource,
            baselineFootprintBytes: baselineFootprintBytes,
            measuredFootprintBytes: snapshot.combinedFootprintBytes,
            reclaimSlackBytes: constants.reclaimSlackBytes
        )
    }

    private func effectiveCeilingBytes() -> UInt64 {
        min(
            constants.loaderMemoryCeilingBytes,
            physicalMemoryBytes > constants.hostReserveBytes ? physicalMemoryBytes - constants.hostReserveBytes : 0
        )
    }
}

extension ByteCountFormatter {
    static func loaderString(for byteCount: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(byteCount))
    }
}
