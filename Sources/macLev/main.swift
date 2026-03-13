import SwiftUI
import WebKit

@main
struct MacLevApp: App {
    @StateObject private var model = BrowserModel()

    var body: some Scene {
        WindowGroup("macLev") {
            BrowserWindow()
                .environmentObject(model)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1024, height: 640)
    }
}

final class BrowserModel: ObservableObject {
    @Published var addressText = "https://www.example.com"
    @Published var isFloating = true
    @Published var restrictToAllowlist = false
    @Published var allowlistText = ""
    @Published var status = "Ready"
    @Published var pendingURL: URL?

    func submitAddress() {
        let raw = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            status = "Address is empty"
            return
        }

        var candidate = raw
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }

        guard let url = URL(string: candidate), let host = url.host, !host.isEmpty else {
            status = "Invalid address"
            return
        }

        addressText = url.absoluteString
        status = "Loading"
        pendingURL = url
    }

    func normalizedAllowlist() -> [String] {
        allowlistText
            .split { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func canNavigate(to host: String?) -> Bool {
        guard restrictToAllowlist else { return true }
        let host = host?.lowercased() ?? ""
        let allowlist = normalizedAllowlist()

        if allowlist.isEmpty { return true }
        return allowlist.contains(where: { host == $0 || host.hasSuffix("." + $0) })
    }
}

struct BrowserWindow: View {
    @EnvironmentObject private var model: BrowserModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("https://example.com", text: $model.addressText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(model.submitAddress)
                Button("Go", action: model.submitAddress)
                Toggle("Always on top", isOn: $model.isFloating)
                    .toggleStyle(.switch)
            }

            HStack(spacing: 8) {
                Toggle("Restrict navigation to allowlist", isOn: $model.restrictToAllowlist)
                    .toggleStyle(.switch)
                TextField("allowed hosts: example.com, api.mysite.local", text: $model.allowlistText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!model.restrictToAllowlist)
            }

            Text(model.status)
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            RestrictingWebView(
                status: $model.status,
                addressText: $model.addressText,
                pendingURL: $model.pendingURL,
                shouldAllowHost: model.canNavigate
            )
        }
        .padding(10)
        .overlay(
            WindowBehaviorConfigurator(isFloating: $model.isFloating)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false), alignment: .topLeading
        )
        .onAppear {
            model.submitAddress()
        }
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
        guard let window = window else { return }
        window.level = isFloating ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
    }
}

struct RestrictingWebView: NSViewRepresentable {
    @Binding var status: String
    @Binding var addressText: String
    @Binding var pendingURL: URL?
    let shouldAllowHost: (String?) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            updateStatus: { status = $0 },
            updateAddress: { addressText = $0 },
            shouldAllowHost: shouldAllowHost
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateRule(shouldAllowHost)

        if let url = pendingURL {
            DispatchQueue.main.async {
                self.pendingURL = nil
            }
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let updateStatus: (String) -> Void
        private let updateAddress: (String) -> Void
        private var shouldAllowHost: (String?) -> Bool

        init(updateStatus: @escaping (String) -> Void,
             updateAddress: @escaping (String) -> Void,
             shouldAllowHost: @escaping (String?) -> Bool) {
            self.updateStatus = updateStatus
            self.updateAddress = updateAddress
            self.shouldAllowHost = shouldAllowHost
        }

        func updateRule(_ check: @escaping (String?) -> Bool) {
            shouldAllowHost = check
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let host = navigationAction.request.url?.host
            guard shouldAllowHost(host) else {
                let hostText = host ?? "unknown"
                updateStatus("Blocked by allowlist: \(hostText)")
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            updateStatus("Loading")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let newAddress = webView.url?.absoluteString ?? ""
            updateAddress(newAddress)
            updateStatus("Loaded")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            updateStatus("Failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            updateStatus("Failed: \(error.localizedDescription)")
        }
    }
}
