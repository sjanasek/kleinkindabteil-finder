import Foundation
import os

/// Zugriff auf das (inoffizielle) Backend des DB Navigators.
/// Nur lesend: Haltestellen, Verbindungen, Sitzplatzanzeige, Teilen-Link.
nonisolated struct DBClient: Sendable {
  enum Failure: Error, LocalizedError {
    case http(Int, String)
    case blocked
    case noSeatPlan
    var errorDescription: String? {
      switch self {
      case .http(let code, let body): "DB-Backend antwortet mit HTTP \(code): \(body.prefix(120))"
      case .blocked: "Die Bahn blockiert gerade Anfragen (OPS_BLOCKED). Bitte später erneut versuchen."
      case .noSeatPlan: "Sitzplan nicht abrufbar"
      }
    }
  }

  private static let base = URL(string: "https://app.services-bahn.de/mob")!
  private static let userAgent = "DBNavigator/Android/26.9.0"
  private static let journeyMedia = "application/x.db.vendo.mob.verbindungssuche.v9+json"
  private static let locationMedia = "application/x.db.vendo.mob.location.v3+json"
  private static let shareMedia = "application/x.db.vendo.mob.verbindungteilen.v1+json"
  private static let log = Logger(subsystem: "de.janasek.kleinkindabteilfinder", category: "db")

  let session: URLSession
  let layouts: LayoutCache

  init(session: URLSession = DBClient.makeSession(), layouts: LayoutCache = LayoutCache()) {
    self.session = session
    self.layouts = layouts
  }

  /// Der DB-Edge (Akamai) filtert nach TLS-Fingerabdruck: ein Standard-
  /// URLSession-ClientHello wird auf `angebote/fahrplan` mit OPS_BLOCKED
  /// abgewiesen, ein reiner TLS-1.3-Handshake nicht. Empirisch ermittelt.
  static func makeSession() -> URLSession {
    let c = URLSessionConfiguration.ephemeral
    c.tlsMinimumSupportedProtocolVersion = .TLSv13
    c.timeoutIntervalForRequest = 25
    c.waitsForConnectivity = true
    return URLSession(configuration: c)
  }

  // MARK: Haltestellen

  func searchStations(_ term: String) async throws -> [Station] {
    let raw: [RawLocation] = try await post("location/search", media: Self.locationMedia,
                                            body: ["locationTypes": ["ALL"], "searchTerm": term])
    return raw.filter { $0.locationType == "ST" }
      .map { Station(name: $0.name, locationId: $0.locationId, evaNr: $0.evaNr ?? "") }
  }

  /// Bester Treffer: exakter Name vor erstem Treffer.
  func resolveStation(_ term: String) async throws -> Station? {
    let hits = try await searchStations(term)
    let norm = { (s: String) in s.lowercased().split(separator: " ").joined(separator: " ") }
    return hits.first { norm($0.name) == norm(term) } ?? hits.first
  }

  // MARK: Verbindungen

  struct Traveller: Sendable { let type: String; let age: Int? }

  static func travellers(adults: Int, childAges: [Int]) -> [Traveller] {
    Array(repeating: Traveller(type: "ERWACHSENER", age: nil), count: max(1, adults))
      + childAges.map { Traveller(type: $0 <= 5 ? "KLEINKIND" : "FAMILIENKIND", age: $0) }
  }

  func searchJourneys(from: Station, to: Station, departure: Date, travellers: [Traveller],
                      maxTransfers: Int?, context: String?) async throws -> (journeys: [Journey], later: String?) {
    var wunsch: [String: Any] = [
      "abgangsLocationId": from.locationId,
      "alternativeHalteBerechnung": true,
      "verkehrsmittel": ["ALL"],
      "zeitWunsch": ["reiseDatum": ISO8601.withOffset(departure), "zeitPunktArt": "ABFAHRT"],
      "zielLocationId": to.locationId,
    ]
    if let maxTransfers { wunsch["maxUmstiege"] = maxTransfers }
    if let context { wunsch["context"] = context }
    let reisende: [[String: Any]] = travellers.map { t in
      var r: [String: Any] = ["ermaessigungen": ["KEINE_ERMAESSIGUNG KLASSENLOS"], "reisendenTyp": t.type]
      if let age = t.age { r["alter"] = age }
      return r
    }
    let body: [String: Any] = [
      "autonomeReservierung": false,
      "einstiegsTypList": ["STANDARD"],
      "fahrverguenstigungen": ["deutschlandTicketVorhanden": false, "nurDeutschlandTicketVerbindungen": false],
      "klasse": "KLASSE_2",
      "reiseHin": ["wunsch": wunsch],
      "reisendenProfil": ["reisende": reisende],
      "reservierungsKontingenteVorhanden": false,
    ]
    let raw: RawFahrplan = try await post("angebote/fahrplan", media: Self.journeyMedia, body: body)
    return (raw.verbindungen.map(Self.journey(from:)), raw.spaeterContext)
  }

  private static func journey(from w: RawVerbindungWrapper) -> Journey {
    let v = w.verbindung
    let legs: [Leg] = v.verbindungsAbschnitte.filter { $0.typ == "FAHRZEUG" }.map { a in
      Leg(name: a.mitteltext ?? "", product: a.produktGattung ?? "",
          trainNumber: a.zugNummer ?? a.verkehrsmittelNummer ?? "",
          from: a.abgangsOrt?.name ?? "", fromEva: a.abgangsOrt?.evaNr ?? "",
          departure: a.abgangsDatum ?? "", departurePlatform: a.halte?.first?.gleis,
          to: a.ankunftsOrt?.name ?? "", toEva: a.ankunftsOrt?.evaNr ?? "",
          arrival: a.ankunftsDatum ?? "", arrivalPlatform: a.halte?.last?.gleis,
          load: load(a.auslastungsInfos))
    }
    return Journey(duration: v.reiseDauer, transfers: v.umstiegeAnzahl,
                   departure: legs.first?.departure ?? "", arrival: legs.last?.arrival ?? "",
                   load: load(v.auslastungsInfos), price: w.angebote?.preise?.gesamt?.ab?.betrag,
                   legs: legs, context: v.kontext)
  }

  private static func load(_ infos: [RawAuslastung]?) -> LoadInfo? {
    guard let i = infos?.first(where: { $0.klasse == "KLASSE_2" }), let text = i.anzeigeTextKurz else { return nil }
    return LoadInfo(level: i.stufe, text: text)
  }

  // MARK: Sitzplatzanzeige (gsd)

  /// Profil „FamilieMitKleinkind“ ist das einzige, das die Plätze im
  /// Kleinkindabteil als wählbar meldet. Liefert nil, wenn es keinen Sitzplan gibt.
  func fetchSeatMap(for leg: Leg) async throws -> [SeatCoach]? {
    let data: [String: Any] = [
      "buchungskontext": [
        "quellSystem": "SIMA",
        "buchungsKontextId": UUID().uuidString.lowercased(),
        "buchungsKontextDaten": [
          "zugnummer": leg.trainNumber,
          "zugfahrtKey": "",
          "abfahrtHalt": ["locationId": leg.fromEva, "abfahrtZeit": ISO8601.naive(leg.departure)],
          "ankunftHalt": ["locationId": leg.toEva, "ankunftZeit": ISO8601.naive(leg.arrival)],
          "inventarsystem": "RIFF",
          "platzbedarfe": [["platzprofilCode": "FamilieMitKleinkind", "anzahl": 1.0, "klasse": "KLASSE_2"]],
        ],
      ],
      "correlationID": correlationId(),
      "lang": "de",
      "theme": "app",
    ]
    let json = String(decoding: try JSONSerialization.data(withJSONObject: data), as: UTF8.self)
    var comps = URLComponents(url: Self.base.appending(path: "gsd/gsd_v3"), resolvingAgainstBaseURL: false)!
    comps.queryItems = [URLQueryItem(name: "data", value: json)]
    var req = URLRequest(url: comps.url!)
    req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

    for attempt in 0..<3 {
      try Task.checkCancellation()
      let (body, res) = try await session.data(for: req)
      guard let http = res as? HTTPURLResponse else { continue }
      if http.statusCode == 409 { return nil }          // kein Sitzplan für diesen Zug
      guard http.statusCode == 200 else { try await backoff(attempt); continue }
      let html = String(decoding: body, as: UTF8.self)
      guard let ssrJSON = Self.extractSSR(html) else { try await backoff(attempt); continue }
      let ssr = try JSONDecoder().decode(RawSeatSSR.self, from: Data(ssrJSON.utf8))
      let coaches = (ssr.zugfahrt?.zugteile ?? []).flatMap { $0.wagen ?? [] }.map { w in
        SeatCoach(number: w.nummer, wagentyp: w.wagentyp,
                  status: Dictionary((w.plaetze ?? []).map { ($0.nummer, $0.status) }, uniquingKeysWith: { a, _ in a }))
      }
      return coaches.isEmpty ? nil : coaches
    }
    throw Failure.noSeatPlan
  }

  private static func extractSSR(_ html: String) -> String? {
    let re = /id='ssr_data'\s*>(.*?)<\/script>/.dotMatchesNewlines()
    return html.firstMatch(of: re).map { String($0.1) }
  }

  func layout(for wagentyp: String) async throws -> CoachLayout? {
    if let cached = await layouts.get(wagentyp) { return cached.value }
    let url = Self.base.appending(path: "gsd/api/wagentypen/\(wagentyp)")
    var req = URLRequest(url: url)
    req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    var layout: CoachLayout?
    for attempt in 0..<3 {
      let (body, res) = try await session.data(for: req)
      let code = (res as? HTTPURLResponse)?.statusCode ?? 0
      if code == 404 { break }
      guard code == 200 else { try await backoff(attempt); continue }
      let raw = try JSONDecoder().decode(RawWagentyp.self, from: body)
      layout = CoachLayout(elements: (raw.wagenteile ?? []).flatMap { $0.elemente ?? [] })
      break
    }
    await layouts.set(wagentyp, layout)
    return layout
  }

  // MARK: Teilen-Link

  func shareLink(for journey: Journey) async -> URL? {
    guard let ctx = journey.context, ctx.contains("¶") else { return nil }
    let body: [String: Any] = ["GH": ctx, "HD": journey.departure,
                               "SO": journey.legs.first?.from ?? "", "ZO": journey.legs.last?.to ?? ""]
    guard let raw: RawShare = try? await post("angebote/verbindung/teilen", media: Self.shareMedia, body: body, retries: 1),
          let vbid = raw.vbid else { return nil }
    return URL(string: "https://www.bahn.de/buchung/start?vbid=\(vbid)")
  }

  // MARK: Transport

  private func post<T: Decodable>(_ path: String, media: String, body: Any, retries: Int = 3) async throws -> T {
    var req = URLRequest(url: Self.base.appending(path: path))
    req.httpMethod = "POST"
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    for (k, v) in ["Accept": media, "Content-Type": media, "Accept-Language": "de",
                   "User-Agent": Self.userAgent, "X-App-Version": "26.9.0",
                   "X-Correlation-ID": correlationId()] {
      req.setValue(v, forHTTPHeaderField: k)
    }
    var last: Failure = .http(0, "")
    for attempt in 0...retries {
      try Task.checkCancellation()
      let (data, res) = try await session.data(for: req)
      let code = (res as? HTTPURLResponse)?.statusCode ?? 0
      if (200..<300).contains(code) { return try JSONDecoder().decode(T.self, from: data) }
      let text = String(decoding: data, as: UTF8.self)
      Self.log.error("POST \(path, privacy: .public) → \(code) \(text.prefix(200), privacy: .public)")
      if text.contains("OPS_BLOCKED") { throw Failure.blocked }
      last = .http(code, text)
      if code == 429 || code >= 500 { try await backoff(attempt); continue }
      throw last
    }
    throw last
  }

  private func backoff(_ attempt: Int) async throws {
    try await Task.sleep(for: .milliseconds(700 * (attempt + 1)))
  }

  private func correlationId() -> String {
    "\(UUID().uuidString.lowercased())_\(UUID().uuidString.lowercased())"
  }
}

/// Wagen-Layouts ändern sich nie: im Speicher und auf Platte gecacht.
actor LayoutCache {
  struct Entry: Codable { let value: CoachLayout? }
  private var entries: [String: Entry] = [:]
  private var loaded = false
  private let file: URL

  init() {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    file = dir.appending(path: "wagentypen.json")
  }

  func get(_ key: String) -> Entry? {
    loadIfNeeded()
    return entries[key]
  }

  func set(_ key: String, _ value: CoachLayout?) {
    loadIfNeeded()
    entries[key] = Entry(value: value)
    if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file, options: .atomic) }
  }

  private func loadIfNeeded() {
    guard !loaded else { return }
    loaded = true
    if let data = try? Data(contentsOf: file), let e = try? JSONDecoder().decode([String: Entry].self, from: data) {
      entries = e
    }
  }
}
