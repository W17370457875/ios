import UIKit
import WebKit

final class WebViewController: UIViewController {

    // MARK: - 可调配置（改这里即可）

    /// 应用启动时打开的地址
    private let kHomeURL = "https://10804722.xyz/vpn/"

    /// 桌面版 User-Agent（macOS 上的 Safari）
    private let kDesktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    /// 移动版 User-Agent（底部工具栏可一键切换）
    private let kMobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

    /// 强制把 viewport 撑到桌面宽度，让页面按 PC 布局渲染
    private let kForceDesktopViewport = true
    private let kDesktopViewportWidth = 1280

    /// 是否显示底部工具条（返回 / 前进 / 首页 / 切换UA / 刷新）
    private let kShowToolbar = true

    /// 放行自签证书。企业内网 VPN 门户常使用自签证书；公开站点请改为 false
    private let kTrustSelfSignedCertificates = true

    // MARK: - 视图

    private var webView: WKWebView!
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let toolbar = UIToolbar()
    private let errorView = UIView()
    private let errorLabel = UILabel()
    private let errorButton = UIButton(type: .system)

    private let backItem = UIBarButtonItem()
    private let forwardItem = UIBarButtonItem()
    private let homeItem = UIBarButtonItem()
    private let uaItem = UIBarButtonItem()
    private let reloadItem = UIBarButtonItem()

    private var isDesktop = true
    private var observations: [NSKeyValueObservation] = []
    private var loadError = false

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildWebView(desktop: isDesktop)
        setupToolbar()
        setupErrorView()
        layoutViews()

        if let url = URL(string: kHomeURL) {
            webView.load(URLRequest(url: url))
        }
    }

    deinit {
        observations.removeAll()
    }

    // MARK: - 构建 WebView

    private func buildWebView(desktop: Bool) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKWebpagePreferences()
        prefs.preferredContentMode = desktop ? .desktop : .mobile
        config.defaultWebpagePreferences = prefs

        if kForceDesktopViewport {
            let js = """
            (function(){
              var width = \(kDesktopViewportWidth);
              function setVP(){
                var head = document.head || document.getElementsByTagName('head')[0];
                if(!head){ return; }
                var m = head.querySelector('meta[name=viewport]');
                if(!m){ m = document.createElement('meta'); m.name = 'viewport'; head.appendChild(m); }
                m.setAttribute('content','width=' + width + ', minimum-scale=0.1');
              }
              if(document.readyState !== 'loading'){ setVP(); }
              document.addEventListener('DOMContentLoaded', setVP);
              window.addEventListener('load', setVP);
              setTimeout(setVP, 300);
            })();
            """
            let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = desktop ? kDesktopUA : kMobileUA
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsLinkPreview = true
        wv.scrollView.refreshControl = refreshControl
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        wv.uiDelegate = self

        observations.removeAll()
        observations.append(wv.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            self?.updateProgress(wv.estimatedProgress)
        })
        observations.append(wv.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
            self?.backItem.isEnabled = wv.canGoBack
        })
        observations.append(wv.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
            self?.forwardItem.isEnabled = wv.canGoForward
        })
        observations.append(wv.observe(\.title, options: [.new]) { [weak self] wv, _ in
            self?.errorLabel.text = wv.title
        })

        if webView?.superview != nil {
            webView.removeFromSuperview()
        }
        webView = wv
        view.insertSubview(webView, at: 0)
        layoutWebView()
    }

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(reload), for: .valueChanged)
        return rc
    }()

    // MARK: - 布局

    private func layoutWebView() {
        guard let wv = webView else { return }
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: kShowToolbar ? toolbar.topAnchor : view.bottomAnchor)
        ])
    }

    private func layoutViews() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])

        if kShowToolbar {
            view.addSubview(toolbar)
            NSLayoutConstraint.activate([
                toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
        }
    }

    private func setupToolbar() {
        backItem.image = UIImage(systemName: "chevron.left")
        backItem.style = .plain
        backItem.target = self
        backItem.action = #selector(goBack)
        backItem.isEnabled = false

        forwardItem.image = UIImage(systemName: "chevron.right")
        forwardItem.style = .plain
        forwardItem.target = self
        forwardItem.action = #selector(goForward)
        forwardItem.isEnabled = false

        homeItem.image = UIImage(systemName: "house")
        homeItem.style = .plain
        homeItem.target = self
        homeItem.action = #selector(goHome)

        uaItem.image = UIImage(systemName: "display")
        uaItem.style = .plain
        uaItem.target = self
        uaItem.action = #selector(toggleUA)

        reloadItem.image = UIImage(systemName: "arrow.clockwise")
        reloadItem.style = .plain
        reloadItem.target = self
        reloadItem.action = #selector(reload)

        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbar.items = [backItem, flex, forwardItem, flex, homeItem, flex, uaItem, flex, reloadItem]
    }

    private func setupErrorView() {
        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.backgroundColor = .systemBackground
        errorView.isHidden = true
        view.addSubview(errorView)

        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.font = .preferredFont(forTextStyle: .callout)
        errorLabel.textColor = .secondaryLabel
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(errorLabel)

        errorButton.setTitle("重试", for: .normal)
        errorButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
        errorButton.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(errorButton)

        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: view.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            errorLabel.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: errorView.centerYAnchor, constant: -20),
            errorLabel.leadingAnchor.constraint(equalTo: errorView.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: errorView.trailingAnchor, constant: -24),
            errorButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12),
            errorButton.centerXAnchor.constraint(equalTo: errorView.centerXAnchor)
        ])
    }

    // MARK: - 动作

    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func goHome() {
        if let url = URL(string: kHomeURL) { webView.load(URLRequest(url: url)) }
    }
    @objc private func reload() {
        errorView.isHidden = true
        if loadError {
            loadError = false
            if let url = URL(string: kHomeURL) { webView.load(URLRequest(url: url)) }
            return
        }
        webView.reload()
    }
    @objc private func toggleUA() {
        isDesktop.toggle()
        buildWebView(desktop: isDesktop)
        webView.reload()
    }

    private func updateProgress(_ value: Double) {
        progressView.progress = Float(value)
        progressView.isHidden = value >= 1.0
    }

    private func showError(_ message: String) {
        loadError = true
        errorLabel.text = message
        errorView.isHidden = false
        progressView.isHidden = true
        refreshControl.endRefreshing()
    }
}

// MARK: - WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let allowed = ["http", "https", "about", "blob", "data", "file"]
        if let scheme = url.scheme?.lowercased(), !allowed.contains(scheme) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if kTrustSelfSignedCertificates,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = false
        errorView.isHidden = true
        progressView.isHidden = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
        progressView.isHidden = true
        backItem.isEnabled = webView.canGoBack
        forwardItem.isEnabled = webView.canGoForward
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        handleFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func handleFailure(_ error: Error) {
        let ns = error as NSError
        if ns.domain == "NSURLErrorDomain", ns.code == NSURLErrorCancelled { return }
        refreshControl.endRefreshing()
        showError("页面加载失败：\(error.localizedDescription)\n请检查网络或 VPN 连接后重试。")
    }
}

// MARK: - WKUIDelegate

extension WebViewController: WKUIDelegate {

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let ac = UIAlertController(title: frame.request.url?.host, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(ac, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let ac = UIAlertController(title: frame.request.url?.host, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        ac.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        present(ac, animated: true)
    }
}
