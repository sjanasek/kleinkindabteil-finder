import SwiftUI

struct ResultsView: View {
  @Bindable var model: SearchModel

  var body: some View {
    List {
      Section {
        statusRow
      }
      if model.visibleResults.isEmpty, model.phase == .done {
        ContentUnavailableView(
          "Kein passendes Kleinkindabteil",
          systemImage: "figure.and.child.holdinghands",
          description: Text("Keine der \(model.total) Verbindungen hat \(model.seatsNeeded) freie Plätze zusammen in einem Kleinkindabteil. Tipp: anderes Datum, oder „Auch volle Verbindungen zeigen“ für den Familienbereich als Ausweichoption.")
        )
      }
      ForEach(model.visibleResults) { item in
        JourneyCard(item: item)
          .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if model.isRunning {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Abbrechen", role: .cancel) { model.cancel() }
        }
      } else {
        ToolbarItem(placement: .topBarTrailing) {
          Toggle("Alle", isOn: $model.showAll).toggleStyle(.button)
        }
      }
    }
  }

  private var title: String {
    if let f = model.fromStation, let t = model.toStation { "\(f.name) → \(t.name)" } else { "Ergebnisse" }
  }

  @ViewBuilder private var statusRow: some View {
    switch model.phase {
    case .idle:
      Text("Bereit.")
    case .resolving:
      HStack { ProgressView(); Text("Suche Haltestellen …") }
    case .loading(let page, let found):
      HStack { ProgressView(); Text("Lade Zeitfenster \(page) … (\(found) Verbindungen)") }
    case .checking(let done, let total):
      VStack(alignment: .leading, spacing: 6) {
        HStack { ProgressView(); Text("Prüfe Sitzpläne … \(done)/\(total)") }
        ProgressView(value: Double(done), total: Double(max(total, 1)))
        Text("Gesucht: \(model.seatsNeeded) freie Plätze je ICE/IC in einem Abteil").font(.footnote).foregroundStyle(.secondary)
      }
    case .done:
      let ok = model.results.count(where: \.ok)
      Label("\(ok) von \(model.total) Verbindungen mit \(model.seatsNeeded) freien Plätzen im Kleinkindabteil",
            systemImage: ok > 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(ok > 0 ? .green : .red)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
    }
  }
}
