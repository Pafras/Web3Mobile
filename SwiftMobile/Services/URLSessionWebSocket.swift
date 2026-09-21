import Foundation
import WalletConnectRelay

/// `WebSocketConnecting` implemented on URLSessionWebSocketTask.
///
/// Reown's SDK ships only the protocol; the official example satisfies it with
/// Starscream. URLSessionWebSocketTask is part of Foundation and covers every
/// member of the protocol, so no third-party socket library is needed.
final class URLSessionWebSocket: NSObject, WebSocketConnecting {

    var request: URLRequest

    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?

    private let lock = NSLock()
    private var connected = false
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var pingTimer: DispatchSourceTimer?

    private let queue = DispatchQueue(label: "com.pafrasvio.SwiftMobile.websocket")

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connected
    }

    init(request: URLRequest) {
        self.request = request
        super.init()
    }

    func connect() {
        queue.sync {
            guard task == nil else { return }
            // A fresh session per connection: URLSession retains its delegate
            // until invalidated, and invalidating is what breaks that cycle.
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let task = session.webSocketTask(with: request)
            self.session = session
            self.task = task
            task.resume()
            receiveNext()
        }
    }

    func disconnect() {
        queue.sync {
            stopPinging()
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            session?.invalidateAndCancel()
            session = nil
            setConnected(false)
        }
    }

    func write(string: String, completion: (() -> Void)?) {
        queue.async { [weak self] in
            guard let task = self?.task else { return }
            task.send(.string(string)) { error in
                if let error {
                    self?.fail(error)
                } else {
                    completion?()
                }
            }
        }
    }

    // MARK: - Receiving

    /// URLSessionWebSocketTask delivers one message per `receive` call, so the
    /// call has to be re-armed after every message.
    private func receiveNext() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.onText?(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.onText?(text)
                    }
                @unknown default:
                    break
                }
                self.receiveNext()
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        queue.async { [weak self] in
            guard let self, self.task != nil else { return }
            self.stopPinging()
            self.task = nil
            self.session?.invalidateAndCancel()
            self.session = nil
            self.setConnected(false)
            self.onDisconnect?(error)
        }
    }

    // MARK: - Keepalive

    /// The relay connection is long-lived and idle for long stretches, which is
    /// exactly what NATs and carrier networks drop. A periodic ping keeps it up.
    /// ponytail: 15s is a guess that works — tune it if disconnects show up.
    private func startPinging() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            self?.task?.sendPing { error in
                if let error { self?.fail(error) }
            }
        }
        timer.resume()
        pingTimer = timer
    }

    private func stopPinging() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    private func setConnected(_ value: Bool) {
        lock.lock()
        connected = value
        lock.unlock()
    }
}

// MARK: - URLSessionWebSocketDelegate

extension URLSessionWebSocket: URLSessionWebSocketDelegate {

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol proto: String?
    ) {
        queue.async { [weak self] in
            self?.setConnected(true)
            self?.startPinging()
            self?.onConnect?()
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        queue.async { [weak self] in
            guard let self, self.task != nil else { return }
            self.stopPinging()
            self.task = nil
            self.setConnected(false)
            self.onDisconnect?(nil)
        }
    }
}

struct URLSessionSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        URLSessionWebSocket(request: URLRequest(url: url))
    }
}
