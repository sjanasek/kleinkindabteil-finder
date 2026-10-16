import SwiftUI

struct SearchView: View {
  @State private var model = SearchModel()
  @AppStorage("lastFrom") private var lastFrom = ""
  @AppStorage("lastTo") private var lastTo = ""
  @State private var showResults = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Strecke") {
          StationField(title: "Von", text: $model.from, placeholder: "z. B. Berlin Hbf")
          StationField(title: "Nach", text: $model.to, placeholder: "z. B. München Hbf")
        }
        Section("Wann") {
          DatePicker("Datum", selection: $model.date, in: Date.now..., displayedComponents: .date)
          Toggle("Ganzer Tag", isOn: $model.wholeDay)
          if !model.wholeDay {
            DatePicker("Ab Uhrzeit", selection: $model.time, displayedComponents: .hourAndMinute)
          }
        }
        Section {
          Stepper("Erwachsene: \(model.adults)", value: $model.adults, in: 1...5)
          LabeledContent("Kinder (Alter)") {
            TextField("z. B. 1, 4", text: $model.childAges)
              .multilineTextAlignment(.trailing)
              .keyboardType(.numbersAndPunctuation)
          }
        } header: {
          Text("Reisende")
        } footer: {
          Text("Gesucht werden \(max(1, model.adults) + model.ages.count) freie Plätze zusammen in einem Kleinkindabteil.")
        }
        Section("Filter") {
          Picker("Umstiege", selection: $model.maxTransfers) {
            Text("egal").tag(Int?.none)
            Text("direkt").tag(Int?.some(0))
            Text("max. 1").tag(Int?.some(1))
            Text("max. 2").tag(Int?.some(2))
          }
          Picker("Bedingung", selection: $model.requireAll) {
            Text("jeder ICE/IC frei").tag(true)
            Text("mind. ein ICE/IC frei").tag(false)
          }
          Toggle("Auch volle Verbindungen zeigen", isOn: $model.showAll)
        }
        Section {
          Button {
            lastFrom = model.from
            lastTo = model.to
            model.search()
            showResults = true
          } label: {
            Label("Verbindungen prüfen", systemImage: "magnifyingglass")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .disabled(model.from.trimmingCharacters(in: .whitespaces).isEmpty || model.to.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        Section {
          Text("Inoffiziell: liest das Backend des DB Navigators. Momentaufnahme ohne Gewähr; ob ein Platz wirklich buchbar ist, zeigt erst die Buchung auf bahn.de.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Kleinkindabteil")
      .navigationDestination(isPresented: $showResults) {
        ResultsView(model: model)
      }
      .onAppear {
        if model.from.isEmpty { model.from = lastFrom }
        if model.to.isEmpty { model.to = lastTo }
        #if DEBUG
        // Für Screenshots/Simulator: KK_DEMO="Hamburg Hbf|Köln Hbf|2026-11-12" startet sofort eine Suche.
        if let demo = ProcessInfo.processInfo.environment["KK_DEMO"] {
          let p = demo.split(separator: "|").map(String.init)
          if p.count >= 2 { model.from = p[0]; model.to = p[1] }
          if p.count >= 3, let d = try? Date(p[2], strategy: .iso8601.year().month().day()) { model.date = d }
          model.adults = 2; model.childAges = "1, 4"; model.wholeDay = true
          model.search()
          showResults = true
        }
        #endif
      }
    }
  }
}

#Preview {
  SearchView()
}
