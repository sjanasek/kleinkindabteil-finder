import Foundation
import Observation

/// Sucheingaben, Suche und Ergebnisse. Lebt auf dem Main Actor; die Netzwerk-
/// arbeit läuft über `async` (URLSession lagert selbst aus).
@Observable
final class SearchModel {
  enum Phase: Equatable {
    case idle
    case resolving
    case loading(page: Int, found: Int)
    case checking(done: Int, total: Int)
    case done
    case failed(String)
  }

  // Eingaben
  var from = ""
  var to = ""
  var date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
  var wholeDay = true
  var time = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
  var adults = 1
  var childAges = "2"
  var maxTransfers: Int? = nil
  var requireAll = true
  var showAll = false

  // Ergebnis
  private(set) var phase: Phase = .idle
  private(set) var results: [CheckedJourney] = []
  private(set) var total = 0
  private(set) var seatsNeeded = 0
  private(set) var fromStation: Station?
  private(set) var toStation: Station?

  private let client = DBClient()
  private var task: Task<Void, Never>?

  var ages: [Int] { childAges.split(whereSeparator: { ",; ".contains($0) }).compactMap { Int($0) } }
  var visibleResults: [CheckedJourney] { showAll ? results : results.filter(\.ok) }
  var isRunning: Bool {
    switch phase { case .resolving, .loading, .checking: true; default: false }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }

  func search() {
    cancel()
    results = []
    total = 0
    seatsNeeded = max(1, adults) + ages.count
    phase = .resolving
    task = Task { await run() }
  }

  private func run() async {
    do {
      async let f = client.resolveStation(from)
      async let t = client.resolveStation(to)
      guard let fromStation = try await f, let toStation = try await t else {
        phase = .failed("Haltestelle nicht gefunden.")
        return
      }
      self.fromStation = fromStation
      self.toStation = toStation

      let journeys = try await loadJourneys(from: fromStation, to: toStation)
      total = journeys.count
      phase = .checking(done: 0, total: journeys.count)

      // Begrenzt parallel (2), damit das Backend nicht drosselt.
      var done = 0
      let need = seatsNeeded, all = requireAll, client = client
      try await withThrowingTaskGroup(of: CheckedJourney.self) { group in
        var iterator = journeys.makeIterator()
        func addNext() -> Bool {
          guard let j = iterator.next() else { return false }
          group.addTask { await Self.check(j, need: need, requireAll: all, client: client) }
          return true
        }
        for _ in 0..<2 { _ = addNext() }
        for try await checked in group {
          try Task.checkCancellation()
          done += 1
          results.append(checked)
          results.sort { ($0.ok ? 0 : 1, $0.journey.departure) < ($1.ok ? 0 : 1, $1.journey.departure) }
          phase = .checking(done: done, total: journeys.count)
          _ = addNext()
        }
      }
      phase = .done
    } catch is CancellationError {
      phase = .idle
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  private func loadJourneys(from: Station, to: Station) async throws -> [Journey] {
    let travellers = DBClient.travellers(adults: adults, childAges: ages)
    let start = startDate()
    let wantedDay = ISO8601.dayKey(start)
    var context: String?
    var seen = Set<String>()
    var journeys: [Journey] = []
    let maxPages = wholeDay ? 40 : 1
    for page in 0..<maxPages {
      try Task.checkCancellation()
      phase = .loading(page: page + 1, found: journeys.count)
      let (batch, later) = try await client.searchJourneys(from: from, to: to, departure: start, travellers: travellers,
                                                           maxTransfers: maxTransfers, context: context)
      var beyondDay = false
      for j in batch where !j.departure.isEmpty {
        if wholeDay, ISO8601.dayKey(j.departure) != wantedDay { beyondDay = true; continue }
        if seen.insert(j.id).inserted { journeys.append(j) }
      }
      context = later
      if later == nil || beyondDay || batch.isEmpty { break }
    }
    return journeys
  }

  private func startDate() -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let day = cal.dateComponents([.year, .month, .day], from: date)
    let clock = wholeDay ? DateComponents(hour: 0, minute: 0) : Calendar.current.dateComponents([.hour, .minute], from: time)
    var c = day
    c.hour = clock.hour
    c.minute = clock.minute
    return cal.date(from: c) ?? date
  }

  nonisolated private static func check(_ journey: Journey, need: Int, requireAll: Bool, client: DBClient) async -> CheckedJourney {
    var checks: [LegCheck] = []
    for leg in journey.legs { checks.append(await client.check(leg)) }
    var result = CheckedJourney(journey: journey, checks: checks, seatsNeeded: need, requireAll: requireAll)
    if result.ok { result.link = await client.shareLink(for: journey) }
    return result
  }
}
