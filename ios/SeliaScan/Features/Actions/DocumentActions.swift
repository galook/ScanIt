import Foundation
import AVFoundation
import UIKit

enum ClipboardService {
    static func copySensitive(_ value: String) { UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: value]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]) }
}
@MainActor final class ReadAllPagesService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    func read(_ pages: [String], language: SpeechLanguage = .automatic) { let locale = language.identifier ?? Locale.current.identifier; for page in pages { let utterance = AVSpeechUtterance(string: page); utterance.voice = AVSpeechSynthesisVoice(language: locale) ?? AVSpeechSynthesisVoice(language: DocumentLanguage.english.recognitionIdentifier); synthesizer.speak(utterance) } }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
