import AVFoundation

enum RecorderState {
    case idle, recording, processing
}

@MainActor
final class AudioRecorder: ObservableObject {
    @Published var state: RecorderState = .idle
    @Published var permissionDenied = false
    @Published var level: Float = 0

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private(set) var recordingURL: URL?

    private var tempURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
    }

    // Uses AVAudioSession — works on iOS 15+ (not iOS-17-only AVAudioApplication)
    func requestPermission() async {
        let session = AVAudioSession.sharedInstance()
        let granted = await withCheckedContinuation { continuation in
            session.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        permissionDenied = !granted
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        guard session.recordPermission == .granted else {
            permissionDenied = true
            return
        }

        try? session.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
        try? session.setActive(true)

        let url = tempURL
        let settings: [String: Any] = [
            AVFormatIDKey:            Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey:          16000,
            AVNumberOfChannelsKey:    1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record()
            recordingURL = url
            state = .recording

            // MainActor.assumeIsolated fixes the Swift 6 Sendable warning:
            // Timer always fires on the main run loop, so it's safe to assert
            // main-actor isolation inside the callback.
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.recorder?.updateMeters()
                    let db = self.recorder?.averagePower(forChannel: 0) ?? -60
                    self.level = Float(max(0, (db + 60) / 60))
                }
            }
        } catch {
            state = .idle
        }
    }

    func stop() -> URL? {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        level = 0
        state = .processing
        let url = recordingURL
        recordingURL = nil
        return url
    }

    func cancel() {
        meterTimer?.invalidate()
        meterTimer = nil
        if let url = recorder?.url {
            recorder?.stop()
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        recordingURL = nil
        level = 0
        state = .idle
    }
}
