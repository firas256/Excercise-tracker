import Foundation

enum ExerciseCategory: String, Codable, CaseIterable, Sendable {
    case freeWeight
    case machine
    case bodyweight

    var displayName: String {
        switch self {
        case .freeWeight: return "Free weights"
        case .machine: return "Machines & cables"
        case .bodyweight: return "Bodyweight"
        }
    }
}

/// How well a wrist-worn sensor can observe the exercise.
enum TrackingQuality: String, Codable, Sendable {
    /// The wrist moves a lot – reliable counting and good feedback.
    case good
    /// Counting works, but feedback is less detailed.
    case moderate
    /// Hands are fixed (e.g. on a leg-press handle): choose it manually; counting is best-effort.
    case limited

    var displayName: String {
        switch self {
        case .good: return "Great"
        case .moderate: return "Good"
        case .limited: return "Limited"
        }
    }
}

enum ExerciseType: String, Codable, CaseIterable, Identifiable, Sendable {
    // Free weights
    case bicepCurl
    case hammerCurl
    case shoulderPress
    case lateralRaise
    case frontRaise
    case uprightRow
    case shrug
    case benchPress
    case chestFly
    case bentOverRow
    case deadlift
    case romanianDeadlift
    case squat
    case gobletSquat
    case lunge
    case overheadTricepsExtension
    case skullCrusher
    case kettlebellSwing
    // Machines & cables
    case latPulldown
    case seatedCableRow
    case chestPressMachine
    case pecDeck
    case tricepsPushdown
    case legPress
    case legExtension
    case legCurl
    // Bodyweight
    case pullUp
    case pushUp
    case dip

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bicepCurl: return "Bicep Curl"
        case .hammerCurl: return "Hammer Curl"
        case .shoulderPress: return "Shoulder Press"
        case .lateralRaise: return "Lateral Raise"
        case .frontRaise: return "Front Raise"
        case .uprightRow: return "Upright Row"
        case .shrug: return "Shrug"
        case .benchPress: return "Bench Press"
        case .chestFly: return "Dumbbell Fly"
        case .bentOverRow: return "Bent-over Row"
        case .deadlift: return "Deadlift"
        case .romanianDeadlift: return "Romanian Deadlift"
        case .squat: return "Barbell Squat"
        case .gobletSquat: return "Goblet Squat"
        case .lunge: return "Lunge"
        case .overheadTricepsExtension: return "Overhead Triceps Ext."
        case .skullCrusher: return "Skull Crusher"
        case .kettlebellSwing: return "Kettlebell Swing"
        case .latPulldown: return "Lat Pulldown"
        case .seatedCableRow: return "Seated Cable Row"
        case .chestPressMachine: return "Chest Press Machine"
        case .pecDeck: return "Pec Deck / Cable Fly"
        case .tricepsPushdown: return "Triceps Pushdown"
        case .legPress: return "Leg Press"
        case .legExtension: return "Leg Extension"
        case .legCurl: return "Leg Curl"
        case .pullUp: return "Pull-up"
        case .pushUp: return "Push-up"
        case .dip: return "Dip"
        }
    }

    var category: ExerciseCategory {
        switch self {
        case .latPulldown, .seatedCableRow, .chestPressMachine, .pecDeck, .tricepsPushdown,
             .legPress, .legExtension, .legCurl:
            return .machine
        case .pullUp, .pushUp, .dip:
            return .bodyweight
        default:
            return .freeWeight
        }
    }

    var muscleGroup: String {
        switch self {
        case .bicepCurl, .hammerCurl: return "Biceps"
        case .overheadTricepsExtension, .skullCrusher, .tricepsPushdown, .dip: return "Triceps"
        case .shoulderPress, .lateralRaise, .frontRaise, .uprightRow: return "Shoulders"
        case .shrug: return "Traps"
        case .benchPress, .chestFly, .chestPressMachine, .pecDeck, .pushUp: return "Chest"
        case .bentOverRow, .latPulldown, .seatedCableRow, .pullUp: return "Back"
        case .deadlift, .romanianDeadlift: return "Posterior chain"
        case .squat, .gobletSquat, .lunge, .legPress, .legExtension: return "Legs"
        case .legCurl: return "Hamstrings"
        case .kettlebellSwing: return "Full body"
        }
    }

    var symbolName: String {
        switch category {
        case .freeWeight: return "dumbbell.fill"
        case .machine: return "figure.strengthtraining.traditional"
        case .bodyweight: return "figure.strengthtraining.functional"
        }
    }

    var trackingQuality: TrackingQuality {
        switch self {
        case .bicepCurl, .hammerCurl, .lateralRaise, .frontRaise, .shoulderPress, .tricepsPushdown,
             .overheadTricepsExtension, .skullCrusher, .kettlebellSwing, .chestFly, .uprightRow,
             .benchPress, .latPulldown, .bentOverRow, .pecDeck:
            return .good
        case .deadlift, .romanianDeadlift, .squat, .gobletSquat, .lunge, .seatedCableRow,
             .chestPressMachine, .shrug:
            return .moderate
        case .legPress, .legExtension, .legCurl, .pullUp, .pushUp, .dip:
            return .limited
        }
    }

    /// Exercises the watch can reasonably guess on its own. "Limited" ones must be picked manually.
    var isAutoDetectable: Bool { trackingQuality != .limited }

    /// True when the first movement away from the starting position is the lowering (eccentric)
    /// phase, e.g. squat or bench press. Used to label tempo phases correctly.
    var eccentricFirst: Bool {
        switch self {
        case .benchPress, .chestFly, .romanianDeadlift, .squat, .gobletSquat, .lunge,
             .overheadTricepsExtension, .skullCrusher, .legPress, .pushUp, .dip:
            return true
        default:
            return false
        }
    }

    /// Short coaching cue shown in the library and on the watch.
    var formCue: String {
        switch self {
        case .bicepCurl: return "Elbows pinned to your sides, full extension at the bottom, squeeze at the top."
        case .hammerCurl: return "Thumbs up, elbows still, lower slowly."
        case .shoulderPress: return "Press straight overhead, lock out without arching your back."
        case .lateralRaise: return "Lift to shoulder height with a soft elbow, lead with the elbows."
        case .frontRaise: return "Raise to eye level with control, no swinging."
        case .uprightRow: return "Pull to chest height, elbows leading, wrists relaxed."
        case .shrug: return "Lift straight up, pause, lower slowly – don't roll the shoulders."
        case .benchPress: return "Lower to mid-chest under control, press up and slightly back."
        case .chestFly: return "Wide arc with a slight elbow bend, stretch without pain."
        case .bentOverRow: return "Flat back, pull towards the hip, squeeze the shoulder blade."
        case .deadlift: return "Bar close to the legs, push the floor away, lock out with the glutes."
        case .romanianDeadlift: return "Hinge at the hips with soft knees, feel the hamstrings stretch."
        case .squat: return "Knees track over toes, hit depth, drive up through mid-foot."
        case .gobletSquat: return "Chest up, elbows inside the knees at the bottom."
        case .lunge: return "Long step, back knee towards the floor, front knee over the ankle."
        case .overheadTricepsExtension: return "Elbows point up and stay narrow; lower behind the head slowly."
        case .skullCrusher: return "Upper arms vertical, bend only at the elbow."
        case .kettlebellSwing: return "Hinge, snap the hips – the arms just guide the bell."
        case .latPulldown: return "Pull to the upper chest, elbows down and back, control the return."
        case .seatedCableRow: return "Tall chest, pull to the belly button, don't rock back."
        case .chestPressMachine: return "Handles at mid-chest, press without locking the elbows hard."
        case .pecDeck: return "Hug a big tree – squeeze in the middle, slow on the way back."
        case .tricepsPushdown: return "Elbows glued to your sides, lock out at the bottom."
        case .legPress: return "Lower until knees reach ~90°, keep the lower back on the pad."
        case .legExtension: return "Full extension, pause, lower slowly."
        case .legCurl: return "Curl fully, keep hips down on the pad."
        case .pullUp: return "Full hang to chin over bar, no kipping."
        case .pushUp: return "Body in a straight line, chest to just above the floor."
        case .dip: return "Lower until upper arms are parallel to the floor, slight forward lean."
        }
    }

    static func grouped() -> [(ExerciseCategory, [ExerciseType])] {
        ExerciseCategory.allCases.map { cat in (cat, allCases.filter { $0.category == cat }) }
    }
}
