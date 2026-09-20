import Foundation

enum ABIError: Error, Equatable {
    case unexpectedReturnLength(String)
    case decimalsOutOfRange(Decimal)
}

/// The little bit of ABI encoding this app needs.
///
/// A node does not understand "call balanceOf". It takes bytes. Those bytes are
/// a 4-byte function selector followed by the arguments, each padded to 32.
enum ABI {

    /// First 4 bytes of keccak256("balanceOf(address)").
    static let balanceOfSelector = "0x70a08231"
    /// First 4 bytes of keccak256("decimals()").
    static let decimalsSelector = "0x313ce567"

    /// Encodes a call to a function taking a single address argument.
    ///
    /// Every ABI argument occupies a 32-byte slot, right-aligned. An address is
    /// 20 bytes, so it gets 12 zero bytes (24 hex zeros) in front of it.
    static func encodeAddressCall(selector: String, address: String) throws -> String {
        let checked = try EthUnits.validateAddress(address)
        let padding = String(repeating: "0", count: 24)
        return selector + padding + checked.dropFirst(2)
    }

    /// Decodes a single 32-byte unsigned integer return value.
    static func decodeUInt(_ hex: String) throws -> Decimal {
        let digits = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard digits.count == 64 else {
            throw ABIError.unexpectedReturnLength(hex)
        }
        return try EthUnits.wei(fromHex: digits)
    }

    /// Decodes `decimals()`. It is declared uint8 but still arrives in a full
    /// 32-byte slot. The range check matters: a wrong value here rescales the
    /// balance by orders of magnitude.
    static func decodeDecimals(_ hex: String) throws -> Int {
        let value = try decodeUInt(hex)
        guard value >= 0, value <= 36 else {
            throw ABIError.decimalsOutOfRange(value)
        }
        return NSDecimalNumber(decimal: value).intValue
    }
}
