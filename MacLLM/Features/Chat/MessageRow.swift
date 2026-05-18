import SwiftUI

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.role == .user ? "person.circle.fill" : "sparkles")
                .font(.title2)
                .foregroundStyle(message.role == .user ? .blue : .purple)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? "Siz" : "Asistan")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(message.content.isEmpty ? "…" : message.content)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(message.role == .user ? Color.blue.opacity(0.08) : Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
