import SwiftUI

struct JourneyCard: View {
  let item: CheckedJourney

  private var j: Journey { item.journey }
  private var tint: Color { item.ok ? .green : (item.unknownCount > 0 ? .orange : .red) }
  private var badge: String {
    if item.ok { "Kleinkindabteil frei" }
    else if item.unknownCount > 0 { "Nicht prüfbar" }
    else if item.hasLongDistance { "Kleinkindabteil voll" }
    else { "Kein ICE/IC" }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(clock(j.departure)) → \(clock(j.arrival))")
          .font(.title3.weight(.bold).monospacedDigit())
        Spacer()
        Text(badge)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(tint.opacity(0.15), in: Capsule())
          .foregroundStyle(tint)
      }
      Text(meta)
        .font(.subheadline)
        .foregroundStyle(.secondary)

      ForEach(Array(zip(j.legs.indices, j.legs)), id: \.0) { i, leg in
        legView(leg, check: item.checks[i])
      }

      if let link = item.link {
        Link(destination: link) {
          Label("Auf bahn.de öffnen & Sitzplatz wählen", systemImage: "arrow.up.right.square")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(.vertical, 4)
    .overlay(alignment: .leading) {
      RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4).padding(.leading, -14)
    }
  }

  private var meta: String {
    var parts = ["\(j.duration / 3600) h \(String(format: "%02d", j.duration % 3600 / 60)) min"]
    parts.append(j.transfers == 0 ? "direkt" : "\(j.transfers) Umstieg\(j.transfers > 1 ? "e" : "")")
    if let p = j.price { parts.append("ab \(p.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE"))))") }
    return parts.joined(separator: " · ")
  }

  @ViewBuilder private func legView(_ leg: Leg, check: LegCheck) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Divider()
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(leg.name).fontWeight(.semibold)
        Text("\(clock(leg.departure)) \(leg.from)\(leg.departurePlatform.map { " (Gl. \($0))" } ?? "") → \(clock(leg.arrival)) \(leg.to)")
          .font(.subheadline)
      }
      if let load = leg.load { Text(load.text).font(.caption).foregroundStyle(.secondary) }
      zones(for: leg, check: check)
    }
  }

  @ViewBuilder private func zones(for leg: Leg, check: LegCheck) -> some View {
    switch check {
    case .skipped:
      chip(leg.isRegional ? "Nahverkehr – Mehrzweckbereich nutzen" : "Kein DB-Reservierungssystem – nicht prüfbar", tint: .secondary)
    case .unavailable:
      chip("Kein Sitzplan abrufbar", tint: .secondary)
    case .failed(let msg):
      chip("Fehler: \(msg)", tint: .orange)
    case .checked(let r):
      if r.coaches.isEmpty { chip("Kein Kleinkindabteil in diesem Zug", tint: .secondary) }
      ForEach(r.coaches, id: \.number) { c in
        if c.kleinkind.total > 0 {
          let free = c.kleinkind.free
          chip("👶 Wagen \(c.number) Kleinkindabteil: \(free)/\(c.kleinkind.total) frei"
               + (free > 0 ? " (Platz \(c.kleinkind.freeNumbers.joined(separator: ", ")))" : ""),
               tint: free >= item.seatsNeeded ? .green : (free > 0 ? .orange : .red))
        }
        if c.familie.total > 0 {
          chip("👨‍👩‍👧 Wagen \(c.number) Familienbereich: \(c.familie.free)/\(c.familie.total) frei",
               tint: c.familie.free > 0 ? .green : .red)
        }
      }
      if !r.kinderwagenCoaches.isEmpty {
        chip("🛒 Kinderwagen: Wagen \(r.kinderwagenCoaches.joined(separator: ", "))", tint: .secondary)
      }
    }
  }

  private func chip(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(.footnote)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 8).padding(.vertical, 4)
      .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
      .foregroundStyle(tint == .secondary ? Color.primary : tint)
  }

  private func clock(_ iso: String) -> String {
    guard let d = ISO8601.parse(iso) else { return "–" }
    return d.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE")))
  }
}
