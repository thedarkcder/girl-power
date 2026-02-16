# How to Test Girl Power App Flow

1. Build the app target:
   ```sh
   xcodebuild -scheme GirlPower -destination 'platform=iOS Simulator,name=iPhone 15' build
   ```
2. Run targeted regression tests for the state machine invariants:
   ```sh
   xcodebuild test -scheme GirlPower -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:GirlPowerTests/AppFlowStateMachineTests
   ```
3. Run the full test suite (unit + UI tests):
   ```sh
   xcodebuild test -scheme GirlPower -destination 'platform=iOS Simulator,name=iPhone 15'
   ```
4. Launch the app on the simulator:
   - First launch should show the splash, onboarding carousel (three slides), CTA, then demo stub.
   - Relaunching after completing onboarding should land directly on the CTA screen.
    - Launch with `-resetOnboarding` to force onboarding, `-returningUser` to verify skip logic.
