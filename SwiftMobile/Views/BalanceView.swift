import SwiftUI

struct BalanceView: View {
    @State private var viewModel = BalanceViewModel()

    var body: some View {
        NavigationStack {
            Form {
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
