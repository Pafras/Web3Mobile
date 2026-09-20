import Foundation

struct Token: Identifiable, Hashable, Sendable {
    let address: String
    let symbol: String

    var id: String { address }

    /// Addresses verified against Sepolia. `decimals` is read from each
    /// contract at runtime rather than hardcoded here — it is the contract's
    /// answer that matters, not this app's assumption.
    static let sepolia: [Token] = [
        Token(address: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", symbol: "USDC"),
        Token(address: "0x779877A7B0D9E8603169DdbD7836e478b4624789", symbol: "LINK"),
        Token(address: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14", symbol: "WETH"),
    ]
}

struct TokenBalance: Identifiable, Sendable {
    let token: Token
    /// The contract's raw integer, in the token's smallest unit.
    let raw: Decimal
    let decimals: Int

    var id: String { token.address }

    /// USDC uses 6 decimals, LINK 18. Dividing by the wrong power here is the
    /// classic ERC-20 bug: it misreports the balance by a factor of 10^12.
    var amount: Decimal { raw / pow(Decimal(10), decimals) }
}
