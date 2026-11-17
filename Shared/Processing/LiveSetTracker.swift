import Foundation

enum TrackerEvent {
    case setStarted
    /// Rep count changed. `lastRep` is the most recent completed rep.
    case repsUpdated(count: Int, lastRep: RepMetrics?)
    /// A rep was too short (under half the required range) and wasn't counted.
    case repNotCounted(RepMetrics)
    case exerciseGuess([ExerciseCandidate])
    case setCompleted(CompletedSet)
    case setDiscarded(reason: String)
}

struct CompletedSet {
    var startTime: Double
    var endTime: Double
    var analysis: SetAnalysis
    /// Arm-frame samples of the set (kept for optional ML training export).
    var samples: [ArmSample]
}

/// Real-time set tracker. Feed it arm-frame samples (≈50 Hz) and it emits events:
/// automatic set start (movement), rep updates (re-analysed twice a second), exercise guesses,
/// and set completion after a few seconds of rest.
final class LiveSetTracker {
    struct Configuration {
        var restTimeout: Double = 5
        var minimumReps = 2
        var analysisInterval: Double = 0.5
        /// Motion energy needed to start a set.
        var activationThreshold: Double = 0.4
        /// Seconds of still data kept before movement starts (helps find the resting position).
        var preRoll: Double = 1.5
        var maxSetDuration: Double = 240
    }

    var configuration: Configuration
    var analyzer: SetAnalyzer
    /// When set, classification is skipped and this exercise is used.
    var lockedExercise: ExerciseType?

    private(set) var isActive = false
    private(set) var lastAnalysis: SetAnalysis = .empty
    private var buffer: [ArmSample] = []
    private var preRollBuffer: [ArmSample] = []
    private var energy = 0.0
    private var lastTime: Double?
    private var aboveSince: Double?
    private var lastMotionTime = 0.0
    private var lastAnalysisTime = 0.0
    private var announcedReps = 0
    private var announcedTooShort = 0
    private var announcedGuess: ExerciseType?

    init(configuration: Configuration = Configuration(), analyzer: SetAnalyzer = SetAnalyzer()) {
        self.configuration = configuration
        self.analyzer = analyzer
    }

    private var threshold: Double {
        configuration.activationThreshold * (lockedExercise?.trackingQuality == .limited ? 0.35 : 1)
    }

    var currentSetDuration: Double {
        guard isActive, let f = buffer.first, let l = buffer.last else { return 0 }
        return l.t - f.t
    }

    func ingest(_ s: ArmSample) -> [TrackerEvent] {
        let dt = lastTime.map { max(0.001, min(0.2, s.t - $0)) } ?? 0.02
        lastTime = s.t
        let alpha = dt / (0.25 + dt)
        energy = alpha * s.motionEnergy + (1 - alpha) * energy

        var events: [TrackerEvent] = []
        if !isActive {
            preRollBuffer.append(s)
            if let first = preRollBuffer.first, s.t - first.t > configuration.preRoll {
                preRollBuffer.removeFirst(max(1, preRollBuffer.count / 10))
            }
            if energy > threshold {
                if aboveSince == nil { aboveSince = s.t }
                if let since = aboveSince, s.t - since >= 0.3 {
                    isActive = true
                    buffer = preRollBuffer
                    preRollBuffer.removeAll()
                    lastMotionTime = s.t
                    lastAnalysisTime = s.t
                    announcedReps = 0
                    announcedTooShort = 0
                    announcedGuess = nil
                    lastAnalysis = .empty
                    events.append(.setStarted)
                }
            } else {
                aboveSince = nil
            }
            return events
        }

        buffer.append(s)
        if energy > threshold * 0.6 { lastMotionTime = s.t }

        if s.t - lastAnalysisTime >= configuration.analysisInterval {
            lastAnalysisTime = s.t
            events.append(contentsOf: runAnalysis())
        }

        let restedTooLong = s.t - lastMotionTime > configuration.restTimeout
        let tooLong = (buffer.first.map { s.t - $0.t } ?? 0) > configuration.maxSetDuration
        if restedTooLong || tooLong {
            events.append(finish(endingAt: restedTooLong ? lastMotionTime + 0.6 : s.t))
        }
        return events
    }

    /// Ends the current set now (e.g. the user tapped "Done").
    func finishSet() -> [TrackerEvent] {
        guard isActive else { return [] }
        return [finish(endingAt: buffer.last?.t ?? 0)]
    }

    /// Drops the current set without reporting it.
    func cancelSet() {
        resetToIdle()
    }

    private func runAnalysis() -> [TrackerEvent] {
        var events: [TrackerEvent] = []
        let analysis = analyzer.analyze(buffer, lockedExercise: lockedExercise)
        lastAnalysis = analysis
        // The live count only ever goes up (re-analysis can briefly disagree on the newest rep);
        // the final count is decided by the full analysis when the set ends.
        if analysis.repCount > announcedReps {
            announcedReps = analysis.repCount
            events.append(.repsUpdated(count: analysis.repCount, lastRep: analysis.reps.last))
        }
        // A new too-short rep that is also the most recent one: tell the user it didn't count.
        if analysis.tooShortReps.count > announcedTooShort, let short = analysis.tooShortReps.last {
            announcedTooShort = analysis.tooShortReps.count
            if short.startTime >= (analysis.reps.last?.startTime ?? -1) { events.append(.repNotCounted(short)) }
        }
        if lockedExercise == nil, analysis.repCount >= 3, let top = analysis.candidates.first, top.exercise != announcedGuess {
            announcedGuess = top.exercise
            events.append(.exerciseGuess(analysis.candidates))
        }
        return events
    }

    private func finish(endingAt endTime: Double) -> TrackerEvent {
        let samples = buffer.filter { $0.t <= endTime }
        let analysis = analyzer.analyze(samples, lockedExercise: lockedExercise)
        let start = samples.first?.t ?? endTime
        resetToIdle()
        if analysis.repCount < configuration.minimumReps {
            if analysis.tooShortReps.count >= configuration.minimumReps {
                return .setDiscarded(reason: "The reps were too short to count (under half the full range)")
            }
            return .setDiscarded(reason: "Fewer than \(configuration.minimumReps) reps detected")
        }
        if lockedExercise == nil, let f = analysis.features, FeatureExtractor.looksLikeWalking(f) {
            return .setDiscarded(reason: "Looked like walking")
        }
        return .setCompleted(CompletedSet(startTime: start, endTime: endTime, analysis: analysis, samples: samples))
    }

    private func resetToIdle() {
        isActive = false
        buffer.removeAll()
        preRollBuffer.removeAll()
        aboveSince = nil
        announcedReps = 0
        announcedTooShort = 0
        announcedGuess = nil
    }
}
