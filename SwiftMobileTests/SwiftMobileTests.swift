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
