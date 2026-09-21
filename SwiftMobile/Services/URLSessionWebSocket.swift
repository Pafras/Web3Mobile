import Foundation
import OSLog
import WalletConnectRelay

/// `WebSocketConnecting` implemented on URLSessionWebSocketTask.
///
/// Reown's SDK ships only the protocol; the official example satisfies it with
/// Starscream. URLSessionWebSocketTask is part of Foundation and covers every
/// member of the protocol, so no third-party socket library is needed.
///
/// Callers re-enter: the SDK's connection handler reacts to `onDisconnect` by
/// calling `connect()` again. Every callback is therefore invoked *outside* the
/// lock, and no method ever blocks waiting on another.
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

    private let timerQueue = DispatchQueue(label: "com.pafrasvio.SwiftMobile.websocket.ping")
    private let log = Logger(subsystem: "com.pafrasvio.SwiftMobile", category: "socket")

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
        log.info("SOCK connect requested url=\(self.request.url?.absoluteString ?? "nil", privacy: .public)")

        lock.lock()
        guard task == nil else {
            lock.unlock()
            log.info("SOCK already connecting or connected")
            return
        }
        // A fresh session per connection: URLSession retains its delegate until
        // invalidated, and invalidating is what breaks that cycle.
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        lock.unlock()

        task.resume()
        receive(on: task)
    }

    func disconnect() {
        log.info("SOCK disconnect requested")
        guard let (task, session) = takeConnection() else { return }
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    func write(string: String, completion: (() -> Void)?) {
        lock.lock()
        let task = self.task
        lock.unlock()

        guard let task else { return }
        task.send(.string(string)) { [weak self] error in
            if let error {
                self?.fail(error)
            } else {
                completion?()
            }
        }
    }

    // MARK: - Receiving

    /// URLSessionWebSocketTask delivers one message per `receive` call, so the
    /// call has to be re-armed after every message.
    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
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
                self.receive(on: task)
            case .failure(let error):
                self.fail(error)
            }
        }
    }

    // MARK: - Teardown

    /// Clears the connection state and hands back what needs tearing down, or
    /// nil if another path got there first. Keeps teardown to one winner.
    private func takeConnection() -> (URLSessionWebSocketTask, URLSession)? {
        lock.lock()
        guard let task, let session else {
            lock.unlock()
            return nil
        }
        self.task = nil
        self.session = nil
        connected = false
        lock.unlock()

        stopPinging()
        return (task, session)
    }

    private func fail(_ error: Error) {
        log.error("SOCK failed: \(String(describing: error), privacy: .public)")
        guard let (task, session) = takeConnection() else { return }
        task.cancel(with: .abnormalClosure, reason: nil)
        session.invalidateAndCancel()
        // Called with no lock held: the SDK reconnects from inside this.
        onDisconnect?(error)
    }

    // MARK: - Keepalive

    /// The relay connection is long-lived and idle for long stretches, which is
    /// exactly what NATs and carrier networks drop. A periodic ping keeps it up.
    /// ponytail: 15s is a guess that works — tune it if disconnects show up.
    private func startPinging() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let task = self.task
            self.lock.unlock()
            task?.sendPing { error in
                if let error { self.fail(error) }
            }
        }
        timer.resume()

        lock.lock()
        pingTimer?.cancel()
        pingTimer = timer
        lock.unlock()
    }

    private func stopPinging() {
        lock.lock()
        let timer = pingTimer
        pingTimer = nil
        lock.unlock()
        timer?.cancel()
    }
}

// MARK: - URLSessionWebSocketDelegate

extension URLSessionWebSocket: URLSessionWebSocketDelegate {

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol proto: String?
    ) {
        log.info("SOCK opened, protocol=\(proto ?? "none", privacy: .public)")
        lock.lock()
        connected = true
        lock.unlock()

        startPinging()
        // Called with no lock held: the SDK publishes queued messages here.
        onConnect?()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        log.info("SOCK closed code=\(closeCode.rawValue)")
        guard let (_, session) = takeConnection() else { return }
        session.invalidateAndCancel()
        onDisconnect?(nil)
    }
}

struct URLSessionSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        URLSessionWebSocket(request: URLRequest(url: url))
    }
}
