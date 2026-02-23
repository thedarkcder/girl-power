import SwiftUI

struct PaywallView: View {
    @StateObject private var viewModel: PaywallViewModel
    let onClose: () -> Void

    init(viewModel: PaywallViewModel, onClose: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                priceCard
                featureList
                legalLinks
                actionButtons
                if let error = viewModel.errorMessage {
                    errorBanner(message: error)
                }
                if let success = viewModel.successMessage {
                    successBanner(message: success)
                }
            }
            .padding(24)
        }
        .background(LinearGradient(
            gradient: Gradient(colors: [Color(red: 0.05, green: 0.04, blue: 0.09), Color(red: 0.16, green: 0.08, blue: 0.21)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close", action: onClose)
                    .foregroundColor(.white)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unlock Coaching")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            Text("Go beyond the two demo sessions with unlimited pro guidance.")
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.titleText)
                .font(.title3.bold())
                .foregroundColor(.white)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(viewModel.priceText)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(.white)
                Text("per month")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
            }
            if viewModel.isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.featureBullets, id: \.self) { feature in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text(feature)
                        .foregroundColor(.white)
                        .font(.body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legalLinks: some View {
        HStack {
            Link("Privacy Policy", destination: viewModel.privacyURL)
                .foregroundColor(.white)
            Spacer()
            Link("Terms of Use", destination: viewModel.termsURL)
                .foregroundColor(.white)
        }
        .font(.footnote)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: viewModel.subscribe) {
                Text(viewModel.state.isSubscribed ? "Subscribed" : "Subscribe")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isSubscribeDisabled ? Color.white.opacity(0.4) : Color.white)
                    .clipShape(Capsule())
            }
            .disabled(viewModel.isSubscribeDisabled)
            .accessibilityIdentifier("paywall_subscribe_cta")

            Button(action: viewModel.restore) {
                Text("Restore Purchases")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
            }
            .disabled(viewModel.isRestoreDisabled)
            .accessibilityIdentifier("paywall_restore_cta")
        }
    }

    private func errorBanner(message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func successBanner(message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
