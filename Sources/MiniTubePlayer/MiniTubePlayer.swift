import AppKit
import SwiftUI
import WebKit

enum ViewMode: String {
    case fullVideo = "Full Video"
    case youtubeLayout = "YouTube Layout"
}

enum PlayerWindowSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var menuLabel: String {
        let width = Int(value.width)
        let height = Int(value.height)
        return "\(rawValue) (\(width)x\(height))"
    }

    var value: NSSize {
        switch self {
        case .small:
            NSSize(width: 640, height: 360)
        case .medium:
            NSSize(width: 960, height: 540)
        case .large:
            NSSize(width: 1280, height: 720)
        }
    }

    static func nearest(to size: NSSize) -> PlayerWindowSize {
        Self.allCases.min { lhs, rhs in
            let lhsDelta = abs(lhs.value.width - size.width) + abs(lhs.value.height - size.height)
            let rhsDelta = abs(rhs.value.width - size.width) + abs(rhs.value.height - size.height)
            return lhsDelta < rhsDelta
        } ?? .medium
    }
}

@main
struct MiniTubePlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(WindowConfigurator())
                .frame(minWidth: 480, minHeight: 270)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 960, height: 540)
        .commands {
            CommandMenu("Player Size") {
                Button(PlayerWindowSize.small.menuLabel) {
                    WindowController.shared.apply(size: .small)
                }
                Button(PlayerWindowSize.medium.menuLabel) {
                    WindowController.shared.apply(size: .medium)
                }
                Button(PlayerWindowSize.large.menuLabel) {
                    WindowController.shared.apply(size: .large)
                }
            }
            CommandMenu("View Mode") {
                Button(ViewMode.fullVideo.rawValue) {
                    WebViewController.shared.fillVideoInWindow()
                }
                Button(ViewMode.youtubeLayout.rawValue) {
                    WebViewController.shared.restorePageLayout()
                }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject private var viewModeStore = ViewModeStore.shared
    @ObservedObject private var playerSizeStore = PlayerSizeStore.shared
    @State private var isInteractionLocked = false

    var body: some View {
        ZStack {
            YouTubeWebView(url: URL(string: "https://www.youtube.com")!)

            if isInteractionLocked {
                InteractionBlockerOverlay()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .onChange(of: isInteractionLocked) { locked in
            WebViewController.shared.setInteractionLocked(locked)
        }
        .animation(.easeInOut(duration: 0.15), value: isInteractionLocked)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 18) {
                    Menu {
                        Button(ViewMode.fullVideo.rawValue) {
                            WebViewController.shared.fillVideoInWindow()
                        }
                        Button(ViewMode.youtubeLayout.rawValue) {
                            WebViewController.shared.restorePageLayout()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.on.rectangle")
                                .foregroundStyle(.blue)
                            Text(viewModeStore.mode.rawValue)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.14))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.blue.opacity(0.45), lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)

                    Menu {
                        Button(PlayerWindowSize.small.menuLabel) {
                            WindowController.shared.apply(size: .small)
                        }
                        Button(PlayerWindowSize.medium.menuLabel) {
                            WindowController.shared.apply(size: .medium)
                        }
                        Button(PlayerWindowSize.large.menuLabel) {
                            WindowController.shared.apply(size: .large)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "ruler")
                                .foregroundStyle(.green)
                            Text(playerSizeStore.size.rawValue)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.14))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.green.opacity(0.45), lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInteractionLocked.toggle()
                } label: {
                    Image(systemName: isInteractionLocked ? "lock.fill" : "lock.open.fill")
                }
                .help(isInteractionLocked ? "Unlock interactions" : "Lock interactions")
            }
        }
    }
}

struct YouTubeWebView: NSViewRepresentable {
    let url: URL

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                if ViewModeStore.shared.mode == .fullVideo {
                    WebViewController.shared.fillVideoInWindow()
                } else {
                    WebViewController.shared.syncViewModeFromPage()
                }
                webView.window?.makeFirstResponder(webView)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let userContentController = WKUserContentController()
        let disableFullscreenScript = WKUserScript(
            source: """
            (() => {
              const noop = () => {};
              const reject = () => Promise.reject(new Error('Fullscreen disabled by MiniTubePlayer'));
              const patch = (proto, key, value) => {
                if (!proto || !(key in proto)) return;
                try {
                  Object.defineProperty(proto, key, {
                    configurable: true,
                    writable: true,
                    value
                  });
                } catch (_) {}
              };

              patch(Element.prototype, 'requestFullscreen', reject);
              patch(Element.prototype, 'webkitRequestFullscreen', noop);
              patch(Element.prototype, 'webkitRequestFullScreen', noop);
              patch(HTMLVideoElement.prototype, 'webkitEnterFullscreen', noop);
              patch(HTMLVideoElement.prototype, 'webkitEnterFullScreen', noop);

              document.addEventListener('fullscreenchange', () => {
                if (document.fullscreenElement) {
                  document.exitFullscreen().catch(() => {});
                }
              }, true);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(disableFullscreenScript)
        configuration.userContentController = userContentController
        configuration.preferences.setValue(false, forKey: "fullScreenEnabled")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")

        WebViewController.shared.attach(webView: webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        WebViewController.shared.attach(webView: nsView)
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            WindowController.shared.attach(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            WindowController.shared.attach(window: window)
        }
    }
}

struct InteractionBlockerOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = InteractionBlockerNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let blocker = nsView as? InteractionBlockerNSView else { return }
        DispatchQueue.main.async {
            blocker.window?.makeFirstResponder(blocker)
        }
    }
}

final class InteractionBlockerNSView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func keyDown(with event: NSEvent) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        if let iconURL = Bundle.module.url(forResource: "appicon", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        } else if let fallbackURL = Bundle.module.url(forResource: "icon", withExtension: "png"),
                  let fallbackImage = NSImage(contentsOf: fallbackURL) {
            NSApp.applicationIconImage = fallbackImage
        }

        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class ViewModeStore: ObservableObject {
    static let shared = ViewModeStore()
    @Published var mode: ViewMode = .youtubeLayout

    private init() {}
}

@MainActor
final class PlayerSizeStore: ObservableObject {
    static let shared = PlayerSizeStore()
    @Published var size: PlayerWindowSize = .medium

    private init() {}
}

@MainActor
final class WebViewController {
    static let shared = WebViewController()

    private var webView: WKWebView?
    private var pendingFullVideoApply = false

    private init() {}

    func attach(webView: WKWebView) {
        self.webView = webView
        setScrollingEnabled(ViewModeStore.shared.mode != .fullVideo)
        if pendingFullVideoApply || ViewModeStore.shared.mode == .fullVideo {
            applyFullVideoIfPossible()
        }
        syncViewModeFromPage()
    }

    func setInteractionLocked(_ locked: Bool) {
        guard let webView = resolveWebView() else { return }
        if locked {
            webView.evaluateJavaScript("document.activeElement && document.activeElement.blur();", completionHandler: nil)
            webView.window?.makeFirstResponder(nil)
        } else {
            webView.window?.makeFirstResponder(webView)
        }
    }

    func syncViewModeFromPage() {
        guard let webView = resolveWebView() else { return }

        let script = """
        (() => {
          return document.documentElement?.getAttribute('data-mini-tv-mode') === 'full-video';
        })();
        """

        webView.evaluateJavaScript(script) { result, _ in
            let isFull = (result as? Bool) ?? false
            DispatchQueue.main.async {
                ViewModeStore.shared.mode = isFull ? .fullVideo : .youtubeLayout
            }
        }
    }

    func fillVideoInWindow() {
        ViewModeStore.shared.mode = .fullVideo
        pendingFullVideoApply = true
        setScrollingEnabled(false)
        print("Full Video requested")
        applyFullVideoIfPossible()
    }

    private func applyFullVideoIfPossible() {
        guard pendingFullVideoApply else { return }
        guard let webView = resolveWebView() else {
            print("Full Video waiting for webView...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.applyFullVideoIfPossible()
            }
            return
        }

        pendingFullVideoApply = false
        print("Full Video applying...")

        let script = """
        (() => {
          try {
            const clearLegacy = () => {
              const state = window.__miniTvFullVideoState;
              if (state) {
                if (state.resizeHandler) window.removeEventListener('resize', state.resizeHandler, true);
                if (state.observer) state.observer.disconnect();
                if (state.timer) window.clearInterval(state.timer);
                if (state.wheelBlocker) window.removeEventListener('wheel', state.wheelBlocker, true);
                if (state.wheelBlocker) window.removeEventListener('touchmove', state.wheelBlocker, true);
                delete window.__miniTvFullVideoState;
              }

              const style = document.getElementById('mini-tv-full-video-style');
              if (style) style.remove();

              const props = [
                'display', 'position', 'left', 'right', 'top', 'bottom', 'inset',
                'width', 'height', 'max-width', 'max-height', 'min-width', 'min-height',
                'margin', 'padding', 'overflow', 'background', 'transform', 'transform-origin',
                'will-change', 'visibility', 'opacity', 'pointer-events', 'z-index', 'object-fit'
              ];

              document.querySelectorAll('[data-mini-tv-forced-style="1"]').forEach((el) => {
                props.forEach((prop) => el.style.removeProperty(prop));
                el.removeAttribute('data-mini-tv-forced-style');
              });
            };

            clearLegacy();

            const target = document.querySelector('video.html5-main-video')
              || document.querySelector('#movie_player video')
              || document.querySelector('.html5-video-player video')
              || document.querySelector('#movie_player')
              || document.querySelector('.html5-video-player')
              || document.querySelector('#player')
              || document.querySelector('ytd-player')
              || document.querySelector('video');

            if (!target) {
              return { ok: false, reason: 'no target' };
            }

            document.documentElement?.setAttribute('data-mini-tv-mode', 'full-video');
            document.body?.setAttribute('data-mini-tv-mode', 'full-video');

            const theaterButton = document.querySelector('.ytp-size-button');
            if (theaterButton && theaterButton.getAttribute('aria-pressed') !== 'true') {
              theaterButton.click();
            }

            const moviePlayer = document.getElementById('movie_player');
            const isWatchPage = location.pathname.startsWith('/watch') || !!document.querySelector('ytd-watch-flexy');
            if (moviePlayer && isWatchPage) {
              const style = document.createElement('style');
              style.id = 'mini-tv-full-video-style';
              style.textContent = `
                html[data-mini-tv-mode='full-video'],
                body[data-mini-tv-mode='full-video'] {
                  overflow: hidden !important;
                  background: #000 !important;
                  width: 100% !important;
                  height: 100% !important;
                }

                html[data-mini-tv-mode='full-video'] ytd-masthead,
                html[data-mini-tv-mode='full-video'] #masthead-container,
                html[data-mini-tv-mode='full-video'] tp-yt-app-header-layout,
                html[data-mini-tv-mode='full-video'] ytd-mini-guide-renderer,
                html[data-mini-tv-mode='full-video'] #guide {
                  display: none !important;
                }

                html[data-mini-tv-mode='full-video'] #secondary,
                html[data-mini-tv-mode='full-video'] #below,
                html[data-mini-tv-mode='full-video'] #comments,
                html[data-mini-tv-mode='full-video'] #related,
                html[data-mini-tv-mode='full-video'] ytd-watch-next-secondary-results-renderer {
                  display: none !important;
                }

                html[data-mini-tv-mode='full-video'] #page-manager,
                html[data-mini-tv-mode='full-video'] #content,
                html[data-mini-tv-mode='full-video'] #columns,
                html[data-mini-tv-mode='full-video'] #primary,
                html[data-mini-tv-mode='full-video'] #primary-inner,
                html[data-mini-tv-mode='full-video'] ytd-watch-flexy {
                  margin: 0 !important;
                  padding: 0 !important;
                  top: 0 !important;
                  max-width: none !important;
                  width: 100vw !important;
                  min-height: 100vh !important;
                }

                html[data-mini-tv-mode='full-video'] ytd-player,
                html[data-mini-tv-mode='full-video'] #player-container-outer,
                html[data-mini-tv-mode='full-video'] #player-container-inner,
                html[data-mini-tv-mode='full-video'] #player {
                  position: fixed !important;
                  inset: 0 !important;
                  width: 100vw !important;
                  height: 100vh !important;
                  margin: 0 !important;
                  padding: 0 !important;
                  z-index: 2147483646 !important;
                  background: #000 !important;
                }

                html[data-mini-tv-mode='full-video'] #movie_player {
                  display: block !important;
                  position: fixed !important;
                  inset: 0 !important;
                  width: 100vw !important;
                  height: 100vh !important;
                  max-width: none !important;
                  max-height: none !important;
                  margin: 0 !important;
                  padding: 0 !important;
                  transform: none !important;
                  z-index: 2147483647 !important;
                }

                html[data-mini-tv-mode='full-video'] .html5-video-player,
                html[data-mini-tv-mode='full-video'] .html5-video-container,
                html[data-mini-tv-mode='full-video'] video.html5-main-video {
                  display: block !important;
                  position: absolute !important;
                  inset: 0 !important;
                  width: 100% !important;
                  height: 100% !important;
                  max-width: none !important;
                  max-height: none !important;
                  margin: 0 !important;
                  padding: 0 !important;
                  transform: none !important;
                }

                html[data-mini-tv-mode='full-video'] video.html5-main-video {
                  object-fit: cover !important;
                }
              `;
              document.head?.appendChild(style);

              const wheelBlocker = (event) => {
                event.preventDefault();
              };
              window.addEventListener('wheel', wheelBlocker, { passive: false, capture: true });
              window.addEventListener('touchmove', wheelBlocker, { passive: false, capture: true });
              window.__miniTvFullVideoState = { wheelBlocker };

              if (typeof moviePlayer.setSize === 'function') {
                try {
                  moviePlayer.setSize(window.innerWidth, window.innerHeight);
                } catch (_) {}
              }

              window.scrollTo(0, 0);
              return {
                ok: true,
                reason: 'css-player-fixed',
                left: 0,
                top: 0,
                width: Number(window.innerWidth),
                height: Number(window.innerHeight),
                scrollX: 0,
                scrollY: 0,
                useNativeZoom: false
              };
            }

            const rect = target.getBoundingClientRect();
            const left = Number(rect.left);
            const top = Number(rect.top);
            const width = Number(rect.width);
            const height = Number(rect.height);

            if (!Number.isFinite(width) || !Number.isFinite(height) || width < 8 || height < 8) {
              return {
                ok: false,
                reason: 'invalid rect',
                left,
                top,
                width,
                height,
                scrollX: Number(window.scrollX),
                scrollY: Number(window.scrollY)
              };
            }

            if (moviePlayer && typeof moviePlayer.setSize === 'function') {
              try {
                moviePlayer.setSize(window.innerWidth, window.innerHeight);
              } catch (_) {}
            }

            return {
              ok: true,
              reason: 'ok',
              left,
              top,
              width,
              height,
              scrollX: Number(window.scrollX),
              scrollY: Number(window.scrollY),
              useNativeZoom: true
            };
          } catch (error) {
            return {
              ok: false,
              reason: String(error),
              stack: error && error.stack ? String(error.stack) : ''
            };
          }
        })();
        """

        func runAttempt(_ attempt: Int = 0) {
            webView.evaluateJavaScript(script) { [weak self, weak webView] result, error in
                guard let webView else { return }

                if let error {
                    print("Full Video apply failed: \(error.localizedDescription)")
                    if let nsError = error as NSError? {
                        print("Full Video apply error info: \(nsError.userInfo)")
                    }
                    if attempt == 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                            guard self != nil else { return }
                            runAttempt(1)
                        }
                    }
                    return
                }

                guard let payload = result as? [String: Any] else {
                    print("Full Video raw result: \(String(describing: result))")
                    return
                }

                let ok = (payload["ok"] as? Bool) ?? false
                let reason = (payload["reason"] as? String) ?? ""
                if !ok {
                    print("Full Video stats: reason=\(reason)")
                    if let stack = payload["stack"] as? String, !stack.isEmpty {
                        print("Full Video script stack: \(stack)")
                    }
                    if attempt == 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                            guard self != nil else { return }
                            runAttempt(1)
                        }
                    }
                    return
                }

                let left = (payload["left"] as? NSNumber)?.doubleValue ?? 0
                let top = (payload["top"] as? NSNumber)?.doubleValue ?? 0
                let width = (payload["width"] as? NSNumber)?.doubleValue ?? 0
                let height = (payload["height"] as? NSNumber)?.doubleValue ?? 0
                let scrollX = (payload["scrollX"] as? NSNumber)?.doubleValue ?? 0
                let scrollY = (payload["scrollY"] as? NSNumber)?.doubleValue ?? 0
                let useNativeZoom = (payload["useNativeZoom"] as? Bool) ?? true

                if !useNativeZoom {
                    webView.setMagnification(1.0, centeredAt: NSPoint(x: webView.bounds.midX, y: webView.bounds.midY))
                    print("Full Video stats: reason=\(reason), nativeZoom=off, target=\(width)x\(height)")
                    return
                }

                if width < 8 || height < 8 {
                    print("Full Video stats: reason=invalid-size, width=\(width), height=\(height)")
                    if attempt == 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                            guard self != nil else { return }
                            runAttempt(1)
                        }
                    }
                    return
                }

                let viewWidth = max(Double(webView.bounds.width), 1)
                let viewHeight = max(Double(webView.bounds.height), 1)
                let rawScale = max(viewWidth / width, viewHeight / height)
                let scale = max(1.0, min(rawScale * 1.03, 4.0))

                webView.allowsMagnification = true
                let center = NSPoint(x: webView.bounds.midX, y: webView.bounds.midY)
                webView.setMagnification(CGFloat(scale), centeredAt: center)

                let targetCenterX = scrollX + left + (width / 2)
                let targetTopY = scrollY + top
                let visibleWidthInPage = viewWidth / scale
                let scrollScript = """
                (() => {
                  const viewportWidth = Math.max(1, \(visibleWidthInPage));
                  const x = Math.max(0, \(targetCenterX) - (viewportWidth / 2));
                  const y = Math.max(0, \(targetTopY) - 2);
                  window.scrollTo(x, y);
                  window.requestAnimationFrame(() => {
                    const video = document.querySelector('video.html5-main-video')
                      || document.querySelector('#movie_player video')
                      || document.querySelector('.html5-video-player video')
                      || document.querySelector('video');
                    if (!video) return;
                    const rect = video.getBoundingClientRect();
                    const delta = Math.max(-240, Math.min(240, rect.top - 2));
                    if (Math.abs(delta) > 1) {
                      window.scrollBy(0, delta);
                    }
                  });
                  return { x, y };
                })();
                """
                webView.evaluateJavaScript(scrollScript, completionHandler: nil)

                print("Full Video stats: reason=\(reason), scale=\(scale), target=\(width)x\(height)")
            }
        }

        runAttempt()
    }

    func restorePageLayout() {
        guard let webView = resolveWebView() else { return }
        ViewModeStore.shared.mode = .youtubeLayout
        pendingFullVideoApply = false
        setScrollingEnabled(true)

        webView.setMagnification(1.0, centeredAt: NSPoint(x: webView.bounds.midX, y: webView.bounds.midY))

        let script = """
        (() => {
          try {
            const state = window.__miniTvFullVideoState;
            if (state) {
              if (state.resizeHandler) window.removeEventListener('resize', state.resizeHandler, true);
              if (state.observer) state.observer.disconnect();
              if (state.timer) window.clearInterval(state.timer);
              if (state.wheelBlocker) window.removeEventListener('wheel', state.wheelBlocker, true);
              if (state.wheelBlocker) window.removeEventListener('touchmove', state.wheelBlocker, true);
              delete window.__miniTvFullVideoState;
            }

            const style = document.getElementById('mini-tv-full-video-style');
            if (style) style.remove();

            const props = [
              'display', 'position', 'left', 'right', 'top', 'bottom', 'inset',
              'width', 'height', 'max-width', 'max-height', 'min-width', 'min-height',
              'margin', 'padding', 'overflow', 'background', 'transform', 'transform-origin',
              'will-change', 'visibility', 'opacity', 'pointer-events', 'z-index', 'object-fit'
            ];

            document.querySelectorAll('[data-mini-tv-forced-style="1"]').forEach((el) => {
              props.forEach((prop) => el.style.removeProperty(prop));
              el.removeAttribute('data-mini-tv-forced-style');
            });

            document.documentElement?.removeAttribute('data-mini-tv-mode');
            document.body?.removeAttribute('data-mini-tv-mode');
            document.documentElement?.classList.remove('mini-tv-full-video');
            document.body?.classList.remove('mini-tv-full-video');

            const watchFlexy = document.querySelector('ytd-watch-flexy');
            if (watchFlexy) watchFlexy.removeAttribute('theater');

            window.scrollTo(0, 0);
            return true;
          } catch (_) {
            return false;
          }
        })();
        """

        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func setScrollingEnabled(_ enabled: Bool) {
        guard let webView = resolveWebView(),
              let scrollView = resolveScrollView(in: webView) else { return }

        scrollView.hasHorizontalScroller = enabled
        scrollView.hasVerticalScroller = enabled
        scrollView.autohidesScrollers = !enabled
        scrollView.horizontalScrollElasticity = enabled ? .automatic : .none
        scrollView.verticalScrollElasticity = enabled ? .automatic : .none
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.isHidden = !enabled
        scrollView.horizontalScroller?.isHidden = !enabled
    }

    private func resolveScrollView(in webView: WKWebView) -> NSScrollView? {
        if let enclosing = webView.enclosingScrollView {
            return enclosing
        }
        return findScrollView(in: webView)
    }

    private func findScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for child in view.subviews {
            if let found = findScrollView(in: child) {
                return found
            }
        }
        return nil
    }

    private func resolveWebView() -> WKWebView? {
        if let webView {
            return webView
        }

        for window in NSApp.windows {
            if let found = findWebView(in: window.contentView) {
                webView = found
                return found
            }
        }

        return nil
    }

    private func findWebView(in view: NSView?) -> WKWebView? {
        guard let view else { return nil }

        if let webView = view as? WKWebView {
            return webView
        }

        for child in view.subviews {
            if let found = findWebView(in: child) {
                return found
            }
        }

        return nil
    }
}
@MainActor
final class WindowController {
    static let shared = WindowController()

    private weak var window: NSWindow?
    private var resizeObserver: NSObjectProtocol?
    private var configuredWindowNumbers: Set<Int> = []

    private init() {}

    func attach(window: NSWindow) {
        configureIfNeeded(window: window)

        if self.window !== window {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }

            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.syncCurrentWindowSizeState()
                }
            }
        }

        self.window = window
        snapToNearestPresetIfNeeded(animated: false)
        syncCurrentWindowSizeState()
    }

    func apply(size: PlayerWindowSize) {
        guard let window else { return }

        PlayerSizeStore.shared.size = size
        let nextSize = size.value

        var frame = window.frame
        frame.origin.y += frame.height - nextSize.height
        frame.size = nextSize
        window.setFrame(frame, display: true, animate: true)

        if ViewModeStore.shared.mode == .fullVideo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                WebViewController.shared.fillVideoInWindow()
            }
        }
    }

    private func syncCurrentWindowSizeState() {
        guard let window else { return }
        PlayerSizeStore.shared.size = PlayerWindowSize.nearest(to: window.frame.size)
    }

    private func snapToNearestPresetIfNeeded(animated: Bool) {
        guard let window else { return }

        let current = window.frame.size
        let nearest = PlayerWindowSize.nearest(to: current).value
        let tolerance: CGFloat = 0.5
        let alreadyPreset =
            abs(current.width - nearest.width) <= tolerance &&
            abs(current.height - nearest.height) <= tolerance

        guard !alreadyPreset else { return }

        var frame = window.frame
        frame.origin.y += frame.height - nearest.height
        frame.size = nearest
        window.setFrame(frame, display: true, animate: animated)
    }

    private func configureIfNeeded(window: NSWindow) {
        let windowNumber = window.windowNumber
        guard !configuredWindowNumbers.contains(windowNumber) else { return }
        configuredWindowNumbers.insert(windowNumber)

        window.level = .normal
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.styleMask.insert(.titled)
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.remove(.resizable)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.styleMask.remove(.fullSizeContentView)
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.makeKeyAndOrderFront(nil)
    }
}
