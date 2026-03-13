import SwiftUI
import WebKit

@main
struct MaclevApp: App {
    @StateObject private var model = BrowserModel()

    var body: some Scene {
        WindowGroup("maclev") {
            BrowserView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1120, height: 720)
    }
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published var addressText = "https://www.example.com"
    @Published var pendingURL: URL?
    @Published var status = "Ready"
    @Published var isFloating = true

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
        pendingURL = url
        status = "Loading..."
    }
}

struct BrowserView: View {
    @EnvironmentObject private var model: BrowserModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
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

            HStack {
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            BrowserWebView(
                addressText: $model.addressText,
                pendingURL: $model.pendingURL,
                status: $model.status
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
            model.loadAddress()
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
        guard let window else { return }
        window.level = isFloating ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.titleVisibility = .visible
    }
}

struct BrowserWebView: NSViewRepresentable {
    @Binding var addressText: String
    @Binding var pendingURL: URL?
    @Binding var status: String

    func makeCoordinator() -> Coordinator {
        Coordinator(
            updateAddress: { addressText = $0 },
            updateStatus: { status = $0 }
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if let url = pendingURL {
            DispatchQueue.main.async {
                pendingURL = nil
            }
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let updateAddress: (String) -> Void
        private let updateStatus: (String) -> Void

        init(updateAddress: @escaping (String) -> Void, updateStatus: @escaping (String) -> Void) {
            self.updateAddress = updateAddress
            self.updateStatus = updateStatus
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            updateStatus("Loading...")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateAddress(webView.url?.absoluteString ?? "")
            updateStatus("Loaded.")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            updateStatus("Failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            updateStatus("Failed: \(error.localizedDescription)")
        }
    }
}
