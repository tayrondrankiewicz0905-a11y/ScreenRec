import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import AppKit
import Combine

enum CaptureMode: String, CaseIterable, Identifiable {
    case display
    case window

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display: return "Bildschirm"
        case .window: return "Fenster"
        }
    }
}

final class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var captureMode: CaptureMode = .display
    @Published var microphoneEnabled = false
    @Published var systemAudioEnabled = true
    @Published var cursorEnabled = true
    @Published var selectedWindowTitle: String?
    @Published var errorMessage: String?
    @Published private(set) var elapsed: TimeInterval = 0

    var elapsedText: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var outputFolder: URL {
        get {
            if let saved = UserDefaults.standard.url(forKey: "outputFolder") {
                return saved
            }
            return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ScreenRec", isDirectory: true)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "outputFolder")
        }
    }

    private var stream: SCStream?
    private var selectedWindow: SCWindow?
    private let captureQueue = DispatchQueue(label: "com.tayron.screenrec.capture")
    private let writerQueue = DispatchQueue(label: "com.tayron.screenrec.writer")
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var writerStarted = false
    private var recordingURL: URL?
    private var timer: Timer?

    override init() {
        super.init()
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = url
        }
    }

    func chooseWindow() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let ownPID = ProcessInfo.processInfo.processIdentifier
                let windows = content.windows.filter {
                    $0.isOnScreen &&
                    $0.windowLayer == 0 &&
                    $0.owningApplication?.processID != ownPID &&
                    $0.frame.width >= 200 &&
                    $0.frame.height >= 100
                }

                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Fenster auswählen"
                    alert.informativeText = "Wähle das Fenster, das aufgenommen werden soll."
                    let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
                    for window in windows {
                        let app = window.owningApplication?.applicationName ?? "App"
                        let title = window.title.isEmpty ? app : "\(app) – \(window.title)"
                        popup.addItem(withTitle: title)
                    }
                    alert.accessoryView = popup
                    alert.addButton(withTitle: "Auswählen")
                    alert.addButton(withTitle: "Abbrechen")

                    guard alert.runModal() == .alertFirstButtonReturn,
                          !windows.isEmpty else { return }

                    let index = popup.indexOfSelectedItem
                    guard index >= 0 && index < windows.count else { return }

                    self.selectedWindow = windows[index]
                    let window = windows[index]
                    let app = window.owningApplication?.applicationName ?? "App"
                    self.selectedWindowTitle = window.title.isEmpty ? app : "\(app) – \(window.title)"
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Fenster konnten nicht geladen werden: \(error.localizedDescription)"
                }
            }
        }
    }

    func start() {
        errorMessage = nil

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                guard let display = content.displays.first else {
                    throw RecorderError.noDisplay
                }

                let filter: SCContentFilter
                let width: Int
                let height: Int

                if captureMode == .window {
                    guard let window = selectedWindow else {
                        await MainActor.run {
                            self.errorMessage = "Bitte zuerst ein Fenster auswählen."
                        }
                        return
                    }
                    filter = SCContentFilter(desktopIndependentWindow: window)
                    width = max(2, Int(window.frame.width * 2))
                    height = max(2, Int(window.frame.height * 2))
                } else {
                    filter = SCContentFilter(display: display, excludingWindows: [])
                    width = max(2, display.width)
                    height = max(2, display.height)
                }

                let config = SCStreamConfiguration()
                config.width = width
                config.height = height
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.queueDepth = 5
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = cursorEnabled
                config.capturesAudio = systemAudioEnabled
                config.captureMicrophone = microphoneEnabled
                config.sampleRate = 48_000
                config.channelCount = 2
                config.excludesCurrentProcessAudio = true

                let outputURL = makeOutputURL()
                let stream = SCStream(filter: filter, configuration: config, delegate: self)

                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
                if systemAudioEnabled {
                    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
                }
                if microphoneEnabled {
                    try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: captureQueue)
                }

                self.stream = stream
                self.recordingURL = outputURL

                try await stream.startCapture()

                await MainActor.run {
                    self.isRecording = true
                    self.elapsed = 0
                    self.timer?.invalidate()
                    self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                        self?.elapsed += 1
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
                    self.cleanupWriter()
                }
            }
        }
    }

    func stop() {
        guard let stream else { return }

        Task {
            do {
                try await stream.stopCapture()
            } catch {
                await MainActor.run {
                    self.errorMessage = "Aufnahme konnte nicht sauber beendet werden: \(error.localizedDescription)"
                }
            }

            await MainActor.run {
                self.isRecording = false
                self.timer?.invalidate()
                self.timer = nil
            }

            writerQueue.sync {
                self.finishWriter()
            }

            self.stream = nil
        }
    }

    private func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "ScreenRec_\(formatter.string(from: Date())).mp4"
        return outputFolder.appendingPathComponent(name)
    }

    private func prepareWriter(videoSample: CMSampleBuffer) throws {
        guard let recordingURL else { throw RecorderError.noOutputURL }
        guard let formatDescription = CMSampleBufferGetFormatDescription(videoSample) else {
            throw RecorderError.invalidVideoFormat
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)

        try? FileManager.default.removeItem(at: recordingURL)

        let writer = try AVAssetWriter(outputURL: recordingURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dimensions.width),
            AVVideoHeightKey: Int(dimensions.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(8_000_000, Int(dimensions.width * dimensions.height) / 2),
                AVVideoMaxKeyFrameIntervalKey: 120
            ]
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else {
            throw RecorderError.writerInput
        }
        writer.add(videoInput)

        // Audio inputs must be added before AVAssetWriter starts writing.
        if systemAudioEnabled {
            let input = makeAudioInput(sampleRate: 48_000, channels: 2)
            guard writer.canAdd(input) else { throw RecorderError.writerInput }
            writer.add(input)
            systemAudioInput = input
        }

        if microphoneEnabled {
            let input = makeAudioInput(sampleRate: 48_000, channels: 2)
            guard writer.canAdd(input) else { throw RecorderError.writerInput }
            writer.add(input)
            microphoneInput = input
        }

        self.writer = writer
        self.videoInput = videoInput

        guard writer.startWriting() else {
            throw writer.error ?? RecorderError.writerStart
        }

        self.writerStarted = false
    }

    private func makeAudioInput(sampleRate: Double, channels: Int) -> AVAssetWriterInput {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 192_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    private func append(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        writerQueue.async { [weak self] in
            guard let self else { return }

            if type == .screen {
                if self.writer == nil {
                    do {
                        try self.prepareWriter(videoSample: sampleBuffer)
                    } catch {
                        DispatchQueue.main.async {
                            self.errorMessage = "Video-Writer konnte nicht erstellt werden: \(error.localizedDescription)"
                        }
                        return
                    }
                }

                guard let writer = self.writer, let videoInput = self.videoInput else { return }

                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if !self.writerStarted {
                    writer.startSession(atSourceTime: timestamp)
                    self.writerStarted = true
                }

                if videoInput.isReadyForMoreMediaData {
                    videoInput.append(sampleBuffer)
                }
            } else {
                guard self.writer != nil, self.writerStarted else { return }

                let input = type == .microphone ? self.microphoneInput : self.systemAudioInput
                if let input, input.isReadyForMoreMediaData {
                    input.append(sampleBuffer)
                }
            }
        }
    }

    private func finishWriter() {
        guard let writer else {
            cleanupWriter()
            return
        }

        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()

        writer.finishWriting { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                if writer.status == .completed {
                    self.errorMessage = nil
                } else if let error = writer.error {
                    self.errorMessage = "Datei konnte nicht gespeichert werden: \(error.localizedDescription)"
                }
                self.cleanupWriter()
            }
        }
    }

    private func cleanupWriter() {
        writer = nil
        videoInput = nil
        systemAudioInput = nil
        microphoneInput = nil
        writerStarted = false
        recordingURL = nil
    }
}

extension RecordingManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        append(sampleBuffer, type: type)
    }
}

extension RecordingManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "ScreenCaptureKit wurde beendet: \(error.localizedDescription)"
            self.isRecording = false
            self.timer?.invalidate()
            self.timer = nil
        }

        writerQueue.async {
            self.finishWriter()
        }
    }
}

enum RecorderError: LocalizedError {
    case noDisplay
    case noOutputURL
    case invalidVideoFormat
    case writerInput
    case writerStart

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "Kein Bildschirm gefunden."
        case .noOutputURL: return "Kein Ausgabeordner festgelegt."
        case .invalidVideoFormat: return "Ungültiges Videoformat."
        case .writerInput: return "Video-Input konnte nicht hinzugefügt werden."
        case .writerStart: return "Video-Writer konnte nicht gestartet werden."
        }
    }
}
