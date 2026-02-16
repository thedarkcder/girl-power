import SwiftUI

struct DemoAttemptFlowView: View {
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.pink)
                .accessibilityHidden(true)
            Text("Demo Starting Soon")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("We're preparing the interactive experience. This placeholder keeps routing deterministic until the real flow ships.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
            Button(action: onExit) {
                Text("Back to CTA")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.pink.opacity(0.2))
                    .foregroundColor(.pink)
                    .clipShape(Capsule())
                    .padding(.horizontal, 32)
            }
            .accessibilityIdentifier("demo_exit_button")
            .accessibilityHint("Returns to the Start Free Demo screen")
            Spacer()
        }
        .padding(.top, 60)
        .navigationTitle("Girl Power Demo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onExit) {
                    Image(systemName: "chevron.left")
                    Text("CTA")
                }
                .accessibilityIdentifier("demo_toolbar_back_button")
                .accessibilityHint("Returns to the Start Free Demo screen")
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

struct DemoAttemptFlowView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DemoAttemptFlowView(onExit: {})
        }
    }
}
