import WatchKit

/// Haptic vocabulary used throughout the app so each cue always feels the same.
enum Haptics {
    private static func play(_ type: WKHapticType) {
        DispatchQueue.main.async { WKInterfaceDevice.current().play(type) }
    }

    /// A new calibration instruction is shown.
    static func nextInstruction() { play(.start) }
    /// Stillness detected – the hold has begun.
    static func holdStarted() { play(.click) }
    /// Pose captured successfully.
    static func poseCaptured() { play(.success) }
    /// Pose does not match the instruction.
    static func wrongPose() { play(.failure) }
    /// Calibration complete.
    static func calibrationDone() { play(.notification) }

    static func goodRep() { play(.click) }
    static func flaggedRep() { play(.retry) }
    /// Too short (under half the full range): not counted.
    static func repNotCounted() { play(.failure) }
    static func setFinished() { play(.stop) }
}
