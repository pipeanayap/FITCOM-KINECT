import SwiftUI

/// Foto de perfil redonda; sin foto, las iniciales del nombre (o un ícono si
/// no hay nombre). Reemplaza las copias de este mismo bloque en cada vista.
struct AvatarView: View {
    let url: String?
    let name: String
    var size: CGFloat = 50

    var body: some View {
        CachedAsyncImage(url: url.flatMap { URL(string: $0) }) { placeholder }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Color.brandAccent.opacity(0.15))
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.brandAccentText)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(Color.brandAccentText)
            }
        }
    }

    /// Primera y última palabra del nombre; un nombre sin letras (vacío o sólo
    /// símbolos) no produce iniciales.
    private var initials: String {
        let words = name.split(separator: " ").filter { $0.contains(where: \.isLetter) }
        guard let first = words.first else { return "" }
        let letters = words.count > 1 ? [first, words[words.count - 1]] : [first]
        return String(letters.compactMap { $0.first(where: \.isLetter) }).uppercased()
    }
}
