import Foundation
import Testing

@testable import SwiftMobile

@Suite("Hex to wei")
struct HexToWeiTests {

    @Test("Parses a JSON-RPC quantity", arguments: [
        ("0x0", Decimal(0)),
        ("0x1", Decimal(1)),
        ("0xff", Decimal(255)),
        ("0x2386f26fc10000", Decimal(string: "10000000000000000")!),
    ])
    func parses(hex: String, expected: Decimal) throws {
        #expect(try EthUnits.wei(fromHex: hex) == expected)
    }

    @Test("Accepts upper case and a missing 0x prefix")
    func tolerantParsing() throws {
        #expect(try EthUnits.wei(fromHex: "0xAA36A7") == 11_155_111)
        #expect(try EthUnits.wei(fromHex: "1a") == 26)
    }

    @Test("Handles balances past UInt64.max")
    func beyondUInt64() throws {
        // 100 ETH in wei is 1e20; UInt64 tops out around 1.8e19, so the
        // straightforward UInt64 implementation silently fails here.
        let wei = try EthUnits.wei(fromHex: "0x56bc75e2d63100000")
        #expect(wei == Decimal(string: "100000000000000000000")!)
        #expect(wei > Decimal(UInt64.max))
    }

    @Test("Rejects an empty quantity")
    func emptyThrows() {
        #expect(throws: EthUnitsError.emptyHex) {
            try EthUnits.wei(fromHex: "0x")
        }
    }

    @Test("Rejects a non-hex character instead of returning zero")
    func badDigitThrows() {
        #expect(throws: EthUnitsError.invalidHexDigit("z")) {
            try EthUnits.wei(fromHex: "0x1z")
        }
    }
}

@Suite("Wei to ETH")
struct WeiToEthTests {

    @Test("Divides by 10^18 exactly")
    func conversion() {
        #expect(EthUnits.eth(fromWei: EthUnits.weiPerEth) == 1)
        #expect(EthUnits.eth(fromWei: Decimal(string: "10000000000000000")!) == Decimal(string: "0.01")!)
        #expect(EthUnits.eth(fromWei: 1) == Decimal(string: "0.000000000000000001")!)
    }

    @Test("Keeps every digit of a real balance")
    func noPrecisionLoss() throws {
        let eth = try EthUnits.eth(fromHex: "0x34e46e3dafbbda31c")
        #expect(eth == Decimal(string: "60.980678334122664732")!)
    }
}

@Suite("Address validation")
struct AddressTests {

    static let valid = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

    @Test("Accepts 0x plus 40 hex characters")
    func acceptsValid() {
        #expect(EthUnits.isValidAddress(Self.valid))
    }

    @Test("Rejects malformed input", arguments: [
        "",
        "0x",
        "d8dA6BF26964aF9D7eEd9e03E53415D37aA96045",      // no 0x
        "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA9604",     // 39 hex digits
        "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA960455",   // 41 hex digits
        "0xZZda6BF26964aF9D7eEd9e03E53415D37aA96045",    // non-hex
    ])
    func rejects(address: String) {
        #expect(!EthUnits.isValidAddress(address))
    }

    @Test("validateAddress returns the address it was given")
    func validateReturns() throws {
        #expect(try EthUnits.validateAddress(Self.valid) == Self.valid)
    }

    @Test("validateAddress throws before any network call happens")
    func validateThrows() {
        #expect(throws: EthUnitsError.invalidAddress("0xnope")) {
            try EthUnits.validateAddress("0xnope")
        }
    }
}

@Suite("Chain guard")
struct ChainTests {

    @Test("Sepolia's chain id is 0xaa36a7")
    func sepoliaId() throws {
        #expect(try EthUnits.wei(fromHex: "0xaa36a7") == RPCClient.sepoliaChainId)
        #expect(RPCClient.sepoliaChainId == 11_155_111)
    }

    @Test("Rejects an endpoint that is not http(s)")
    func rejectsBadEndpoint() {
        #expect(throws: RPCError.invalidEndpoint("not a url")) {
            _ = try RPCClient(urlString: "not a url")
        }
        #expect(throws: RPCError.invalidEndpoint("ftp://example.com")) {
            _ = try RPCClient(urlString: "ftp://example.com")
        }
    }
}

@Suite("ABI encoding")
struct ABIEncodingTests {

    static let owner = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

    @Test("balanceOf calldata is 4 selector bytes plus one 32-byte slot")
    func calldataLayout() throws {
        let data = try ABI.encodeAddressCall(selector: ABI.balanceOfSelector, address: Self.owner)
        #expect(data.hasPrefix("0x70a08231"))
        #expect((data.count - 2) / 2 == 36)
    }

    @Test("The address is right-aligned in its slot")
    func padding() throws {
        let data = try ABI.encodeAddressCall(selector: ABI.balanceOfSelector, address: Self.owner)
        let argument = data.dropFirst(10)                      // past "0x" + selector
        #expect(argument.prefix(24) == String(repeating: "0", count: 24))
        #expect(argument.suffix(40) == Self.owner.dropFirst(2))
    }

    @Test("A malformed address never reaches the network")
    func rejectsBadAddress() {
        #expect(throws: EthUnitsError.invalidAddress("0xnope")) {
            try ABI.encodeAddressCall(selector: ABI.balanceOfSelector, address: "0xnope")
        }
    }
}

@Suite("ABI decoding")
struct ABIDecodingTests {

    static func slot(_ value: String) -> String {
        "0x" + String(repeating: "0", count: 64 - value.count) + value
    }

    @Test("Decodes a full 32-byte word")
    func decodesUInt() throws {
        #expect(try ABI.decodeUInt(Self.slot("06")) == 6)
        #expect(try ABI.decodeUInt(Self.slot("3a35a2aee413f0a88")) == Decimal(string: "67111000000000101000")!)
    }

    @Test("Rejects a short return value rather than guessing")
    func rejectsShortData() {
        // A call to an address holding no contract returns "0x".
        #expect(throws: ABIError.unexpectedReturnLength("0x")) {
            try ABI.decodeUInt("0x")
        }
    }

    @Test("Decodes decimals for tokens that disagree")
    func decodesDecimals() throws {
        #expect(try ABI.decodeDecimals(Self.slot("06")) == 6)   // USDC
        #expect(try ABI.decodeDecimals(Self.slot("12")) == 18)  // LINK, 0x12
    }

    @Test("Rejects an implausible decimals value")
    func rejectsWildDecimals() {
        #expect(throws: ABIError.decimalsOutOfRange(255)) {
            try ABI.decodeDecimals(Self.slot("ff"))
        }
    }
}

@Suite("Token amounts")
struct TokenAmountTests {

    @Test("Scales by the token's own decimals, not by 10^18")
    func scaling() {
        let usdc = TokenBalance(token: Token.sepolia[0], raw: 1_038_730_007, decimals: 6)
        #expect(usdc.amount == Decimal(string: "1038.730007")!)

        // The same raw integer read as an 18-decimal token would be off by 10^12.
        let asEighteen = TokenBalance(token: Token.sepolia[0], raw: 1_038_730_007, decimals: 18)
        #expect(asEighteen.amount != usdc.amount)
        #expect(usdc.amount / asEighteen.amount == Decimal(string: "1000000000000")!)
    }

    @Test("Keeps full precision on an 18-decimal balance")
    func precision() {
        let weth = TokenBalance(
            token: Token.sepolia[2],
            raw: Decimal(string: "82421895501198212")!,
            decimals: 18
        )
        #expect(weth.amount == Decimal(string: "0.082421895501198212")!)
    }
}
