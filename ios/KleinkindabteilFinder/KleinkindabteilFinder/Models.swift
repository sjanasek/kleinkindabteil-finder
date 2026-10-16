import Foundation

// Alle Modelle sind reine Werte und `nonisolated`, damit sie in jedem
// Isolationskontext dekodiert und weitergereicht werden können.

nonisolated struct Station: Hashable, Sendable {
  let name: String
  let locationId: String
  let evaNr: String
}

nonisolated struct LoadInfo: Hashable, Sendable {
  let level: Int
  let text: String
}

nonisolated struct Leg: Hashable, Sendable, Identifiable {
  var id: String { "\(name)@\(departure)" }
  let name: String            // "ICE 505"
  let product: String         // "ICE", "REGIONAL", "FLX", …
  let trainNumber: String
  let from: String
  let fromEva: String
  let departure: String       // ISO mit Offset, wie vom Backend geliefert
  let departurePlatform: String?
  let to: String
  let toEva: String
  let arrival: String
  let arrivalPlatform: String?
  let load: LoadInfo?

  static let reservable: Set<String> = ["ICE", "IC", "EC", "ECE"]
  static let regional: Set<String> = ["REGIONAL", "SBAHN", "BUS", "SCHIFF", "UBAHN", "TRAM", "ANRUFPFLICHTIG", "RE", "RB", "IRE", "S"]
  var isReservable: Bool { Self.reservable.contains(product) }
  var isRegional: Bool { Self.regional.contains(product) }
}

nonisolated struct Journey: Hashable, Sendable, Identifiable {
  var id: String { legs.map(\.id).joined(separator: "|") }
  let duration: Int           // Sekunden
  let transfers: Int
  let departure: String
  let arrival: String
  let load: LoadInfo?
  let price: Double?
  let legs: [Leg]
  let context: String?        // HAFAS-Kontext für „Verbindung teilen“

  var departureDate: Date? { ISO8601.parse(departure) }
  var arrivalDate: Date? { ISO8601.parse(arrival) }
}

/// Ergebnis der Prüfung eines Abschnitts.
nonisolated enum LegCheck: Hashable, Sendable {
  case skipped                 // Nahverkehr / fremder Betreiber
  case unavailable             // kein Sitzplan abrufbar
  case failed(String)
  case checked(SeatReport)
}

nonisolated struct SeatReport: Hashable, Sendable {
  struct Zone: Hashable, Sendable {
    struct Seat: Hashable, Sendable { let number: String; let free: Bool }
    let seats: [Seat]
    var free: Int { seats.count(where: \.free) }
    var total: Int { seats.count }
    var freeNumbers: [String] { seats.filter(\.free).map(\.number) }
  }
  struct Coach: Hashable, Sendable {
    let number: String
    let kleinkind: Zone
    let familie: Zone
    let kinderwagen: Bool
  }
  let coaches: [Coach]
  /// Meiste freie Plätze in EINEM Kleinkindabteil – die Familie sitzt zusammen.
  var kleinkindBest: Int { coaches.map(\.kleinkind.free).max() ?? 0 }
  var kleinkindTotal: Int { coaches.reduce(0) { $0 + $1.kleinkind.total } }
  var kinderwagenCoaches: [String] { coaches.filter(\.kinderwagen).map(\.number) }
}

/// Eine geprüfte Verbindung, wie sie die Ergebnisliste zeigt.
nonisolated struct CheckedJourney: Hashable, Sendable, Identifiable {
  var id: String { journey.id }
  let journey: Journey
  let checks: [LegCheck]
  let seatsNeeded: Int
  let requireAll: Bool
  var link: URL?

  var relevant: [SeatReport] {
    checks.compactMap { if case .checked(let r) = $0 { r } else { nil } }
  }
  var unknownCount: Int {
    checks.count { if case .unavailable = $0 { true } else if case .failed = $0 { true } else { false } }
      + journey.legs.count { !$0.isReservable && !$0.isRegional }
  }
  var hasLongDistance: Bool { !relevant.isEmpty || unknownCount > 0 }
  var ok: Bool {
    guard !relevant.isEmpty, unknownCount == 0 else { return false }
    let good = relevant.count { $0.kleinkindBest >= seatsNeeded }
    return requireAll ? good == relevant.count : good > 0
  }
}

// MARK: - Rohdaten vom Backend (nur die Felder, die wir brauchen)

nonisolated struct RawLocation: Decodable {
  let locationId: String
  let locationType: String
  let name: String
  let evaNr: String?
}

nonisolated struct RawFahrplan: Decodable {
  let verbindungen: [RawVerbindungWrapper]
  let spaeterContext: String?
}
nonisolated struct RawVerbindungWrapper: Decodable {
  let verbindung: RawVerbindung
  let angebote: RawAngebote?
}
nonisolated struct RawAngebote: Decodable {
  struct Preise: Decodable {
    struct Gesamt: Decodable { struct Ab: Decodable { let betrag: Double }; let ab: Ab? }
    let gesamt: Gesamt?
  }
  let preise: Preise?
}
nonisolated struct RawAuslastung: Decodable {
  let klasse: String
  let stufe: Int
  let anzeigeTextKurz: String?
}
nonisolated struct RawVerbindung: Decodable {
  let reiseDauer: Int
  let umstiegeAnzahl: Int
  let kontext: String?
  let auslastungsInfos: [RawAuslastung]?
  let verbindungsAbschnitte: [RawAbschnitt]
}
nonisolated struct RawOrt: Decodable { let name: String; let evaNr: String? }
nonisolated struct RawHalt: Decodable { let gleis: String? }
nonisolated struct RawAbschnitt: Decodable {
  let typ: String
  let mitteltext: String?
  let produktGattung: String?
  let zugNummer: String?
  let verkehrsmittelNummer: String?
  let abgangsOrt: RawOrt?
  let abgangsDatum: String?
  let ankunftsOrt: RawOrt?
  let ankunftsDatum: String?
  let halte: [RawHalt]?
  let auslastungsInfos: [RawAuslastung]?
}

nonisolated struct RawSeatSSR: Decodable {
  struct Zugfahrt: Decodable { let zugteile: [Zugteil]? }
  struct Zugteil: Decodable { let wagen: [Wagen]? }
  struct Wagen: Decodable { let nummer: String; let wagentyp: String; let plaetze: [Platz]? }
  struct Platz: Decodable { let nummer: String; let status: Int }
  let zugfahrt: Zugfahrt?
}

nonisolated struct SeatCoach: Sendable {
  let number: String
  let wagentyp: String
  let status: [String: Int]   // Platznummer → 0 belegt, 1/2 frei
}

nonisolated struct CoachLayout: Codable, Sendable {
  struct Element: Codable, Sendable {
    let x: Double
    let y: Double
    let type: String
    let subtype: String?
    let nummer: String?
  }
  let elements: [Element]
}
nonisolated struct RawWagentyp: Decodable {
  struct Teil: Decodable { let elemente: [CoachLayout.Element]? }
  let wagenteile: [Teil]?
}

nonisolated struct RawShare: Decodable { let vbid: String? }

// MARK: - Zeit-Helfer

nonisolated enum ISO8601 {
  static func parse(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s)
  }
  /// Lokale Zeit mit Offset (Europe/Berlin), wie die App sie sendet.
  static func withOffset(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Europe/Berlin")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
    return f.string(from: date)
  }
  /// Lokale Zeit ohne Offset, wie die Sitzplatzanzeige sie erwartet.
  static func naive(_ iso: String) -> String {
    var s = iso
    if s.hasSuffix("Z") { s.removeLast() }
    else if s.count > 6, let r = s.range(of: #"[+-]\d\d:\d\d$"#, options: .regularExpression) { s.removeSubrange(r) }
    return String(s.prefix(19))
  }
  static func dayKey(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Europe/Berlin")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
  }
  static func dayKey(_ iso: String) -> String? { parse(iso).map(dayKey) }
}
