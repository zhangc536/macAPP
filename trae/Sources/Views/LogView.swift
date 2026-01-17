import SwiftUI

struct LogView: View {
    @Binding var logs: String
    
    var body: some View {
        VStack {
            HStack {
                Text("Logs")
                    .font(.headline)
                Spacer()
                Button("Clear") {
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
    LogView(logs: .constant("[10:30:45] Starting app...\n[10:30:46] Loading projects...\n"))
}
