import SwiftUI

struct LogView: View {
    @Binding var logs: String
    
    var body: some View {
        VStack {
            HStack {
                Text("日志")
                    .font(.headline)
                Spacer()
                Button("清空") {
                    logs = ""
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            ScrollView {
                Text(logs)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
        }
    }
}

#Preview {
    LogView(logs: .constant("[10:30:45] 应用启动...\n[10:30:46] 正在加载项目...\n"))
}
