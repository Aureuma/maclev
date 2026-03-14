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
        WindowGroup("maclev") {
            BrowserView()
                .environmentObject(model)
                .environmentObject(settings)
                .frame(minWidth: 260, minHeight: 140)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 980, height: 680)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(width: 760, height: 560)
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
    @Published var addressText: String
    @Published var status = "Ready."
    @Published var isFloating: Bool
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var command: BrowserCommand?
    @Published var commandToken = UUID()

    let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        self.addressText = settings.startPage
        self.isFloating = settings.launchFloating
    }

    func loadAddress() {
        let raw = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            status = "Address is empty."
            return
        }

        var candidate = raw
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }

        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else {
            status = "Enter a valid http, https, or file URL."
            return
        }

        addressText = url.absoluteString
        settings.startPage = url.absoluteString
        issue(.load(url))
    }

    func goBack() {
        guard canGoBack else { return }
        issue(.goBack)
    }

    func goForward() {
        guard canGoForward else { return }
        issue(.goForward)
    }

    func reloadOrStop() {
        issue(isLoading ? .stop : .reload)
    }

    func setFloating(_ value: Bool) {
        isFloating = value
        settings.launchFloating = value
    }

    private func issue(_ nextCommand: BrowserCommand) {
        command = nextCommand
        commandToken = UUID()
    }
}

struct BrowserView: View {
    @EnvironmentObject private var model: BrowserModel
    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            topBar
            BrowserWebView(
                settings: model.settings,
                addressText: $model.addressText,
                status: $model.status,
                canGoBack: $model.canGoBack,
                canGoForward: $model.canGoForward,
                isLoading: $model.isLoading,
                command: $model.command,
                commandToken: $model.commandToken
            )
            .overlay(
                WindowBehaviorConfigurator(isFloating: Binding(
                    get: { model.isFloating },
                    set: { model.setFloating($0) }
                ))
                .frame(width: 0, height: 0)
                .allowsHitTesting(false),
                alignment: .topLeading
            )
        }
        .padding(12)
        .onAppear {
            model.loadAddress()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: model.goBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack)
            .keyboardShortcut("[", modifiers: .command)

            Button(action: model.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward)
            .keyboardShortcut("]", modifiers: .command)

            Button(action: model.reloadOrStop) {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)

            TextField("https://www.nasa.gov", text: $model.addressText)
                .textFieldStyle(.roundedBorder)
                .focused($addressFieldFocused)
                .onSubmit {
                    model.loadAddress()
                }

            Toggle(isOn: Binding(
                get: { model.isFloating },
                set: { model.setFloating($0) }
            )) {
                Text("🛸")
                    .font(.title2)
            }
            .toggleStyle(.switch)
            .help("Always on top")

            Button("") {
                addressFieldFocused = true
            }
            .keyboardShortcut("l", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button("") {
                if model.isLoading {
                    model.reloadOrStop()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
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
        window.titleVisibility = .visible
    }
}

struct BrowserWebView: NSViewRepresentable {
    let settings: SettingsStore
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
            updateLoading: { isLoading = $0 }
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

        init(
            settings: SettingsStore,
            updateAddress: @escaping (String) -> Void,
            updateStatus: @escaping (String) -> Void,
            updateHistory: @escaping (Bool, Bool) -> Void,
            updateLoading: @escaping (Bool) -> Void
        ) {
            self.settings = settings
            self.updateAddress = updateAddress
            self.updateStatus = updateStatus
            self.updateHistory = updateHistory
            self.updateLoading = updateLoading
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
                promptForPermission(host: host, type: type) { granted, remember in
                    if remember {
                        self.remember(host: host, type: type, value: granted ? .allow : .deny)
                    }

                    guard granted else {
                        DispatchQueue.main.async {
                            self.updateStatus("Media access denied.")
                            decisionHandler(.deny)
                        }
                        return
                    }

                    self.requestAccess(for: type) { systemGranted in
                        DispatchQueue.main.async {
                            self.updateStatus(systemGranted ? "Media access allowed." : "Media access denied.")
                            decisionHandler(systemGranted ? .grant : .deny)
                        }
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

        private func remember(host: String, type: WKMediaCaptureType, value: PermissionPolicy) {
            switch type {
            case .camera:
                settings.setPolicy(for: host, kind: .camera, value: value)
            case .microphone:
                settings.setPolicy(for: host, kind: .microphone, value: value)
            case .cameraAndMicrophone:
                settings.setPolicies(for: host, camera: value, microphone: value)
            @unknown default:
                break
            }
        }

        private func promptForPermission(host: String, type: WKMediaCaptureType, completion: @escaping (Bool, Bool) -> Void) {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = host
                alert.informativeText = "Allow \(self.captureName(for: type))?"
                alert.addButton(withTitle: "Allow")
                alert.addButton(withTitle: "Deny")

                let rememberToggle = NSButton(checkboxWithTitle: "Remember", target: nil, action: nil)
                alert.accessoryView = rememberToggle

                let response = alert.runModal()
                completion(response == .alertFirstButtonReturn, rememberToggle.state == .on)
            }
        }

        private func captureName(for type: WKMediaCaptureType) -> String {
            switch type {
            case .camera:
                return "camera access"
            case .microphone:
                return "microphone access"
            case .cameraAndMicrophone:
                return "camera and microphone access"
            @unknown default:
                return "media access"
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
                        .background(selectedTab == tab ? Color(NSColor.controlAccentColor).opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
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
                Toggle(isOn: $settings.launchFloating) {
                    EmptyView()
                }
                .labelsHidden()
                .help("Launch with Always on top enabled")
            }

            Spacer()
        }
    }

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(icon: AppSVG.shield, title: "Defaults") {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            SVGIconView(svg: AppSVG.camera, size: 18)
                                .frame(width: 18, height: 18)
                            PolicyPicker(selection: $settings.defaultCameraPolicy)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            SVGIconView(svg: AppSVG.microphone, size: 18)
                                .frame(width: 18, height: 18)
                            PolicyPicker(selection: $settings.defaultMicrophonePolicy)
                        }
                    }
                }
            }

            SettingsSection(icon: AppSVG.globe, title: "Sites") {
                if settings.siteRules.isEmpty {
                    Text("No sites yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        HStack {
                            Spacer()
                            SVGIconView(svg: AppSVG.camera, size: 16)
                                .frame(width: 32, height: 16)
                            SVGIconView(svg: AppSVG.microphone, size: 16)
                                .frame(width: 32, height: 16)
                        }

                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(settings.siteRules) { rule in
                                    HStack(spacing: 12) {
                                        Text(rule.host)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        PolicyPicker(
                                            selection: Binding(
                                                get: { settings.policy(for: rule.host, kind: .camera) },
                                                set: { settings.setPolicy(for: rule.host, kind: .camera, value: $0) }
                                            )
                                        )
                                        .frame(width: 120)

                                        PolicyPicker(
                                            selection: Binding(
                                                get: { settings.policy(for: rule.host, kind: .microphone) },
                                                set: { settings.setPolicy(for: rule.host, kind: .microphone, value: $0) }
                                            )
                                        )
                                        .frame(width: 120)
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
