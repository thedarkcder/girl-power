import SwiftUI

struct DemoAttemptFlowView: View {
    let onExit: () -> Void

    var body: some View {
        SquatSessionView()
            .navigationTitle("Squat Coaching")
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
