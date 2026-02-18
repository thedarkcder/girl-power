import Foundation

protocol PaywallRouting {
    func presentPaywall()
}

final class PaywallRouter: PaywallRouting {
    func presentPaywall() {
        NotificationCenter.default.post(name: .init("paywall.present"), object: nil)
    }
}
