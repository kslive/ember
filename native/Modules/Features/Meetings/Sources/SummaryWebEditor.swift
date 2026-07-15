import AppKit
import Core
import DesignSystem
import SwiftUI
import WebKit

/// Controller of the web editor: the Swift → JS command bridge. Ported from Sage
/// (the JS bundle is reused VERBATIM, so the `window.sage*` API names stay).
///
/// The epoch machinery is ported AS A UNIT — every piece fixes a real recorded
/// data-loss bug (echo setDoc resetting the cursor, a tail `doc` message of the
/// previous meeting overwriting the next one, a stale fetch answer adopted after
/// a switch). Do not simplify it "because it's one file".
@MainActor
public final class SummaryEditorController {
    fileprivate weak var webView: WKWebView?
    fileprivate var ready = false
    fileprivate var jsText = ""
    /// Document generation: grows on setDoc/beginSwitch; `doc` messages carrying
    /// an older generation are dropped (anti-overwrite).
    public private(set) var epoch = 0
    /// Epoch of the LAST real push into the webview (setDoc) — JS `currentEpoch`
    /// equals exactly this; used to validate fetchDoc answers.
    public private(set) var lastPushedEpoch = 0

    /// The webview finished its cold start and displays the document — drives
    /// the native-render placeholder that hides the ~1s WKWebView launch.
    public var isReady: Bool {
        ready
    }

    public init() {}

    private func run(_ js: String) {
        guard let webView, ready else { return }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private static func jsString(_ s: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [s]),
           let arr = String(data: data, encoding: .utf8) {
            return String(arr.dropFirst().dropLast())
        }
        return "\"\""
    }

    func setDoc(_ text: String) {
        epoch += 1
        lastPushedEpoch = epoch
        jsText = text
        run("window.sageSetDoc(\(Self.jsString(text)), \(epoch))")
    }

    /// Pulls the live JS buffer (bypassing the JS debounce) — rescues un-flushed
    /// typing. The answer is accepted ONLY if its epoch matches the last push.
    public func fetchDoc() async -> String? {
        guard let webView, ready else { return nil }
        return await withCheckedContinuation { cont in
            webView.evaluateJavaScript("window.sageGetDoc && window.sageGetDoc()") { [weak self] res, _ in
                cont.resume(returning: Self.acceptFetched(res, lastPushedEpoch: self?.lastPushedEpoch ?? -1))
            }
        }
    }

    /// Pure validation of a sageGetDoc answer (testable without WKWebView).
    static func acceptFetched(_ res: Any?, lastPushedEpoch: Int) -> String? {
        guard let dict = res as? [String: Any],
              let text = dict["text"] as? String,
              let epoch = dict["epoch"] as? Int,
              epoch == lastPushedEpoch else { return nil }
        return text
    }

    /// Swift adopted text the webview ALREADY displays — suppress the echo push.
    func noteWebTextAdopted(_ text: String) {
        jsText = text
    }

    /// Raise the generation immediately when switching meetings so tail messages
    /// of the previous document are dropped before the new one loads.
    func beginSwitch() {
        epoch += 1
    }

    func setTheme(_ json: String) {
        run("window.sageSetTheme(\(Self.jsString(json)))")
    }

    /// Immediately send the JS document (bypassing its debounce).
    public func flushDoc() {
        run("window.sageFlushDoc()")
    }

    public func focus() {
        run("window.sageFocus()")
    }
}

/// Pure decision for an incoming `doc` message (testable without WKWebView).
enum EditorDocAction: Equatable {
    case ignore
    case apply(text: String, flush: Bool)
}

/// Markdown editor (CodeMirror 6, Obsidian-style Live Preview) in a WKWebView —
/// the exact Sage editor bundle, offline, restyled with Ember tokens + Geist.
/// No media APIs exist in the bundle (verified) — the webview can never touch
/// the microphone.
public struct SummaryWebEditorView: NSViewRepresentable {
    @Binding var text: String
    let themeJSON: String
    let controller: SummaryEditorController
    let onOpenLink: (String) -> Void
    let onFlushDoc: () -> Void
    let onReady: () -> Void

    public init(text: Binding<String>, themeJSON: String,
                controller: SummaryEditorController,
                onOpenLink: @escaping (String) -> Void = { _ in },
                onFlushDoc: @escaping () -> Void = {},
                onReady: @escaping () -> Void = {}) {
        _text = text
        self.themeJSON = themeJSON
        self.controller = controller
        self.onOpenLink = onOpenLink
        self.onFlushDoc = onFlushDoc
        self.onReady = onReady
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private static func editorIndexURL() -> URL? {
        if let u = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Editor") { return u }
        return Bundle.module.url(forResource: "index", withExtension: "html")
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "sage")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        controller.webView = webView
        context.coordinator.controller = controller
        if let index = Self.editorIndexURL() {
            webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        }
        return webView
    }

    public func updateNSView(_: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard controller.ready else { return }
        if text != controller.jsText { controller.setDoc(text) }
        if context.coordinator.lastTheme != themeJSON {
            context.coordinator.lastTheme = themeJSON
            controller.setTheme(themeJSON)
        }
    }

    /// The 11 CSS vars of the editor bundle, resolved from Ember tokens for the
    /// given appearance + current accent (mirrors EmberColor's dark/light hexes).
    public static func themeJSON(isDark: Bool) -> String {
        func rgba(_ hex: String, _ alpha: Double = 1) -> String {
            var s = hex
            if s.hasPrefix("#") { s.removeFirst() }
            var v: UInt64 = 0
            Scanner(string: s).scanHexInt64(&v)
            return String(format: "rgba(%d,%d,%d,%.3f)",
                          Int((v >> 16) & 0xFF), Int((v >> 8) & 0xFF), Int(v & 0xFF), alpha)
        }
        let accent = AccentPreset.current
        let vars: [String: String] = isDark ? [
            "--bg": rgba("0E0E10"), "--bg1": rgba("161618"), "--bg2": rgba("1C1C1F"), "--bg3": rgba("232326"),
            "--bd": "rgba(255,255,255,0.07)", "--bd2": "rgba(255,255,255,0.13)",
            "--tx": rgba("F5F5F4"), "--tx2": rgba("A1A1A0"), "--tx3": rgba("6B6B6A"),
            "--ac": rgba(accent.base), "--acs": rgba(accent.base, 0.13)
        ] : [
            "--bg": rgba("FAF9F7"), "--bg1": rgba("F0EDE8"), "--bg2": rgba("FFFFFF"), "--bg3": rgba("F0EDE8"),
            "--bd": "rgba(0,0,0,0.07)", "--bd2": "rgba(0,0,0,0.14)",
            "--tx": rgba("1C1B1A"), "--tx2": rgba("605D58"), "--tx3": rgba("908D88"),
            "--ac": rgba(accent.base), "--acs": rgba(accent.base, 0.10)
        ]
        if let data = try? JSONSerialization.data(withJSONObject: vars),
           let s = String(data: data, encoding: .utf8) { return s }
        return "{}"
    }

    public final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: SummaryWebEditorView
        weak var controller: SummaryEditorController?
        var lastTheme: String?

        init(_ parent: SummaryWebEditorView) {
            self.parent = parent
        }

        /// Accept the edit ONLY when its generation matches the current one.
        static func docAction(incomingEpoch: Int?, currentEpoch: Int, text: String?, flush: Bool) -> EditorDocAction {
            guard let incomingEpoch, incomingEpoch == currentEpoch, let text else { return .ignore }
            return .apply(text: text, flush: flush)
        }

        public func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                controller?.ready = true
                controller?.setDoc(parent.text)
                controller?.setTheme(parent.themeJSON)
                lastTheme = parent.themeJSON
                parent.onReady()
            case "doc":
                switch Self.docAction(incomingEpoch: body["epoch"] as? Int, currentEpoch: controller?.epoch ?? -1,
                                      text: body["text"] as? String, flush: (body["flush"] as? Bool) == true) {
                case .ignore: break
                case let .apply(text, flush):
                    controller?.jsText = text
                    if parent.text != text { parent.text = text }
                    if flush { parent.onFlushDoc() }
                }
            case "openLink":
                if let href = body["href"] as? String { parent.onOpenLink(href) }
            default:
                break
            }
        }

        public func webView(_: WKWebView, didFinish _: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, let controller, !controller.ready else { return }
                controller.ready = true
                controller.setDoc(parent.text)
                controller.setTheme(parent.themeJSON)
            }
        }
    }
}
