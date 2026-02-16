import SwiftUI

struct SplashView: View {
    let onFinished: () -> Void
    @State private var hasTriggeredFinish = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.98, green: 0.23, blue: 0.54), Color(red: 0.42, green: 0.15, blue: 0.49)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 16) {
                Image(systemName: "bolt.heart.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundColor(.white)
                    .accessibilityHidden(true)
                Text("Girl Power")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Amplify fearless teams")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Girl Power — Amplify fearless teams")
            .accessibilityHint("Splash screen appears briefly before onboarding begins")
        }
        .ignoresSafeArea()
        .onAppear(perform: triggerFinish)
    }

    private func triggerFinish() {
        guard !hasTriggeredFinish else { return }
        hasTriggeredFinish = true
        DispatchQueue.main.async {
            onFinished()
        }
    }
}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView(onFinished: {})
    }
}
