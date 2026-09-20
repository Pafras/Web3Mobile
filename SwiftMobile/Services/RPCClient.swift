import Foundation

enum RPCError: Error, Equatable {
    case invalidEndpoint(String)
    case httpStatus(Int)
    /// The node answered, but with a JSON-RPC error object.
    case node(code: Int, message: String)
    /// 200 OK, valid JSON, but no `result` field — treat as failure, not zero.
    case missingResult(method: String)
    /// The endpoint is live but points at the wrong network.
    case wrongChain(expected: Decimal, actual: Decimal)
}

/// A single JSON-RPC envelope. Every Ethereum node answers in this shape:
/// either `result` or `error` is present, never both.
private struct RPCResponse: Decodable {
    struct Failure: Decodable {
        let code: Int
        let message: String
    }
    let result: String?
    let error: Failure?
}

/// Minimal Ethereum JSON-RPC client. No web3 library on purpose: every call
/// here is just an HTTP POST with a JSON body, and seeing that is the point.
struct RPCClient {
    let endpoint: URL
    private let session: URLSession

    init(urlString: String, session: URLSession = .shared) throws {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            throw RPCError.invalidEndpoint(urlString)
        }
        self.endpoint = url
        self.session = session
    }

    /// Sends one call and returns the raw `result`, which for these methods is
    /// a hex quantity string such as "0x2386f26fc10000".
    func call(_ method: String, params: [Any] = []) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1,
        ])

        let (data, response) = try await session.data(for: request)

        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            throw RPCError.httpStatus(status)
        }

        let decoded = try JSONDecoder().decode(RPCResponse.self, from: data)
        if let failure = decoded.error {
            throw RPCError.node(code: failure.code, message: failure.message)
        }
        guard let result = decoded.result else {
            throw RPCError.missingResult(method: method)
        }
        return result
    }

    // MARK: - Methods

    /// Sepolia's chain id: 11155111, or 0xaa36a7 over the wire.
    static let sepoliaChainId: Decimal = 11_155_111

    func chainId() async throws -> Decimal {
        try await EthUnits.wei(fromHex: call("eth_chainId"))
    }

    /// Refuses to continue unless the endpoint really is Sepolia. This app must
    /// never touch mainnet, and a single mistyped URL is all it would take.
    func requireSepolia() async throws {
        let actual = try await chainId()
        guard actual == Self.sepoliaChainId else {
            throw RPCError.wrongChain(expected: Self.sepoliaChainId, actual: actual)
        }
    }

    func balance(of address: String) async throws -> Decimal {
        let checked = try EthUnits.validateAddress(address)
        // "latest" = the most recent block. Could also be "safe", "finalized",
        // or a specific block number in hex.
        let hex = try await call("eth_getBalance", params: [checked, "latest"])
        return try EthUnits.wei(fromHex: hex)
    }

    /// Runs a contract function and returns its raw output, without creating a
    /// transaction: nothing is mined, no gas is paid, no wallet is involved.
    func ethCall(to contract: String, data: String) async throws -> String {
        let checked = try EthUnits.validateAddress(contract)
        return try await call("eth_call", params: [
            ["to": checked, "data": data],
            "latest",
        ])
    }

    /// Reads one ERC-20 balance. `decimals` comes from the contract too, since
    /// it varies per token (USDC 6, LINK 18).
    func tokenBalance(of token: Token, owner: String) async throws -> TokenBalance {
        let calldata = try ABI.encodeAddressCall(
            selector: ABI.balanceOfSelector,
            address: owner
        )
        async let rawHex = ethCall(to: token.address, data: calldata)
        async let decimalsHex = ethCall(to: token.address, data: ABI.decimalsSelector)
        return TokenBalance(
            token: token,
            raw: try ABI.decodeUInt(await rawHex),
            decimals: try ABI.decodeDecimals(await decimalsHex)
        )
    }

    func blockNumber() async throws -> Decimal {
        try await EthUnits.wei(fromHex: call("eth_blockNumber"))
    }

    func gasPrice() async throws -> Decimal {
        try await EthUnits.wei(fromHex: call("eth_gasPrice"))
    }
}
