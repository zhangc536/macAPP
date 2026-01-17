import SwiftUI

struct OnboardingView: View {
    @Binding var isOnboardingCompleted: Bool
    
    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "terminal.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundColor(.blue)
            
            Text("欢迎使用 YourApp")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("YourApp 帮助你集中管理和监控本机上的各类服务项目。\n\n点击“开始使用”进入项目管理器。")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
            
            Button("开始使用") {
                isOnboardingCompleted = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingView(isOnboardingCompleted: .constant(false))
}
