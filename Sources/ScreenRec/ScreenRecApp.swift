import SwiftUI
import AppKit

@main
struct ScreenRecApp: App {
    @StateObject private var recorder = RecordingManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(recorder)
                .frame(width: 360)
                .padding(.vertical, 8)
        } label: {
            Image(systemName: recorder.isRecording ? "record.circle.fill" : "record.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}
