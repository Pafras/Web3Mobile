import Combine
import Foundation
import ReownAppKit
import WalletConnectNetworking

/// Owns the Reown AppKit lifecycle: configuration, and the connected account.
///
/// The app never holds a key. It opens a session with the user's wallet, and
/// every signature or transaction is approved there.
@MainActor
@Observable
final class WalletService {

    static let shared = WalletService()

    private(set) var address: String?
    private(set) var isConnected = false
    private(set) var socketConnected = false

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var configured = false

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
            authRequestParams: nil // nil = no Sign In With Ethereum
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

        AppKit.instance.socketConnectionStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.socketConnected = status == .connected }
            .store(in: &cancellables)
    }

    private func readCurrentSession() {
        address = AppKit.instance.getAddress()
        isConnected = address != nil
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
