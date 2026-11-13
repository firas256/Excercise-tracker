import AVFoundation

/// Spoken instructions through the watch speaker, used when the iPhone isn't there to show them.
final class Speaker {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()

    var isEnabled: Bool { WatchSettings.speakInstructions }

    func say(_ text: String) {
        guard isEnabled else { return }
        DispatchQueue.main.async {
            if self.synthesizer.isSpeaking { self.synthesizer.stopSpeaking(at: .immediate) }
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            self.synthesizer.speak(utterance)
        }
    }

    func stop() {
        DispatchQueue.main.async { self.synthesizer.stopSpeaking(at: .immediate) }
    }
}
