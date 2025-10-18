import Foundation
import Speech
import AVFoundation

class SpeechRecognizer: NSObject, ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    // Chiamato quando viene rilevata una pausa di 2s
    var onSilenceDetected: ((String) -> Void)?

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastTranscript: String = ""
    private var lastUpdateAt: Date = Date()
    private var didEmitResult: Bool = false

    override init() {
        if let it = SFSpeechRecognizer(locale: Locale(identifier: "it-IT")) {
            recognizer = it
        } else {
            recognizer = SFSpeechRecognizer()
        }
        super.init()
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { self?.authStatus = status }
            switch status {
            case .authorized:
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async { completion(granted) }
                }
            default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    func start() {
        guard !isRecording else { return }
        transcript = ""
        isRecording = true
        lastTranscript = ""
        lastUpdateAt = Date()
        didEmitResult = false

        do {
            let session = AVAudioSession.sharedInstance()
            #if targetEnvironment(simulator)
            // In Simulator alcuni device HAL non sono disponibili: usa playAndRecord e spokenAudio
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers, .allowBluetooth])
            #else
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            #endif
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            request = SFSpeechAudioBufferRecognitionRequest()
            request?.shouldReportPartialResults = true
            request?.taskHint = .dictation
            if let recognizer = recognizer {
                if recognizer.supportsOnDeviceRecognition {
                    request?.requiresOnDeviceRecognition = true
                }
            }

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            guard let recognizer = recognizer, let request = request else {
                stop()
                return
            }

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let r = result {
                    let newText = r.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        self?.transcript = newText
                        if newText != self?.lastTranscript {
                            self?.lastTranscript = newText
                            self?.lastUpdateAt = Date()
                        }
                    }
                    if r.isFinal {
                        let finalText = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                        self?.didEmitResult = true
                        self?.stop()
                        DispatchQueue.main.async { self?.onSilenceDetected?(finalText) }
                    }
                }
                if let _ = error {
                    let snapshot = self?.transcript.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    self?.stop()
                    if !(self?.didEmitResult ?? true) && !snapshot.isEmpty {
                        DispatchQueue.main.async { self?.onSilenceDetected?(snapshot) }
                        self?.didEmitResult = true
                    }
                }
            }

            // Avvia il timer di silenzio (controllo ogni 0.2s)
            silenceTimer?.invalidate()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self = self, self.isRecording else { return }
                if Date().timeIntervalSince(self.lastUpdateAt) >= 2.0 {
                    let text = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Segnala che abbiamo già emesso un risultato per evitare fallback duplicati
                    self.didEmitResult = true
                    self.stop()
                    DispatchQueue.main.async { self.onSilenceDetected?(text) }
                }
            }
        } catch {
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        // Disattiva sessione
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        // Fallback: se abbiamo testo ma non è stato emesso, invia adesso
        let snapshot = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !didEmitResult && !snapshot.isEmpty {
            DispatchQueue.main.async { self.onSilenceDetected?(snapshot) }
            didEmitResult = true
        }
    }
}
