import ReownAppKit
import SwiftUI

struct BalanceView: View {
    @State private var viewModel = BalanceViewModel()
    private var wallet = WalletService.shared
    @State private var messageToSign = "Hello from SwiftMobile"

    var body: some View {
        NavigationStack {
            Form {
                Section("Wallet") {
                    AppKitButton()
                    LabeledContent("Relay socket") {
                        Text(wallet.socketConnected ? "connected" : "disconnected")
                            .foregroundStyle(wallet.socketConnected ? .green : .red)
                    }
                    if let address = wallet.address {
                        Button("Use connected address") {
                            viewModel.address = address
                            Task { await viewModel.load() }
                        }
                    }
                }

                if wallet.isConnected {
                    Section("Sign a message") {
                        TextField("Message", text: $messageToSign, axis: .vertical)
                            .lineLimit(1 ... 3)

                        Button("Sign with wallet") {
                            Task { await wallet.sign(message: messageToSign) }
                        }
                        .disabled(messageToSign.isEmpty || wallet.signing == .awaitingApproval)

                        switch wallet.signing {
                        case .idle:
                            EmptyView()
                        case .awaitingApproval:
                            Label("Approve in your wallet", systemImage: "hourglass")
                                .foregroundStyle(.secondary)
                        case .signed(let message, let signature):
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Signed", systemImage: "checkmark.seal")
                                    .foregroundStyle(.green)
                                Text(message)
                                    .font(.caption)
                                Text(signature)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        case .failed(let reason):
                            Label(reason, systemImage: "xmark.octagon")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Address") {
                    TextField("0x...", text: $viewModel.address)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !viewModel.address.isEmpty && !viewModel.isAddressValid {
                        Label("Needs 0x + 40 hex characters", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    Button("Fetch") {
                        Task { await viewModel.load() }
                    }
                    .disabled(!viewModel.isAddressValid)
                }

                Section("ETH") {
                    switch viewModel.state {
                    case .idle:
                        Text("Tap Fetch to read the chain.")
                            .foregroundStyle(.secondary)
                    case .loading:
                        ProgressView()
                    case .loaded(let chain):
                        row("Balance", "\(format(chain.balanceEth)) ETH")
                        row("Balance (wei)", format(chain.balanceWei))
                        row("Block", format(chain.blockNumber))
                        row("Gas price", "\(format(chain.gasPriceWei)) wei")
                    case .failed(let message):
                        Label(message, systemImage: "xmark.octagon")
                            .foregroundStyle(.red)
                    }
                }

                if case .loaded(let chain) = viewModel.state {
                    Section("Tokens") {
                        ForEach(chain.tokens) { balance in
                            LabeledContent(balance.token.symbol) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(format(balance.amount))
                                        .font(.system(.body, design: .monospaced))
                                    Text("\(format(balance.raw)) raw · \(balance.decimals) decimals")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sepolia Balance")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func format(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...8)))
    }
}

#Preview {
    BalanceView()
}
