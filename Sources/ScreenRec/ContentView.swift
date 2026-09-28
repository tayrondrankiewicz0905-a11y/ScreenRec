import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var recorder: RecordingManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ScreenRec")
                        .font(.title2.bold())
                    Text(recorder.isRecording ? "Aufnahme läuft" : "Bereit")
                        .foregroundStyle(recorder.isRecording ? .red : .secondary)
                }
                Spacer()
                if recorder.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                }
            }

            Divider()

            Text("Aufnahme")
                .font(.headline)

            Picker("Quelle", selection: $recorder.captureMode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if recorder.captureMode == .window {
                Button {
                    recorder.chooseWindow()
                } label: {
                    Label(recorder.selectedWindowTitle ?? "Fenster auswählen…",
                          systemImage: "macwindow")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 8) {
                Toggle("Mikrofon", isOn: $recorder.microphoneEnabled)
                Toggle("Systemaudio", isOn: $recorder.systemAudioEnabled)
                Toggle("Mauszeiger", isOn: $recorder.cursorEnabled)
            }
            .toggleStyle(.switch)

            Divider()

            HStack {
                Label(recorder.elapsedText, systemImage: "timer")
                    .monospacedDigit()
                Spacer()
                Text(recorder.outputFolder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                recorder.chooseOutputFolder()
            } label: {
                Label("Speicherort ändern", systemImage: "folder")
            }
            .buttonStyle(.plain)

            if let error = recorder.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start()
                }
            } label: {
                HStack {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle.fill")
                    Text(recorder.isRecording ? "Aufnahme stoppen" : "Aufnahme starten")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(recorder.isRecording ? .red : .accentColor)

            HStack {
                Button("Aufnahmen öffnen") {
                    NSWorkspace.shared.open(recorder.outputFolder)
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Beenden") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
            }
            .font(.caption)
        }
        .padding(.horizontal, 16)
    }
}
