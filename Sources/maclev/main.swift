import SwiftUI
import AVFoundation
import Foundation
import WebKit

@main
struct MaclevApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var model: BrowserModel

    init() {
        let sharedSettings = SettingsStore()
        _settings = StateObject(wrappedValue: sharedSettings)
        _model = StateObject(wrappedValue: BrowserModel(settings: sharedSettings))
    }

    var body: some Scene {
        WindowGroup("MacLev") {
            BrowserView()
                .environmentObject(model)
                .environmentObject(settings)
                .frame(minWidth: 520, minHeight: 340)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 860, height: 620)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(width: 760, height: 560)
                .background(SettingsWindowConfigurator())
        }
    }
}

enum BrowserCommand {
    case load(URL)
    case goBack
    case goForward
    case reload
    case stop
}

struct BrowserTabState: Identifiable {
    let id = UUID()
    var title: String
    var addressText: String
    var status: String
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var command: BrowserCommand?
    var commandToken = UUID()
}

enum PermissionPolicy: String, Codable, CaseIterable, Identifiable {
    case ask
    case allow
    case deny

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .ask:
            return "?"
        case .allow:
            return "✓"
        case .deny:
            return "×"
        }
    }

    var helpText: String {
        switch self {
        case .ask:
            return "Ask each time"
        case .allow:
            return "Always allow"
        case .deny:
            return "Always deny"
        }
    }
}

enum SitePermissionKind: String, Codable {
    case camera
    case microphone
}

struct SitePermissionRule: Codable, Identifiable, Hashable {
    let host: String
    var camera: PermissionPolicy
    var microphone: PermissionPolicy

    var id: String { host }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var startPage: String {
        didSet { persistIfReady() }
    }
    @Published var launchFloating: Bool {
        didSet { persistIfReady() }
    }
    @Published var defaultCameraPolicy: PermissionPolicy {
        didSet { persistIfReady() }
    }
    @Published var defaultMicrophonePolicy: PermissionPolicy {
        didSet { persistIfReady() }
    }
    @Published var siteRules: [SitePermissionRule] {
        didSet { persistIfReady() }
    }

    private let storageURL: URL
    private var isRestoring = true

    init() {
        let fileManager = Foundation.FileManager()
        let supportDirectory = fileManager.urls(
            for: Foundation.FileManager.SearchPathDirectory.applicationSupportDirectory,
            in: Foundation.FileManager.SearchPathDomainMask.userDomainMask
        ).first!
        let appDirectory = supportDirectory.appendingPathComponent("maclev", isDirectory: true)
        storageURL = appDirectory.appendingPathComponent("settings.json")

        startPage = "https://www.nasa.gov"
        launchFloating = true
        defaultCameraPolicy = .ask
        defaultMicrophonePolicy = .ask
        siteRules = []

        restore()
        isRestoring = false
    }

    func register(host: String?) {
        let normalizedHost = normalized(host)
        guard !normalizedHost.isEmpty else { return }
        guard !siteRules.contains(where: { $0.host == normalizedHost }) else { return }

        siteRules.append(
            SitePermissionRule(
                host: normalizedHost,
                camera: defaultCameraPolicy,
                microphone: defaultMicrophonePolicy
            )
        )
        siteRules.sort { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
    }

    func policy(for host: String?, kind: SitePermissionKind) -> PermissionPolicy {
        let normalizedHost = normalized(host)
        guard !normalizedHost.isEmpty else {
            return defaultPolicy(for: kind)
        }

        if let rule = siteRules.first(where: { $0.host == normalizedHost }) {
            return kind == .camera ? rule.camera : rule.microphone
        }

        return defaultPolicy(for: kind)
    }

    func setPolicy(for host: String, kind: SitePermissionKind, value: PermissionPolicy) {
        let normalizedHost = normalized(host)
        guard !normalizedHost.isEmpty else { return }

        if let index = siteRules.firstIndex(where: { $0.host == normalizedHost }) {
            if kind == .camera {
                siteRules[index].camera = value
            } else {
                siteRules[index].microphone = value
            }
        } else {
            var rule = SitePermissionRule(
                host: normalizedHost,
                camera: defaultCameraPolicy,
                microphone: defaultMicrophonePolicy
            )
            if kind == .camera {
                rule.camera = value
            } else {
                rule.microphone = value
            }
            siteRules.append(rule)
            siteRules.sort { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
        }
    }

    func setPolicies(for host: String, camera: PermissionPolicy, microphone: PermissionPolicy) {
        let normalizedHost = normalized(host)
        guard !normalizedHost.isEmpty else { return }

        if let index = siteRules.firstIndex(where: { $0.host == normalizedHost }) {
            siteRules[index].camera = camera
            siteRules[index].microphone = microphone
        } else {
            siteRules.append(SitePermissionRule(host: normalizedHost, camera: camera, microphone: microphone))
            siteRules.sort { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
        }
    }

    func clearSiteRules() {
        siteRules.removeAll()
    }

    private func defaultPolicy(for kind: SitePermissionKind) -> PermissionPolicy {
        kind == .camera ? defaultCameraPolicy : defaultMicrophonePolicy
    }

    private func normalized(_ host: String?) -> String {
        host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func persistIfReady() {
        guard !isRestoring else { return }
        persist()
    }

    private func persist() {
        let state = PersistedState(
            startPage: startPage,
            launchFloating: launchFloating,
            defaultCameraPolicy: defaultCameraPolicy,
            defaultMicrophonePolicy: defaultMicrophonePolicy,
            siteRules: siteRules
        )

        do {
            try Foundation.FileManager().createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(state)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSSound.beep()
        }
    }

    private func restore() {
        guard let data = try? Data(contentsOf: storageURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }

        startPage = state.startPage
        launchFloating = state.launchFloating
        defaultCameraPolicy = state.defaultCameraPolicy
        defaultMicrophonePolicy = state.defaultMicrophonePolicy
        siteRules = state.siteRules
    }

    private struct PersistedState: Codable {
        var startPage: String
        var launchFloating: Bool
        var defaultCameraPolicy: PermissionPolicy
        var defaultMicrophonePolicy: PermissionPolicy
        var siteRules: [SitePermissionRule]
    }
}

@MainActor
final class BrowserModel: ObservableObject {
    let settings: SettingsStore

    @Published var tabs: [BrowserTabState]
    @Published var selectedTabID: UUID
    @Published var isFloating: Bool

    init(settings: SettingsStore) {
        self.settings = settings
        let firstTab = BrowserTabState(
            title: "New Tab",
            addressText: settings.startPage,
            status: "Ready.",
            canGoBack: false,
            canGoForward: false,
            isLoading: false
        )
        tabs = [firstTab]
        selectedTabID = firstTab.id
        isFloating = settings.launchFloating
    }

    private var untitledTabTitle: String {
        "New Tab"
    }

    var selectedIndex: Int? {
        tabs.firstIndex(where: { $0.id == selectedTabID })
    }

    private func index(for id: UUID) -> Int? {
        tabs.firstIndex(where: { $0.id == id })
    }

    private func state(for id: UUID) -> BrowserTabState? {
        guard let tabIndex = index(for: id) else {
            return nil
        }
        return tabs[tabIndex]
    }

    var selectedTab: BrowserTabState {
        guard
            let selectedIndex,
            tabs.indices.contains(selectedIndex)
        else {
            return BrowserTabState(
                title: untitledTabTitle,
                addressText: settings.startPage,
                status: "Ready.",
                canGoBack: false,
                canGoForward: false,
                isLoading: false
            )
        }
        return tabs[selectedIndex]
    }

    var canGoBack: Bool {
        selectedTab.canGoBack
    }

    var canGoForward: Bool {
        selectedTab.canGoForward
    }

    var isLoading: Bool {
        selectedTab.isLoading
    }

    var addressText: String {
        selectedTab.addressText
    }

    var status: String {
        selectedTab.status
    }

    var command: BrowserCommand? {
        selectedTab.command
    }

    var commandToken: UUID {
        selectedTab.commandToken
    }

    func selectTab(_ id: UUID) {
        guard index(for: id) != nil else { return }
        selectedTabID = id
    }

    func openTab() {
        let newTab = BrowserTabState(
            title: untitledTabTitle,
            addressText: settings.startPage,
            status: "Ready.",
            canGoBack: false,
            canGoForward: false,
            isLoading: false
        )
        tabs.append(newTab)
        selectedTabID = newTab.id
    }

    func openTab(with address: String?) {
        let normalized = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextAddress = normalized?.isEmpty == false ? normalized! : settings.startPage

        let newTab = BrowserTabState(
            title: untitledTabTitle,
            addressText: nextAddress,
            status: "Ready.",
            canGoBack: false,
            canGoForward: false,
            isLoading: false
        )

        tabs.append(newTab)
        selectedTabID = newTab.id

        if let address = URL(string: nextAddress) {
            issue(.load(address), for: newTab.id)
        }
    }

    func closeSelectedTab() {
        closeTab(selectedTabID)
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        guard let removedIndex = index(for: id) else { return }

        tabs.remove(at: removedIndex)

        if selectedTabID == id {
            let fallbackIndex = min(max(0, removedIndex - 1), tabs.count - 1)
            selectedTabID = tabs[fallbackIndex].id
        }
    }

    func selectNextTab() {
        guard let selectedIndex else { return }
        let next = min(selectedIndex + 1, tabs.count - 1)
        selectedTabID = tabs[next].id
    }

    func selectPreviousTab() {
        guard let selectedIndex else { return }
        let previous = max(selectedIndex - 1, 0)
        selectedTabID = tabs[previous].id
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedTabID = tabs[index].id
    }

    func loadAddress() {
        loadAddress(for: selectedTabID)
    }

    func loadAddress(for tabID: UUID) {
        guard let tabIndex = index(for: tabID) else { return }
        let raw = tabs[tabIndex].addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            setStatus("Address is empty.", for: tabID)
            return
        }

        var candidate = raw
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }

        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else {
            setStatus("Enter a valid http, https, or file URL.", for: tabID)
            return
        }

        setAddress(url.absoluteString, for: tabID)
        settings.startPage = url.absoluteString
        issue(.load(url), for: tabID)
    }

    func goBack() {
        guard let selectedIndex else { return }
        guard tabs[selectedIndex].canGoBack else { return }
        issue(.goBack, for: selectedTabID)
    }

    func goForward() {
        guard let selectedIndex else { return }
        guard tabs[selectedIndex].canGoForward else { return }
        issue(.goForward, for: selectedTabID)
    }

    func reloadOrStop() {
        issue(isLoading ? .stop : .reload, for: selectedTabID)
    }

    func setFloating(_ value: Bool) {
        isFloating = value
        settings.launchFloating = value
    }

    func addressBinding(for tabID: UUID) -> Binding<String> {
        Binding(
            get: { self.state(for: tabID)?.addressText ?? "" },
            set: { newValue in
                self.update(tabID) { tab in
                    tab.addressText = newValue
                }
            }
        )
    }

    func statusBinding(for tabID: UUID) -> Binding<String> {
        Binding(
            get: { self.state(for: tabID)?.status ?? "" },
            set: { newValue in
                self.update(tabID) { tab in
                    tab.status = newValue
                }
            }
        )
    }

    func canGoBackBinding(for tabID: UUID) -> Binding<Bool> {
        Binding(
            get: { self.state(for: tabID)?.canGoBack ?? false },
            set: { newValue in
                self.update(tabID) { tab in
                    tab.canGoBack = newValue
                }
            }
        )
    }

    func canGoForwardBinding(for tabID: UUID) -> Binding<Bool> {
        Binding(
            get: { self.state(for: tabID)?.canGoForward ?? false },
            set: { newValue in
                self.update(tabID) { tab in
                    tab.canGoForward = newValue
                }
            }
        )
    }

    func isLoadingBinding(for tabID: UUID) -> Binding<Bool> {
        Binding(
            get: { self.state(for: tabID)?.isLoading ?? false },
            set: { newValue in
                self.update(tabID) { tab in
                    tab.isLoading = newValue
                }
            }
        )
    }

    func commandBinding(for tabID: UUID) -> Binding<BrowserCommand?> {
        Binding(
            get: { self.state(for: tabID)?.command },
            set: { newValue in
                self.update(tabID) { tab in
                    tab.command = newValue
                }
            }
        )
    }

    func commandTokenBinding(for tabID: UUID) -> Binding<UUID> {
        Binding(
            get: { self.state(for: tabID)?.commandToken ?? UUID() },
            set: { newValue in
                self.update(tabID) { tab in
                    tab.commandToken = newValue
                }
            }
        )
    }

    func updateTitle(_ title: String, for tabID: UUID) {
        let fallback = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = fallback.isEmpty ? untitledTabTitle : fallback
        update(tabID) {
            $0.title = trimmed
        }
    }

    func setAddress(_ address: String, for tabID: UUID) {
        update(tabID) { $0.addressText = address }
    }

    func setStatus(_ value: String, for tabID: UUID) {
        update(tabID) { $0.status = value }
    }

    func setCanGo(_ canGoBack: Bool, _ canGoForward: Bool, for tabID: UUID) {
        update(tabID) {
            $0.canGoBack = canGoBack
            $0.canGoForward = canGoForward
        }
    }

    func setLoading(_ value: Bool, for tabID: UUID) {
        update(tabID) { $0.isLoading = value }
    }

    func clearCommand(for tabID: UUID) {
        update(tabID) { $0.command = nil }
    }

    private func issue(_ nextCommand: BrowserCommand, for tabID: UUID) {
        update(tabID) {
            $0.command = nextCommand
            $0.commandToken = UUID()
        }
    }

    private func update(_ id: UUID, _ apply: (inout BrowserTabState) -> Void) {
        guard let index = index(for: id) else { return }
        apply(&tabs[index])
    }
}

struct BrowserView: View {
    @EnvironmentObject private var model: BrowserModel
    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabStrip

            Divider()

            fullWidthTopBar

            Divider()

            ZStack {
                ForEach(model.tabs) { tab in
                    BrowserWebView(
                        tabID: tab.id,
                        settings: model.settings,
                        onUpdateTitle: { title in
                            model.updateTitle(title, for: tab.id)
                        },
                        addressText: model.addressBinding(for: tab.id),
                        status: model.statusBinding(for: tab.id),
                        canGoBack: model.canGoBackBinding(for: tab.id),
                        canGoForward: model.canGoForwardBinding(for: tab.id),
                        isLoading: model.isLoadingBinding(for: tab.id),
                        command: model.commandBinding(for: tab.id),
                        commandToken: model.commandTokenBinding(for: tab.id)
                    )
                    .opacity(model.selectedTabID == tab.id ? 1 : 0)
                    .allowsHitTesting(model.selectedTabID == tab.id)
                    .id(tab.id)
                }
                keyboardShortcutCommands
                    .frame(width: 0, height: 0)
                    .opacity(0)
            }
        }
        .overlay(
            WindowBehaviorConfigurator(isFloating: Binding(
                get: { model.isFloating },
                set: { model.setFloating($0) }
            ))
            .frame(width: 0, height: 0)
            .allowsHitTesting(false),
            alignment: .topLeading
        )
        .onAppear {
            model.loadAddress()
        }
    }

    private var fullWidthTopBar: some View {
        HStack(spacing: 10) {
            backForwardControls

            addressBar

            floatingToggle
            newTabButton
        }
        .frame(height: 34)
        .padding(.leading, 76)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var keyboardShortcutCommands: some View {
        HStack {
            Button("") {
                addressFieldFocused = true
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("") {
                if model.isLoading {
                    model.reloadOrStop()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("") {
                model.closeSelectedTab()
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("") {
                model.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Button("") {
                model.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            ForEach(1..<10, id: \.self) { index in
                Button("") {
                    model.selectTab(at: index - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
            }
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.tabs) { tab in
                        let isSelected = model.selectedTabID == tab.id
                        HStack(spacing: 8) {
                            Text(tab.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.leading, 2)

                            if model.tabs.count > 1 {
                                Button {
                                    model.closeTab(tab.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 14, height: 14)
                                }
                                .buttonStyle(.plain)
                                .help("Close tab")
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .background(
                            isSelected
                                ? Color.accentColor.opacity(0.16)
                                : Color(NSColor.windowBackgroundColor).opacity(0.65)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onTapGesture {
                            model.selectTab(tab.id)
                        }
                        .help(tab.title)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.regularMaterial)
    }

    private var backForwardControls: some View {
        HStack(spacing: 0) {
                Button(action: model.goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 20)
                }
            .disabled(!model.canGoBack)
            .keyboardShortcut("[", modifiers: .command)
            .buttonStyle(.plain)

            Divider()

            Button(action: model.goForward) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 20)
            }
            .disabled(!model.canGoForward)
            .keyboardShortcut("]", modifiers: .command)
            .buttonStyle(.plain)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(height: 20)
    }

    private var addressBar: some View {
        HStack(spacing: 0) {
            TextField("https://www.nasa.gov", text: model.addressBinding(for: model.selectedTabID))
                .textFieldStyle(.plain)
                .focused($addressFieldFocused)
                .onSubmit {
                    model.loadAddress()
                }
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity)

            Divider()

            Button(action: model.reloadOrStop) {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .help(model.isLoading ? "Stop" : "Reload")
        }
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color(NSColor.separatorColor).opacity(0.34), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .frame(height: 24)
    }

    private var floatingToggle: some View {
        Toggle(isOn: Binding(
            get: { model.isFloating },
            set: { model.setFloating($0) }
        )) {
            Text("🛸")
                .font(.system(size: 10))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .scaleEffect(0.78)
        .labelsHidden()
        .help("Always on top")
    }

    private var newTabButton: some View {
        Button {
            model.openTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .help("New Tab")
        .keyboardShortcut("t", modifiers: .command)
    }
}

struct WindowBehaviorConfigurator: NSViewRepresentable {
    @Binding var isFloating: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(to: view.window)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView.window)
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.level = isFloating ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.styleMask.insert(.fullSizeContentView)
    }
}

struct BrowserWebView: NSViewRepresentable {
    let tabID: UUID
    let settings: SettingsStore
    let onUpdateTitle: (String) -> Void
    @Binding var addressText: String
    @Binding var status: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var command: BrowserCommand?
    @Binding var commandToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(
            settings: settings,
            updateAddress: { addressText = $0 },
            updateStatus: { status = $0 },
            updateHistory: { back, forward in
                canGoBack = back
                canGoForward = forward
            },
            updateLoading: { isLoading = $0 },
            updateTitle: onUpdateTitle
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.attach(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.attach(webView)

        guard let command else { return }
        guard context.coordinator.consumeCommandToken(commandToken) else { return }

        switch command {
        case .load(let url):
            webView.load(URLRequest(url: url))
        case .goBack:
            if webView.canGoBack {
                webView.goBack()
            }
        case .goForward:
            if webView.canGoForward {
                webView.goForward()
            }
        case .reload:
            webView.reload()
        case .stop:
            webView.stopLoading()
            DispatchQueue.main.async {
                self.command = nil
                self.isLoading = false
                self.status = "Stopped."
            }
        }

        if case .stop = command {
            return
        }

        DispatchQueue.main.async {
            self.command = nil
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private weak var webView: WKWebView?
        private var lastCommandToken: UUID?
        private let settings: SettingsStore
        private let updateAddress: (String) -> Void
        private let updateStatus: (String) -> Void
        private let updateHistory: (Bool, Bool) -> Void
        private let updateLoading: (Bool) -> Void
        private let updateTitle: (String) -> Void

        init(
            settings: SettingsStore,
            updateAddress: @escaping (String) -> Void,
            updateStatus: @escaping (String) -> Void,
            updateHistory: @escaping (Bool, Bool) -> Void,
            updateLoading: @escaping (Bool) -> Void,
            updateTitle: @escaping (String) -> Void
        ) {
            self.settings = settings
            self.updateAddress = updateAddress
            self.updateStatus = updateStatus
            self.updateHistory = updateHistory
            self.updateLoading = updateLoading
            self.updateTitle = updateTitle
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            DispatchQueue.main.async {
                self.updateHistory(webView.canGoBack, webView.canGoForward)
            }
        }

        func consumeCommandToken(_ token: UUID) -> Bool {
            if lastCommandToken == token {
                return false
            }
            lastCommandToken = token
            return true
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.updateLoading(true)
                self.updateStatus("Loading...")
                self.updateHistory(webView.canGoBack, webView.canGoForward)
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async {
                if let url = webView.url {
                    self.updateAddress(url.absoluteString)
                    self.settings.register(host: url.host)
                }
                self.updateHistory(webView.canGoBack, webView.canGoForward)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.updateLoading(false)
                self.updateAddress(webView.url?.absoluteString ?? "")
                if let title = webView.title, !title.isEmpty {
                    self.updateTitle(title)
                }
                self.updateStatus("Loaded.")
                self.updateHistory(webView.canGoBack, webView.canGoForward)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.updateLoading(false)
                self.updateStatus("Failed: \(error.localizedDescription)")
                self.updateHistory(webView.canGoBack, webView.canGoForward)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.updateLoading(false)
                self.updateStatus("Failed: \(error.localizedDescription)")
                self.updateHistory(webView.canGoBack, webView.canGoForward)
            }
        }

        @available(macOS 13.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            settings.register(host: origin.host)

            let host = origin.host
            let sitePolicy = effectivePolicy(for: host, type: type)

            switch sitePolicy {
            case .allow:
                requestAccess(for: type) { granted in
                    DispatchQueue.main.async {
                        self.updateStatus(granted ? "Media access allowed." : "Media access denied.")
                        decisionHandler(granted ? .grant : .deny)
                    }
                }
            case .deny:
                DispatchQueue.main.async {
                    self.updateStatus("Media access denied.")
                    decisionHandler(.deny)
                }
            case .ask:
                requestAccess(for: type) { granted in
                    DispatchQueue.main.async {
                        self.updateStatus(
                            granted ? "Media access allowed." : "Media access denied. Enable in macOS System Settings if needed."
                        )
                        decisionHandler(granted ? .grant : .deny)
                    }
                }
            }
        }

        private func effectivePolicy(for host: String, type: WKMediaCaptureType) -> PermissionPolicy {
            switch type {
            case .camera:
                return settings.policy(for: host, kind: .camera)
            case .microphone:
                return settings.policy(for: host, kind: .microphone)
            case .cameraAndMicrophone:
                let camera = settings.policy(for: host, kind: .camera)
                let microphone = settings.policy(for: host, kind: .microphone)
                if camera == .deny || microphone == .deny {
                    return .deny
                }
                if camera == .allow && microphone == .allow {
                    return .allow
                }
                return .ask
            @unknown default:
                return .ask
            }
        }

        private func requestAccess(for type: WKMediaCaptureType, completion: @escaping (Bool) -> Void) {
            switch type {
            case .camera:
                requestDeviceAccess(for: .video, completion: completion)
            case .microphone:
                requestDeviceAccess(for: .audio, completion: completion)
            case .cameraAndMicrophone:
                requestDeviceAccess(for: .video) { cameraGranted in
                    guard cameraGranted else {
                        completion(false)
                        return
                    }

                    self.requestDeviceAccess(for: .audio, completion: completion)
                }
            @unknown default:
                completion(false)
            }
        }

        private func requestDeviceAccess(for mediaType: AVMediaType, completion: @escaping (Bool) -> Void) {
            switch AVCaptureDevice.authorizationStatus(for: mediaType) {
            case .authorized:
                completion(true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    completion(granted)
                }
            case .denied, .restricted:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var selectedTab: SettingsTab = .general
    @State private var dataStatus = "Website data is kept locally until you clear it."

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 8) {
                            SVGIconView(svg: tab.icon, size: 24)
                                .frame(width: 28, height: 28)
                            Text(tab.title)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .background(selectedTab == tab ? Color(NSColor.controlAccentColor).opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .help(tab.title)
                }
            }
            .padding(14)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    generalTab
                case .permissions:
                    permissionsTab
                case .data:
                    dataTab
                }
            }
            .padding(18)
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(icon: AppSVG.home, title: "Start") {
                TextField("https://www.nasa.gov", text: $settings.startPage)
                    .textFieldStyle(.roundedBorder)
            }

            SettingsSection(icon: AppSVG.saucer, title: "Window") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $settings.launchFloating) {
                        Label("Always on top", systemImage: "arrow.up.right.square")
                    }
                    Text("Launch MacLev with the floating window style enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(icon: AppSVG.shield, title: "Defaults") {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            SVGIconView(svg: AppSVG.camera, size: 18)
                                .frame(width: 18, height: 18)
                            PolicyPicker(selection: $settings.defaultCameraPolicy)
                                .frame(width: 132)

                            SVGIconView(svg: AppSVG.microphone, size: 18)
                                .frame(width: 18, height: 18)
                            PolicyPicker(selection: $settings.defaultMicrophonePolicy)
                                .frame(width: 132)
                        }
                    }

                    Text("Defaults apply only when a site has no saved rule.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
            }

            SettingsSection(icon: AppSVG.globe, title: "Sites") {
                if settings.siteRules.isEmpty {
                    Text("No sites yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ScrollView {
                            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                                GridRow {
                                    Text("Site")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    HStack(spacing: 6) {
                                        SVGIconView(svg: AppSVG.camera, size: 14)
                                            .frame(width: 14, height: 14)
                                        Text("Camera")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 132, alignment: .leading)

                                    HStack(spacing: 6) {
                                        SVGIconView(svg: AppSVG.microphone, size: 14)
                                            .frame(width: 14, height: 14)
                                        Text("Microphone")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 132, alignment: .leading)
                                }

                                Divider()
                                    .gridCellUnsizedAxes(.horizontal)

                                ForEach(settings.siteRules) { rule in
                                    GridRow {
                                        Text(rule.host)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        PolicyPicker(
                                            selection: Binding(
                                                get: { settings.policy(for: rule.host, kind: .camera) },
                                                set: { settings.setPolicy(for: rule.host, kind: .camera, value: $0) }
                                            )
                                        )
                                        .frame(width: 132)

                                        PolicyPicker(
                                            selection: Binding(
                                                get: { settings.policy(for: rule.host, kind: .microphone) },
                                                set: { settings.setPolicy(for: rule.host, kind: .microphone, value: $0) }
                                            )
                                        )
                                        .frame(width: 132)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Spacer()
        }
    }

    private var dataTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(icon: AppSVG.storage, title: "Website Data") {
                HStack(spacing: 12) {
                    Button {
                        BrowserDataMaintenance.clearAllWebsiteData {
                            dataStatus = "Website data cleared."
                        }
                    } label: {
                        HStack(spacing: 8) {
                            SVGIconView(svg: AppSVG.trash, size: 16)
                                .frame(width: 16, height: 16)
                            Text("Clear")
                        }
                    }

                    Button {
                        settings.clearSiteRules()
                    } label: {
                        HStack(spacing: 8) {
                            SVGIconView(svg: AppSVG.reset, size: 16)
                                .frame(width: 16, height: 16)
                            Text("Reset")
                        }
                    }
                }

                Text(dataStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(window: view.window)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(window: nsView.window)
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case permissions
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .permissions:
            return "Permissions"
        case .data:
            return "Data"
        }
    }

    var icon: String {
        switch self {
        case .general:
            return AppSVG.sliders
        case .permissions:
            return AppSVG.shield
        case .data:
            return AppSVG.storage
        }
    }
}

struct SettingsSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SVGIconView(svg: icon, size: 18)
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.headline)
            }
            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct PolicyPicker: View {
    @Binding var selection: PermissionPolicy

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(PermissionPolicy.allCases) { policy in
                Text(policy.symbol)
                    .tag(policy)
                    .help(policy.helpText)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct SVGIconView: NSViewRepresentable {
    let svg: String
    let size: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "allowsLinkPreview")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = """
        <!doctype html>
        <html>
        <body style="margin:0;background:transparent;display:flex;align-items:center;justify-content:center;width:\(Int(size))px;height:\(Int(size))px;overflow:hidden;">
        \(svg)
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

enum BrowserDataMaintenance {
    static func clearAllWebsiteData(completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: allTypes) { records in
            store.removeData(ofTypes: allTypes, for: records) {
                completion()
            }
        }
    }
}

enum AppSVG {
    static let sliders = """
    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#6f737b" stroke-width="1.8" stroke-linecap="round">
      <line x1="5" y1="6" x2="19" y2="6"/><circle cx="9" cy="6" r="2.2" fill="#6f737b"/>
      <line x1="5" y1="12" x2="19" y2="12"/><circle cx="15" cy="12" r="2.2" fill="#6f737b"/>
      <line x1="5" y1="18" x2="19" y2="18"/><circle cx="11" cy="18" r="2.2" fill="#6f737b"/>
    </svg>
    """

    static let shield = """
    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#6f737b" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M12 3l7 3v5c0 4.5-3 8.5-7 10-4-1.5-7-5.5-7-10V6l7-3z"/>
      <path d="M9.5 12.5l1.8 1.8L15 10.6"/>
    </svg>
    """

    static let storage = """
    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#6f737b" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <ellipse cx="12" cy="6" rx="7" ry="3"/>
      <path d="M5 6v6c0 1.7 3.1 3 7 3s7-1.3 7-3V6"/>
      <path d="M5 12v6c0 1.7 3.1 3 7 3s7-1.3 7-3v-6"/>
    </svg>
    """

    static let home = """
    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#6f737b" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M4 11.5L12 5l8 6.5"/>
      <path d="M6.5 10.5V19h11v-8.5"/>
    </svg>
    """

    static let saucer = """
    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#6f737b" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
      <ellipse cx="12" cy="12.5" rx="7.5" ry="3.5"/>
      <path d="M9 10.5c.5-2 1.8-3.2 3-3.2s2.5 1.2 3 3.2"/>
      <path d="M8.5 16l-1.5 2.5M12 16.5v2.8M15.5 16l1.5 2.5"/>
    </svg>
    """

    static let camera = """
    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#6f737b" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M5 8h3l1.5-2h5L16 8h3v10H5z"/>
      <circle cx="12" cy="13" r="3.5"/>
    </svg>
    """

    static let microphone = """
    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#6f737b" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <rect x="9" y="4" width="6" height="10" rx="3"/>
      <path d="M7 11.5a5 5 0 0 0 10 0M12 16.5V20M9 20h6"/>
    </svg>
    """

    static let globe = """
    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#6f737b" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="12" cy="12" r="9"/>
      <path d="M3.5 12h17M12 3.2c2.6 2.5 4 5.7 4 8.8s-1.4 6.3-4 8.8c-2.6-2.5-4-5.7-4-8.8s1.4-6.3 4-8.8z"/>
    </svg>
    """

    static let trash = """
    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#6f737b" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M5 7h14M9 7V5h6v2M7 7l1 12h8l1-12"/>
      <path d="M10 10v6M14 10v6"/>
    </svg>
    """

    static let reset = """
    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#6f737b" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M20 6v5h-5"/>
      <path d="M19 11a7 7 0 1 0 2 5"/>
    </svg>
    """
}
