import Foundation

enum EthUnitsError: Error, Equatable {
    case emptyHex
    case invalidHexDigit(Character)
    case invalidAddress(String)
}

enum EthUnits {

    /// 10^18 — one ether expressed in wei.
    static let weiPerEth = Decimal(sign: .plus, exponent: 18, significand: 1)

    /// Parses a JSON-RPC quantity ("0x2386f26fc10000") into wei.
    ///
    /// Decimal is used instead of UInt64 because an EVM quantity is 256-bit:
    /// UInt64 overflows above ~18.4 ETH. Decimal holds 38 significant digits,
    /// which covers every realistic balance.
    static func wei(fromHex hex: String) throws -> Decimal {
        let digits = hex.hasPrefix("0x") || hex.hasPrefix("0X")
            ? hex.dropFirst(2)
            : Substring(hex)
        guard !digits.isEmpty else { throw EthUnitsError.emptyHex }

        var value = Decimal.zero
        for char in digits {
            guard let digit = char.hexDigitValue else {
                throw EthUnitsError.invalidHexDigit(char)
            }
            value = value * 16 + Decimal(digit)
        }
        return value
    }

    /// Converts wei to ether. Exact: both sides are base-10 Decimal.
    static func eth(fromWei wei: Decimal) -> Decimal {
        wei / weiPerEth
    }

    /// Convenience for the common "hex quantity -> ETH" path.
    static func eth(fromHex hex: String) throws -> Decimal {
        eth(fromWei: try wei(fromHex: hex))
    }

    /// An EVM address is "0x" plus exactly 40 hex characters.
    /// ponytail: no EIP-55 checksum validation — add it when the app starts
    /// accepting addresses typed by the user rather than pasted ones.
    static func isValidAddress(_ address: String) -> Bool {
        address.count == 42
            && address.hasPrefix("0x")
            && address.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    static func validateAddress(_ address: String) throws -> String {
        guard isValidAddress(address) else {
            throw EthUnitsError.invalidAddress(address)
        }
        return address
    }
}
