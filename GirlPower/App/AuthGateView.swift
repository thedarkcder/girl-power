import AuthenticationServices
import SwiftUI

struct AuthGateView: View {
    @ObservedObject var viewModel: AppFlowViewModel
    let prompt: AuthPrompt

    @State private var email = ""
    @State private var password = ""
    @State private var mode: AuthMode = .signIn

    private enum AuthMode: String, CaseIterable, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn:
                return "Sign In"
            case .signUp:
                return "Create Account"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if let message = bannerMessage {
                        banner(message: message)
                    }
                    modePicker
                    form
                    appleButton
                    footer
                }
                .padding(24)
            }
            .background(
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.88, blue: 0.77), Color(red: 0.93, green: 0.73, blue: 0.58)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle(promptTitle)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(viewModel.isAuthBusy)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        viewModel.dismissAuthPrompt()
                    }
                    .disabled(viewModel.isAuthBusy)
                    .accessibilityIdentifier("auth_close_button")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt.message)
                .font(.title2.weight(.bold))
                .foregroundColor(.black)
            Text("Supabase keeps your session active so protected purchase and second-demo routes can recover after relaunch.")
                .font(.body)
                .foregroundColor(.black.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modePicker: some View {
        Picker("Authentication mode", selection: $mode) {
            ForEach(AuthMode.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("auth_mode_picker")
    }

    private var form: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .padding()
                .background(Color.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("auth_email_field")

            SecureField("Password", text: $password)
                .padding()
                .background(Color.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("auth_password_field")

            Button(action: submitEmailFlow) {
                HStack {
                    if viewModel.isAuthBusy {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(mode == .signIn ? "Continue with Email" : "Create Account")
                        .font(.headline)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .clipShape(Capsule())
            }
            .disabled(viewModel.isAuthBusy || email.isEmpty || password.count < 6)
            .accessibilityIdentifier(mode == .signIn ? "auth_sign_in_button" : "auth_sign_up_button")
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue, onRequest: viewModel.prepareAppleSignIn(request:), onCompletion: viewModel.completeAppleSignIn(result:))
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .clipShape(Capsule())
            .disabled(viewModel.isAuthBusy)
            .accessibilityIdentifier("auth_apple_button")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why this gate exists")
                .font(.headline)
                .foregroundColor(.black)
            Text("Your first coaching demo stays anonymous. A valid Supabase session is required before another demo or any subscription flow can continue.")
                .font(.footnote)
                .foregroundColor(.black.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var promptTitle: String {
        switch prompt.context {
        case .secondDemo:
            return "Unlock Demo Two"
        case .paywall:
            return "Secure Your Purchase"
        case .restore, .retry:
            return "Restore Access"
        }
    }

    private var bannerMessage: String? {
        switch viewModel.authState {
        case .authFailed(_, let message, _):
            return message
        case .authRequired(_, let message):
            return message
        default:
            return nil
        }
    }

    private func banner(message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundColor(.black)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func submitEmailFlow() {
        switch mode {
        case .signIn:
            viewModel.submitEmailSignIn(email: email, password: password)
        case .signUp:
            viewModel.submitEmailSignUp(email: email, password: password)
        }
    }
}
