import AppKit
import AudioService
import Core
import DesignSystem
import MeetingsFeature
import RecordingFeature
import SettingsFeature
import SwiftUI

struct AppShell: View {
    @EnvironmentObject private var locale: LocaleManager
    @ObservedObject var model: AppModel
    @AppStorage("ember.sidebarWidth") private var sidebarWidth: Double = 266
    @State private var dragStartWidth: Double?
    @State private var keyMonitor: Any?

    private let minSidebar: Double = 220
    private let maxSidebar: Double = 460

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(route: $model.route, selectedMeetingId: $model.selectedMeetingId, meetings: model.store.meetings,
                    width: CGFloat(sidebarWidth),
                    isRecording: model.isRecordingActive,
                    recordingElapsed: model.engine.elapsed,
                    onTapRecording: { model.route = .home },
                    onRename: { model.renaming = $0 }, onDelete: { model.deleting = $0 })
            sidebarDivider
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 600)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: locale.language)
        .background(EmberColor.bg)
        .background(WindowConfigurator())
        .background(shortcuts)
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            dialogs
                .animation(.easeInOut(duration: 0.18), value: model.renaming)
                .animation(.easeInOut(duration: 0.18), value: model.deleting)
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                EmberToast(info: toast)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.toast)
        .onAppear { installKeyMonitor() }
        .onDisappear { if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil } }
    }

    /// Full-height draggable divider between the sidebar and the main content.
    private var sidebarDivider: some View {
        Rectangle().fill(EmberColor.border).frame(width: 1)
            .overlay(
                Color.clear.frame(width: 11).contentShape(Rectangle())
                    .onHover { $0 ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { v in
                                let start = dragStartWidth ?? sidebarWidth
                                if dragStartWidth == nil { dragStartWidth = sidebarWidth }
                                sidebarWidth = min(max(start + Double(v.translation.width), minSidebar), maxSidebar)
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            )
    }

    /// Hidden buttons hosting global shortcuts: ⌘R record toggle, ⌘, settings.
    private var shortcuts: some View {
        ZStack {
            Button("") {
                if model.isRecordingActive { model.stopRecording(language: locale.language) } else { model.startRecording() }
            }
            .keyboardShortcut("r", modifiers: .command)
            Button("") { model.route = .settings }
                .keyboardShortcut(",", modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            MainActor.assumeIsolated { handleKey(ev) }
        }
    }

    private func handleKey(_ ev: NSEvent) -> NSEvent? {
        if model.deleting != nil || model.renaming != nil { return ev }
        let editing = NSApp.keyWindow?.firstResponder is NSText
        if ev.modifierFlags.contains(.command), ev.keyCode == 51 {
            if model.route == .meetings, model.selectedMeetingId != nil { model.requestDeleteSelected(); return nil }
        }
        if !editing {
            if ev.keyCode == 126 { model.selectAdjacentMeeting(-1); return nil }
            if ev.keyCode == 125 { model.selectAdjacentMeeting(1); return nil }
        }
        return ev
    }

    @ViewBuilder private var dialogs: some View {
        if let m = model.renaming {
            RenameDialog(initial: m.title, title: locale.t("dialog.rename.title"),
                         confirmLabel: locale.t("common.save"), cancelLabel: locale.t("common.cancel"),
                         onConfirm: { model.rename(m.id, to: $0) }, onCancel: { model.renaming = nil })
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else if let m = model.deleting {
            EmberDialog(tone: .danger, title: locale.t("dialog.delete.title"), message: locale.t("dialog.delete.msg"),
                        confirmLabel: locale.t("common.delete"), cancelLabel: locale.t("common.cancel"),
                        onConfirm: { model.confirmDelete(m.id) }, onCancel: { model.deleting = nil })
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    @ViewBuilder private var mainContent: some View {
        switch model.route {
        case .home:
            if model.isRecordingActive {
                RecordingView(engine: model.engine, segments: model.liveSegments, onStop: { model.stopRecording(language: locale.language) })
            } else {
                HomeIdleView(isEmpty: model.store.meetings.isEmpty, onStart: model.startRecording)
            }
        case .meetings:
            if let id = model.selectedMeetingId, let meeting = model.meeting(id) {
                MeetingDetailContainer(model: model, meeting: meeting)
                    .id(id)
            } else {
                emptyPane
            }
        case .settings:
            SettingsView(transcription: model.transcription, summary: model.summary)
        }
    }

    private var emptyPane: some View {
        VStack {}
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(EmberColor.bg)
    }
}

/// Loads a meeting's transcript + summary OUT of the render path: the synchronous
/// SQLite reads run only when the selection or `model.revision` changes (via
/// `.task(id:)`), not on every `AppModel` publish (toast / processing / level bumps).
private struct MeetingDetailContainer: View {
    @ObservedObject var model: AppModel
    let meeting: Meeting
    @State private var segments: [TranscriptSegment] = []
    @State private var summary: MeetingSummary?

    var body: some View {
        MeetingDetailsView(
            meeting: meeting,
            segments: segments,
            summary: summary,
            isProcessing: model.isProcessing(meeting.id),
            summaryService: model.summary,
            onRegenerate: { model.regenerate(meetingId: meeting.id) },
            onRename: { model.rename(meeting.id, to: $0) }
        )
        .task(id: "\(meeting.id)#\(model.revision)") {
            segments = model.store.transcript(meetingId: meeting.id)
            summary = model.store.summary(meetingId: meeting.id)
        }
    }
}

/// Makes the window use a full-size content view so SwiftUI content reaches the
/// very top (under the transparent titlebar) — removes the empty top band.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { configure(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }
}
