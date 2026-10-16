import SwiftUI

/// Textfeld mit Haltestellen-Vorschlägen aus dem Backend.
struct StationField: View {
  let title: String
  @Binding var text: String
  let placeholder: String

  @State private var suggestions: [Station] = []
  @State private var lookup: Task<Void, Never>?
  @State private var chosen = false
  @FocusState private var focused: Bool
  private let client = DBClient()

  var body: some View {
    LabeledContent(title) {
      TextField(placeholder, text: $text)
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .focused($focused)
        .onChange(of: text) { _, new in
          if chosen { chosen = false; return }
          schedule(new)
        }
    }
    if focused, !suggestions.isEmpty {
      ForEach(suggestions, id: \.locationId) { s in
        Button {
          chosen = true
          text = s.name
          suggestions = []
          focused = false
        } label: {
          Label(s.name, systemImage: "tram.fill")
            .foregroundStyle(.primary)
        }
      }
    }
  }

  private func schedule(_ term: String) {
    lookup?.cancel()
    let query = term.trimmingCharacters(in: .whitespaces)
    guard query.count >= 2 else { suggestions = []; return }
    lookup = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      let hits = (try? await client.searchStations(query)) ?? []
      guard !Task.isCancelled else { return }
      suggestions = Array(hits.prefix(6))
    }
  }
}
