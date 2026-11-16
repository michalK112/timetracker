import SwiftUI

/// Kolorowa ikona w zaokrąglonym kwadracie, jak w Ustawieniach systemowych.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
            .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
    }
}

/// Układ zawijający elementy do kolejnych wierszy (słowa kluczowe, legenda).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// Mała etykieta z obramowaniem (godziny, narzędzie).
struct Tag<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 5) { content }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
    }
}

struct StatusTag: View {
    let status: EntryStatus
    var body: some View {
        Text(status.label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(status.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Edytor listy słów kluczowych: chipy z usuwaniem + pole z przyciskiem „Dodaj”.
/// Można wpisać kilka słów naraz, oddzielając je przecinkami; Enter też dodaje.
struct KeywordEditor: View {
    @Binding var words: [String]
    var placeholder: String
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !words.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                        HStack(spacing: 4) {
                            Text(w).lineLimit(1)
                            Button { words.remove(at: i) } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Usuń „\(w)”")
                        }
                        .font(.system(size: 12.5))
                        .padding(.leading, 9).padding(.trailing, 6)
                        .frame(height: 24)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("Słowo kluczowe", text: $draft, prompt: Text(placeholder))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { add(); focused = true }
                Button {
                    add()
                    focused = true
                } label: {
                    Label("Dodaj", systemImage: "plus")
                }
                .disabled(draft.trimmed.isEmpty)
            }
            if words.isEmpty {
                Text("Brak słów kluczowych — wpisz słowo i kliknij Dodaj (kilka naraz oddziel przecinkami).")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func add() {
        let parts = draft.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        for p in parts where !words.contains(where: { $0.lowercased() == p.lowercased() }) { words.append(p) }
        draft = ""
    }
}
