import SwiftUI
import Quartz
import ApplicationServices

@main
struct MacLevApp: App {
    @StateObject private var model = WindowFloaterModel()

    var body: some Scene {
        WindowGroup("macLev") {
            WindowFloaterView()
                .environmentObject(model)
                .frame(minWidth: 780, minHeight: 540)
                .onAppear {
                    model.refreshWindows()
                }
        }
    }
}

typealias CGSConnectionID = UInt32
typealias CGSWindowID = UInt32
typealias CGSWindowLevel = Int32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSSetWindowLevel")
func CGSSetWindowLevel(_ connection: CGSConnectionID, _ windowID: CGSWindowID, _ level: CGSWindowLevel) -> Int32

struct TrackedWindow: Identifiable, Hashable {
    let id: UInt32
    let pid: Int
    let owner: String
    let name: String
    let isOnScreen: Bool

    var displayName: String {
        if name.isEmpty {
            return "(No Title)"
        }
        return name
    }

    var subtitle: String {
        "\(owner) · pid:\(pid) · id:\(id)"
    }
}

@MainActor
final class WindowFloaterModel: ObservableObject {
    @Published var windows: [TrackedWindow] = []
    @Published var selectedWindowID: UInt32?
    @Published var pinnedWindowIDs: Set<UInt32> = []
    @Published var status = "Ready"

    private(set) var supportsWindowLevelAPI: Bool?

    private let normalLevel: CGSWindowLevel = CGSWindowLevel(CGWindowLevelForKey(.normalWindow))
    private let floatingLevel: CGSWindowLevel = CGSWindowLevel(CGWindowLevelForKey(.floatingWindow))

    func refreshWindows() {
        status = "Scanning visible windows..."

        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as NSArray? else {
            status = "Unable to read window list from system."
            windows = []
            return
        }

        var parsed: [TrackedWindow] = []

        for item in list.compactMap({ $0 as? [String: Any] }) {
            guard let windowID = item[kCGWindowNumber as String] as? UInt32 else { continue }
            guard let ownerName = item[kCGWindowOwnerName as String] as? String else { continue }
            let pid = item[kCGWindowOwnerPID as String] as? Int ?? 0
            if pid == ProcessInfo.processInfo.processIdentifier { continue }
            let owner = item[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let title = (item[kCGWindowName as String] as? String) ?? ""
            let isOnScreen = (item[kCGWindowIsOnscreen as String] as? Bool) ?? false
            let layer = item[kCGWindowLayer as String] as? Int ?? 0
            if layer < 0 { continue }
            parsed.append(TrackedWindow(id: windowID, pid: pid, owner: ownerName, name: title, isOnScreen: isOnScreen))
        }

        windows = parsed
            .filter { $0.isOnScreen || $0.name == "PiP" }
            .sorted { lhs, rhs in
                if lhs.owner == rhs.owner {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.owner.localizedCaseInsensitiveCompare(rhs.owner) == .orderedAscending
            }

        if selectedWindowID == nil || windows.first(where: { $0.id == selectedWindowID }) == nil {
            selectedWindowID = windows.first?.id
        }

        status = "Found \(windows.count) windows."
    }

    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        status = trusted ? "Accessibility trust granted." : "Accessibility not granted yet. Open System Settings > Privacy & Security > Accessibility to enable."
    }

    func hasAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }

    func pinSelected() {
        guard let id = selectedWindowID else {
            status = "Select a window first."
            return
        }
        applyFloating(id: id, pinned: true)
    }

    func unpinSelected() {
        guard let id = selectedWindowID else {
            status = "Select a window first."
            return
        }
        applyFloating(id: id, pinned: false)
    }

    func pinAllVisible() {
        var applied = 0
        for window in windows where window.isOnScreen {
            if !pinnedWindowIDs.contains(window.id) {
                if setWindowLevel(window.id, floating: true) {
                    pinnedWindowIDs.insert(window.id)
                    applied += 1
                }
            }
        }
        status = "Pinned \(applied) windows."
    }

    func unpinAll() {
        let toUnpin = Array(pinnedWindowIDs)
        for id in toUnpin {
            let _ = setWindowLevel(id, floating: false)
            pinnedWindowIDs.remove(id)
        }
        status = "Unpinned \(toUnpin.count) windows."
    }

    func applyFloating(id: UInt32, pinned: Bool) {
        if setWindowLevel(id, floating: pinned) {
            if pinned {
                pinnedWindowIDs.insert(id)
                status = "Pinned window id \(id)"
            } else {
                pinnedWindowIDs.remove(id)
                status = "Unpinned window id \(id)"
            }
        } else {
            status = "Could not change window level (requires private API behavior on this macOS version)."
        }
    }

    private func setWindowLevel(_ windowID: UInt32, floating: Bool) -> Bool {
        supportsWindowLevelAPI = true

        let level = floating ? floatingLevel : normalLevel
        let result = CGSSetWindowLevel(CGSMainConnectionID(), windowID, level)
        if result == 0 {
            return true
        }

        supportsWindowLevelAPI = false
        return false
    }

    var isPinned: (UInt32) -> Bool {
        { self.pinnedWindowIDs.contains($0) }
    }
}

struct WindowFloaterView: View {
    @EnvironmentObject private var model: WindowFloaterModel
    @State private var listSelection: Set<UInt32> = []

    var body: some View {
        VStack(spacing: 12) {
            header
            controls
            rowHeader
            windowList
            statusBar
            warning

            Divider()

            footer
        }
        .padding(14)
        .frame(minWidth: 780, minHeight: 540)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("macLev")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Floating utility for any visible window")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("Refresh windows", action: model.refreshWindows)
            Button("Request Accessibility", action: model.requestAccessibilityPermission)
            Text("Accessibility status: \(model.hasAccessibility() ? "Trusted" : "Not trusted")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Pin") { model.pinSelected() }
                .buttonStyle(.borderedProminent)
            Button("Unpin") { model.unpinSelected() }
            Button("Pin all visible") { model.pinAllVisible() }
            Button("Unpin all") { model.unpinAll() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowHeader: some View {
        HStack {
            Text("Window")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Source")
                .font(.headline)
                .frame(width: 220, alignment: .leading)
            Text("Pinned")
                .font(.headline)
                .frame(width: 70, alignment: .leading)
        }
        .padding(.horizontal, 6)
    }

    private var windowList: some View {
        List(selection: $listSelection) {
            ForEach(model.windows) { window in
                WindowRow(window: window, isPinned: model.isPinned(window.id))
                    .tag(window.id)
            }
        }
        .onAppear {
            listSelection = model.selectedWindowID.map { Set([$0]) } ?? []
        }
        .onChange(of: listSelection) { selection in
            model.selectedWindowID = selection.first
        }
        .onChange(of: model.selectedWindowID) { selected in
            listSelection = selected.map { Set([$0]) } ?? []
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .frame(maxHeight: .infinity)
    }

    private var statusBar: some View {
        Text(model.status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Important")
                .font(.headline)
            Text("This app uses private CoreGraphics window-level APIs to request a floating state for non-own windows.\nSuch APIs are unsupported and can break in macOS updates.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note")
                .font(.headline)
            Text("It can only pin visible windows from other apps; behavior is app-by-app dependent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WindowRow: View {
    let window: TrackedWindow
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(window.displayName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(window.subtitle)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: 260, alignment: .leading)
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundStyle(isPinned ? .accentColor : .secondary)
                .frame(width: 70, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
