import Foundation

/// Erkennung von Kleinkindabteil und Familienbereich im Wagen-Layout.
nonisolated enum SeatAnalysis {
  struct Zones: Equatable, Sendable {
    var kleinkind: [String] = []
    var familie: [String] = []
    var kinderwagen = false
    var hasKleinkindSymbol = false
    var hasFamilieSymbol = false
    var isRelevant: Bool { hasKleinkindSymbol || hasFamilieSymbol || kinderwagen }
  }

  /// Kleinkindabteil: Plätze zwischen den nächsten Trennwänden links/rechts des
  /// Symbols (Fallback: Radius 8). Familienbereich: Plätze im Radius 12 um das Symbol.
  static func zones(in layout: CoachLayout) -> Zones {
    var out = Zones()
    let els = layout.elements
    let seats = els.filter { $0.type == "PLATZ" }
    let walls = els.filter { $0.type == "EINBAU" && ($0.subtype ?? "").hasPrefix("WAND") }
    out.kinderwagen = els.contains { $0.subtype == "KINDERWAGEN" }

    for sym in els where sym.type == "SYMBOL" && sym.subtype == "KLEINKINDABTEIL" {
      out.hasKleinkindSymbol = true
      let left = walls.filter { $0.x <= sym.x }.max(by: { $0.x < $1.x })
      let right = walls.filter { $0.x >= sym.x }.min(by: { $0.x < $1.x })
      let (lo, hi): (Double, Double) = if let left, let right, right.x - left.x <= 24 {
        (left.x, right.x)
      } else {
        (sym.x - 8, sym.x + 8)
      }
      for s in seats where s.x >= lo && s.x <= hi {
        if let n = s.nummer, !out.kleinkind.contains(n) { out.kleinkind.append(n) }
      }
    }
    for sym in els where sym.type == "SYMBOL" && sym.subtype == "FAMILIENBEREICH" {
      out.hasFamilieSymbol = true
      for s in seats where abs(s.x - sym.x) <= 12 {
        if let n = s.nummer, !out.kleinkind.contains(n), !out.familie.contains(n) { out.familie.append(n) }
      }
    }
    return out
  }

  static func report(coaches: [SeatCoach], layouts: [String: CoachLayout?]) -> SeatReport {
    var result: [SeatReport.Coach] = []
    for c in coaches {
      guard let layout = layouts[c.wagentyp] ?? nil else { continue }
      let z = zones(in: layout)
      guard z.isRelevant else { continue }
      let zone = { (nrs: [String]) in
        SeatReport.Zone(seats: nrs.map { .init(number: $0, free: [1, 2].contains(c.status[$0] ?? 0)) })
      }
      result.append(.init(number: c.number, kleinkind: zone(z.kleinkind), familie: zone(z.familie), kinderwagen: z.kinderwagen))
    }
    return SeatReport(coaches: result)
  }
}

extension DBClient {
  /// Prüft einen Abschnitt: Sitzplan laden, Layouts laden, auswerten.
  func check(_ leg: Leg) async -> LegCheck {
    guard leg.isReservable else { return .skipped }
    do {
      guard let coaches = try await fetchSeatMap(for: leg) else { return .unavailable }
      var layouts: [String: CoachLayout?] = [:]
      for typ in Set(coaches.map(\.wagentyp)) {
        layouts[typ] = try await layout(for: typ)
      }
      return .checked(SeatAnalysis.report(coaches: coaches, layouts: layouts))
    } catch is CancellationError {
      return .failed("abgebrochen")
    } catch {
      return .failed(error.localizedDescription)
    }
  }
}
