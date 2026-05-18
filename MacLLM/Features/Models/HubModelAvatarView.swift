import SwiftUI

/// Hugging Face org/kullanıcı avatarı — `/api/avatars/{namespace}`.
struct HubModelAvatarView: View {
    let repoId: String
    var size: CGFloat = 40

    private var author: String {
        ModelMetadataParser.repoAuthor(repoId) ?? repoId.split(separator: "/").first.map(String.init) ?? "?"
    }

    private var avatarURL: URL? {
        let namespace = author.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? author
        return URL(string: "https://huggingface.co/api/avatars/\(namespace)")
    }

    var body: some View {
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        HubAuthorAvatarFallback(author: author, size: size)
                    case .empty:
                        HubAuthorAvatarFallback(author: author, size: size)
                    @unknown default:
                        HubAuthorAvatarFallback(author: author, size: size)
                    }
                }
            } else {
                HubAuthorAvatarFallback(author: author, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
    }

    private var cornerRadius: CGFloat {
        max(6, size * 0.22)
    }
}

struct HubAuthorAvatarFallback: View {
    let author: String
    var size: CGFloat = 40

    var body: some View {
        let initial = author.prefix(1).uppercased()
        ZStack {
            LinearGradient(
                colors: [
                    brandTint.opacity(0.35),
                    AppTheme.elevatedSurface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initial)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(brandTint)
        }
        .frame(width: size, height: size)
    }

    private var brandTint: Color {
        switch author.lowercased() {
        case "microsoft": return .blue
        case "meta-llama", "meta": return .indigo
        case "google", "google-bert": return .green
        case "mistralai", "mistral": return .orange
        case "qwen", "qwen2": return .purple
        case "unsloth": return .teal
        case "bartowski", "lmstudio-community": return .cyan
        default: return AppTheme.accent
        }
    }
}
