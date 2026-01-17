import SwiftUI

@main
struct YourApp: App {
    @AppStorage("isOnboardingCompleted") private var isOnboardingCompleted = false
    
    var body: some Scene {
        WindowGroup {
            if isOnboardingCompleted {
                ContentView()
            } else {
                OnboardingView(isOnboardingCompleted: $isOnboardingCompleted)
            }
        }
    }
}
