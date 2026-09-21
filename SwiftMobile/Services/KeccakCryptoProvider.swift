import CryptoSwift
import Foundation
import WalletConnectSigner

enum CryptoProviderError: Error {
    case publicKeyRecoveryNotSupported
}

/// The `CryptoProvider` the SDK requires.
///
/// `keccak256` is Ethereum's hash function — not SHA-3 as standardised, but the
/// original Keccak padding. CryptoSwift implements it; Apple's CryptoKit does
/// not, which is the only reason this app has a crypto dependency at all.
struct KeccakCryptoProvider: CryptoProvider {

    func keccak256(_ data: Data) -> Data {
        Data(SHA3(variant: .keccak256).calculate(for: [UInt8](data)))
    }

    /// Only used for Sign In With Ethereum, which this app does not enable
    /// (`authRequestParams: nil`). Implementing it would mean pulling in
    /// secp256k1 public key recovery for a code path that never runs.
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        throw CryptoProviderError.publicKeyRecoveryNotSupported
    }
}
