import Combine
import Foundation
import OSLog
import ReownAppKit
import UIKit
import WalletConnectNetworking

/// Owns the Reown AppKit lifecycle: configuration, and the connected account.
///
/// The app never holds a key. It opens a session with the user's wallet, and
/// every signature or transaction is approved there.
@MainActor
@Observable
final class WalletService {

    static let shared = WalletService()

    private let log = Logger(subsystem: "com.pafrasvio.SwiftMobile", category: "wallet")

    enum SigningState: Equatable {
        case idle
        /// Request sent, waiting for the user to approve in their wallet.
        case awaitingApproval
        case signed(message: String, signature: String)
        case failed(String)
    }

    private(set) var address: String?
    private(set) var isConnected = false
    private(set) var socketConnected = false
    private(set) var signing: SigningState = .idle

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var pendingMessage: String?

    private init() {}

    /// Sepolia is not in Reown's chain presets — those are mainnet only — so it
    /// is registered here and made the only chain the session may use.
    static let sepolia = Chain(
        chainName: "Sepolia",
        chainNamespace: "eip155",
        chainReference: "11155111",
        requiredMethods: ["personal_sign", "eth_signTypedData", "eth_sendTransaction"],
        optionalMethods: ["wallet_switchEthereumChain", "wallet_addEthereumChain"],
        events: ["chainChanged", "accountsChanged"],
        token: .init(name: "Sepolia Ether", symbol: "SepoliaETH", decimal: 18),
        rpcUrl: "https://ethereum-sepolia-rpc.publicnode.com",
        blockExplorerUrl: "https://sepolia.etherscan.io",
        imageId: ""
    )

    func configure() {
        guard !configured else { return }
        configured = true

        Networking.configure(
            groupIdentifier: "group.com.pafrasvio.SwiftMobile",
            projectId: Secrets.reownProjectId,
            socketFactory: URLSessionSocketFactory()
        )

        let metadata = AppMetadata(
            name: "SwiftMobile",
            description: "A Sepolia dApp built to learn web3 on iOS",
            url: "https://github.com/Pafras/Web3Mobile",
            icons: [],
            // Must match the URL scheme registered in Info.plist, or the wallet
            // cannot bring this app back to the foreground after approval.
            redirect: try! AppMetadata.Redirect(native: "swiftmobile://", universal: nil)
        )

        AppKit.configure(
            projectId: Secrets.reownProjectId,
            metadata: metadata,
            crypto: KeccakCryptoProvider(),
            sessionParams: Self.sepoliaOnlySession,
            authRequestParams: nil, // nil = no Sign In With Ethereum
            // Coinbase Wallet routes requests through its own SDK rather than
            // the relay. This app only speaks WalletConnect.
            coinbaseEnabled: false,
            onError: { [weak self] error in
                self?.log.error("APPKIT error: \(String(describing: error), privacy: .public)")
            }
        )


        AppKit.instance.addChainPreset(Self.sepolia)
        AppKit.instance.selectChain(Self.sepolia)
        AppKit.instance.disableAnalytics()

        observe()
        readCurrentSession()
    }

    /// Only Sepolia is ever requested. A wallet cannot hand this app a mainnet
    /// account, because mainnet is not in the proposal.
    private static var sepoliaOnlySession: SessionParams {
        SessionParams(namespaces: [
            "eip155": ProposalNamespace(
                chains: [Blockchain("eip155:11155111")!],
                methods: ["personal_sign", "eth_signTypedData", "eth_sendTransaction"],
                events: ["chainChanged", "accountsChanged"]
            ),
        ])
    }

    private func observe() {
        AppKit.instance.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.readCurrentSession() }
            .store(in: &cancellables)

        AppKit.instance.sessionSettlePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.readCurrentSession() }
            .store(in: &cancellables)

        AppKit.instance.socketConnectionStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.socketConnected = status == .connected }
            .store(in: &cancellables)

        AppKit.instance.sessionResponsePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in self?.handle(response) }
            .store(in: &cancellables)
    }

    func sign(message: String) async {
        guard let address else {
            signing = .failed("Connect a wallet first.")
            return
        }
        // personal_sign takes the message as a hex string, not plain text.
        let hex = EthUnits.hexString(fromUTF8: message)

        signing = .awaitingApproval

        do {
            // The SDK awaits a relay acknowledgement with no deadline of its
            // own, so a lost ack hangs the call forever. Bound it here.
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await AppKit.instance.request(
                        .personal_sign(address: address, message: hex)
                    )
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(20))
                    throw SignError.relayTimeout
                }
                try await group.next()
                group.cancelAll()
            }
            pendingMessage = message
            openWallet()
        } catch is SignError {
            signing = .failed("The relay never acknowledged the request. Try reconnecting the wallet.")
        } catch {
            log.error("SIGN request failed: \(String(describing: error), privacy: .public)")
            signing = .failed(error.localizedDescription)
        }
    }

    private enum SignError: Error {
        case relayTimeout
    }

    /// Brings the connected wallet to the front.
    ///
    /// AppKit's own `launchCurrentWallet()` returns silently when the session
    /// peer published no `redirect`, which leaves the user staring at a spinner
    /// with no idea the prompt is waiting in another app. This tries the peer's
    /// redirect first and falls back to MetaMask's universal link.
    private func openWallet() {
        let session = AppKit.instance.getSessions().first
        let peer = session?.peer

        let candidates = [
            peer?.redirect?.native,
            peer?.redirect?.universal,
            "https://metamask.app.link/",
        ]

        for candidate in candidates.compactMap({ $0 }) {
            guard let url = URL(string: candidate) else {
                continue
            }
            let canOpen = UIApplication.shared.canOpenURL(url)
            if canOpen {
                UIApplication.shared.open(url) { opened in
                }
                return
            }
        }
        log.error("OPEN no candidate could be opened")
        signing = .failed("Could not open your wallet. Switch to it manually to approve.")
    }

    private func handle(_ response: W3MResponse) {
        switch response.result {
        case .response(let value):
            guard let signature = try? value.get(String.self) else {
                signing = .failed("Wallet returned an unexpected response.")
                return
            }
            signing = .signed(message: pendingMessage ?? "", signature: signature)
        case .error(let error):
            // Code 5000 is the WalletConnect code for "user rejected".
            signing = .failed(
                error.code == 5000
                    ? "You declined the signature in your wallet."
                    : "Wallet error \(error.code): \(error.message)"
            )
        }
        pendingMessage = nil
    }

    func resetSigning() {
        signing = .idle
    }

    private func readCurrentSession() {
        // AppKit's getAddress() reads its own `store.account`, which is not
        // always repopulated when a stored session is restored. The session
        // namespaces are the source of truth, so fall back to them.
        address = AppKit.instance.getAddress() ?? firstSessionAddress()
        isConnected = address != nil
    }

    /// Accounts arrive as CAIP-10 strings, "eip155:11155111:0x6551…".
    private func firstSessionAddress() -> String? {
        AppKit.instance.getSessions()
            .first?
            .namespaces["eip155"]?
            .accounts
            .first?
            .address
    }

    func disconnect() async {
        guard let session = AppKit.instance.getSessions().first else { return }
        try? await AppKit.instance.disconnect(topic: session.topic)
        readCurrentSession()
    }

    func handleDeeplink(_ url: URL) {
        AppKit.instance.handleDeeplink(url)
    }
}
