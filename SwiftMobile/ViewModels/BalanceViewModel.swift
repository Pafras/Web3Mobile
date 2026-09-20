import Foundation

@MainActor
@Observable
final class BalanceViewModel {

    /// One enum instead of separate isLoading / value / errorMessage properties:
    /// it makes "loading AND failed at the same time" unrepresentable.
    enum State {
        case idle
        case loading
        case loaded(Chain)
        case failed(String)
    }

    struct Chain {
        let balanceWei: Decimal
        let blockNumber: Decimal
        let gasPriceWei: Decimal
        let tokens: [TokenBalance]

        var balanceEth: Decimal { EthUnits.eth(fromWei: balanceWei) }
    }

    var address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    private(set) var state: State = .idle

    var isAddressValid: Bool { EthUnits.isValidAddress(address) }

    private let client: RPCClient?
    private let clientError: String?
    /// Checked once per launch, not on every fetch.
    private var chainVerified = false

    init() {
        do {
            client = try RPCClient(urlString: Secrets.sepoliaRPCURL)
            clientError = nil
        } catch {
            client = nil
            clientError = "Bad RPC URL in Secrets.swift. Paste your Sepolia endpoint there."
        }
    }

    func load() async {
        guard let client else {
            state = .failed(clientError ?? "No RPC client")
            return
        }
        state = .loading
        do {
            if !chainVerified {
                try await client.requireSepolia()
                chainVerified = true
            }
            // Three independent calls, so run them concurrently instead of
            // waiting for each in turn.
            async let balance = client.balance(of: address)
            async let block = client.blockNumber()
            async let gas = client.gasPrice()
            async let tokens = Self.tokenBalances(client: client, owner: address)
            state = .loaded(Chain(
                balanceWei: try await balance,
                blockNumber: try await block,
                gasPriceWei: try await gas,
                tokens: try await tokens
            ))
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    /// One task per token rather than a loop, so three tokens cost one round
    /// trip instead of three.
    /// ponytail: one failing token fails the whole fetch — split it per token
    /// if the list ever grows past a handful.
    private static func tokenBalances(
        client: RPCClient,
        owner: String
    ) async throws -> [TokenBalance] {
        try await withThrowingTaskGroup(of: TokenBalance.self) { group in
            for token in Token.sepolia {
                group.addTask { try await client.tokenBalance(of: token, owner: owner) }
            }
            var balances: [TokenBalance] = []
            for try await balance in group {
                balances.append(balance)
            }
            return balances.sorted { $0.token.symbol < $1.token.symbol }
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case EthUnitsError.invalidAddress:
            "Not a valid address (needs 0x + 40 hex characters)."
        case RPCError.invalidEndpoint:
            "Bad RPC URL in Secrets.swift."
        case RPCError.httpStatus(let code):
            "Node replied HTTP \(code). Wrong URL or rate limited."
        case RPCError.node(let code, let message):
            "Node error \(code): \(message)"
        case RPCError.missingResult(let method):
            "Node returned no result for \(method)."
        case RPCError.wrongChain(_, let actual):
            actual == 1
                ? "That RPC URL points at Ethereum MAINNET (real funds). Use a Sepolia endpoint."
                : "Wrong network: chain id \(actual). Expected Sepolia (11155111)."
        case ABIError.unexpectedReturnLength:
            "That address is not an ERC-20 contract."
        case ABIError.decimalsOutOfRange(let value):
            "Contract reported an implausible decimals value (\(value))."
        case let urlError as URLError:
            "Network problem: \(urlError.localizedDescription)"
        default:
            error.localizedDescription
        }
    }
}
