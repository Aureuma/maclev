import SwiftUI
import WebKit

@main
struct MaclevApp: App {
    @StateObject private var model = BrowserModel()

    var body: some Scene {
        WindowGroup("maclev") {
            BrowserView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1180, height: 760)
    }
}

enum BrowserCommand {
    case load(URL)
    case goBack
    case goForward
    case reload
    case stop
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published var addressText = "https://www.example.com"
    @Published var status = "Ready."
    @Published var isFloating = true
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var command: BrowserCommand?
    @Published var commandToken = UUID()

    let homeURL = URL(string: "https://www.example.com")!

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
        issue(.load(url))
    }

    func goHome() {
        addressText = homeURL.absoluteString
        issue(.load(homeURL))
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

    private func issue(_ nextCommand: BrowserCommand) {
        command = nextCommand
        commandToken = UUID()
    }
}

struct BrowserView: View {
    @EnvironmentObject private var model: BrowserModel

    var body: some View {
        VStack(spacing: 10) {
            topBar
            BrowserWebView(
                addressText: $model.addressText,
                status: $model.status,
                canGoBack: $model.canGoBack,
                canGoForward: $model.canGoForward,
                isLoading: $model.isLoading,
                command: $model.command,
                commandToken: $model.commandToken
            )
            .overlay(
                WindowBehaviorConfigurator(isFloating: $model.isFloating)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false),
                alignment: .topLeading
            )
        }
        .padding(12)
        .onAppear {
            model.goHome()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: model.goBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack)

            Button(action: model.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward)

            Button(action: model.reloadOrStop) {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
            }

            Button(action: model.goHome) {
                Image(systemName: "house")
            }

            TextField("https://example.com", text: $model.addressText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    model.loadAddress()
                }

            Button("Go") {
                model.loadAddress()
            }
            .buttonStyle(.borderedProminent)

            Toggle("Always on top", isOn: $model.isFloating)
                .toggleStyle(.switch)
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
    @Binding var addressText: String
    @Binding var status: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var command: BrowserCommand?
    @Binding var commandToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(
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
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
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

    final class Coordinator: NSObject, WKNavigationDelegate {
        private weak var webView: WKWebView?
        private var lastCommandToken: UUID?
        private let updateAddress: (String) -> Void
        private let updateStatus: (String) -> Void
        private let updateHistory: (Bool, Bool) -> Void
        private let updateLoading: (Bool) -> Void

        init(
            updateAddress: @escaping (String) -> Void,
            updateStatus: @escaping (String) -> Void,
            updateHistory: @escaping (Bool, Bool) -> Void,
            updateLoading: @escaping (Bool) -> Void
        ) {
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
            updateLoading(true)
            updateStatus("Loading...")
            updateHistory(webView.canGoBack, webView.canGoForward)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let url = webView.url {
                updateAddress(url.absoluteString)
            }
            updateHistory(webView.canGoBack, webView.canGoForward)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateLoading(false)
            updateAddress(webView.url?.absoluteString ?? "")
            updateStatus("Loaded.")
            updateHistory(webView.canGoBack, webView.canGoForward)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            updateLoading(false)
            updateStatus("Failed: \(error.localizedDescription)")
            updateHistory(webView.canGoBack, webView.canGoForward)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            updateLoading(false)
            updateStatus("Failed: \(error.localizedDescription)")
            updateHistory(webView.canGoBack, webView.canGoForward)
        }
    }
}
