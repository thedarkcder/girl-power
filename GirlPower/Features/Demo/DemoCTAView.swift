import SwiftUI

struct DemoCTAView: View {
    let onStartDemo: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 12) {
                Text("You're Ready")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.8))
                Text("Start your free momentum-building demo experience.")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            Button(action: onStartDemo) {
                Text("Start Free Demo")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 32)
            .accessibilityIdentifier("start_demo_button")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Routes to the Girl Power demo experience")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DemoCTAView_Previews: PreviewProvider {
    static var previews: some View {
        DemoCTAView(onStartDemo: {})
            .background(Color.black)
    }
}
