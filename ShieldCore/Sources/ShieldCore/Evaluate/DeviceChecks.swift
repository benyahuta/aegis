// Pure mapping rules for the iPhone's measured checks (SPEC §6.1). The iOS app
// (ShieldiOS/Checks/iOSChecks.swift) calls LocalAuthentication and the VersionEvaluator; these
// functions turn what it got into `MeasuredResult`s, so the rules are unit-tested here.
// H7: anything that isn't a clear answer is `unknown`, never `pass`.

import Foundation
import LocalAuthentication

public enum DeviceAuthCheck {
    /// `passcode_set`: `canEvaluatePolicy(.deviceOwnerAuthentication)`.
    /// true → pass; `LAError.passcodeNotSet` → fail; any other error → unknown.
    public static func passcodeStatus(canEvaluate: Bool, errorCode: LAError.Code?) -> Status {
        if canEvaluate { return .pass }
        return errorCode == .passcodeNotSet ? .fail : .unknown
    }

    /// `biometrics_enrolled`: `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`.
    /// true → pass; `biometryNotEnrolled` → fail; `biometryNotAvailable` (and everything else,
    /// including no passcode, which the passcode card already covers) → unknown.
    public static func biometricsStatus(canEvaluate: Bool, errorCode: LAError.Code?) -> Status {
        if canEvaluate { return .pass }
        return errorCode == .biometryNotEnrolled ? .fail : .unknown
    }

    /// Reads the policy without prompting. `canEvaluatePolicy` never shows UI.
    public static func evaluate(_ policy: LAPolicy, context: LAContext = LAContext()) -> (Bool, LAError.Code?) {
        var error: NSError?
        let ok = context.canEvaluatePolicy(policy, error: &error)
        guard !ok, let error, error.domain == LAError.errorDomain else { return (ok, nil) }
        return (ok, LAError.Code(rawValue: error.code))
    }
}

/// Which sensor this iPhone has, so a fix step names the right Settings row: **Face ID &
/// Passcode** or **Touch ID & Passcode** (iPhone SE / iPhone Duo). Read once, never prompts.
public enum Biometry: String, Sendable, Hashable, CaseIterable {
    case faceID
    case touchID
    /// No sensor, an unknown kind, or not read (Mac, tests, demo states): the generic copy
    /// that names both rows is shown.
    case unknown

    /// Step keys that have a Face ID and a Touch ID wording, as (faceID, touchID).
    public static let stepVariants: [String: (faceID: String, touchID: String)] = [
        "step.ios.faceIDPasscode": ("step.ios.faceIDPasscode.faceID", "step.ios.touchIDPasscode"),
        "check.stolen_device_protection.ios.step.open": (
            "check.stolen_device_protection.ios.step.open.faceID",
            "check.stolen_device_protection.ios.step.open.touchID"),
        "check.biometrics_enrolled.ios.step.setUp": (
            "check.biometrics_enrolled.ios.step.setUp.faceID",
            "check.biometrics_enrolled.ios.step.setUp.touchID"),
    ]

    /// The step key to show on this device.
    public func stepKey(_ key: String) -> String {
        guard let variant = Self.stepVariants[key] else { return key }
        switch self {
        case .faceID: return variant.faceID
        case .touchID: return variant.touchID
        case .unknown: return key
        }
    }

    /// `LAContext.biometryType` is filled in by `canEvaluatePolicy`, whatever it returns
    /// (also when nothing is enrolled). `canEvaluatePolicy` never shows UI.
    public static func read(context: LAContext = LAContext()) -> Biometry {
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return from(context.biometryType)
    }

    public static func from(_ type: LABiometryType) -> Biometry {
        switch type {
        case .faceID: .faceID
        case .touchID: .touchID
        default: .unknown
        }
    }
}

extension VersionEvaluation {
    /// `os_patched` (urgent = an actively exploited bug with the fix out, so red, §5.1) and
    /// `device_supported`, ready for the StatusEngine.
    public func measuredResults(today: DateDay) -> [MeasuredResult] {
        [
            MeasuredResult(checkID: .osPatched, status: osPatched, checkedOn: today,
                           urgent: osPatched == .fail && patchOutcome == .updateExploited),
            MeasuredResult(checkID: .deviceSupported, status: deviceSupported, checkedOn: today),
        ]
    }
}

extension MacCheckOutcome {
    /// The StatusEngine input for one Mac outcome. A red tier override (actively exploited
    /// `os_patched`, or Screen Sharing open with CVE-2026-65400 unpatched) is `urgent`.
    public func measuredResult(today: DateDay) -> MeasuredResult {
        MeasuredResult(checkID: checkID, status: status, checkedOn: today, urgent: status == .fail && tierOverride == .red)
    }
}
