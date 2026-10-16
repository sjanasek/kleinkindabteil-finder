import Testing
@testable import KleinkindabteilFinder

/// Layout von Wagen 9 eines ICE 4 (12-teilig), reduziert auf die relevanten Elemente.
private let ice4Coach9 = CoachLayout(elements: [
  .init(x: 14, y: 10, type: "SYMBOL", subtype: "FAMILIENBEREICH", nummer: nil),
  .init(x: 2, y: 2, type: "SYMBOL", subtype: "KINDERWAGEN", nummer: nil),
  .init(x: 74, y: 6, type: "EINBAU", subtype: "WAND_L_GROSS_RECHTS", nummer: nil),
  .init(x: 78, y: 10, type: "SYMBOL", subtype: "KLEINKINDABTEIL", nummer: nil),
  .init(x: 86, y: 6, type: "EINBAU", subtype: "WAND_L_GROSS_LINKS", nummer: nil),
  .init(x: 6, y: 2, type: "PLATZ", subtype: nil, nummer: "78"),
  .init(x: 14, y: 2, type: "PLATZ", subtype: nil, nummer: "74"),
  .init(x: 26, y: 2, type: "PLATZ", subtype: nil, nummer: "64"),
  .init(x: 62, y: 2, type: "PLATZ", subtype: nil, nummer: "24"),
  .init(x: 74, y: 2, type: "PLATZ", subtype: nil, nummer: "16"),
  .init(x: 74, y: 6, type: "PLATZ", subtype: nil, nummer: "15"),
  .init(x: 74, y: 10, type: "PLATZ", subtype: nil, nummer: "14"),
  .init(x: 82, y: 2, type: "PLATZ", subtype: nil, nummer: "12"),
  .init(x: 82, y: 6, type: "PLATZ", subtype: nil, nummer: "11"),
])

@Suite struct SeatAnalysisTests {
  @Test func `Kleinkindabteil liegt zwischen den Trennwänden`() {
    let z = SeatAnalysis.zones(in: ice4Coach9)
    #expect(Set(z.kleinkind) == ["16", "15", "14", "12", "11"])
    #expect(z.kinderwagen)
  }

  @Test func `Familienbereich um das Symbol, ohne Abteilplätze`() {
    let z = SeatAnalysis.zones(in: ice4Coach9)
    #expect(Set(z.familie) == ["78", "74", "64"])
    #expect(!z.familie.contains("24"))
  }

  @Test func `Status 1 und 2 sind frei, 0 ist belegt`() {
    let coach = SeatCoach(number: "9", wagentyp: "I6412", status: ["16": 0, "15": 1, "14": 2, "12": 0, "11": 0])
    let r = SeatAnalysis.report(coaches: [coach], layouts: ["I6412": ice4Coach9])
    #expect(r.kleinkindBest == 2)
    #expect(r.coaches.first?.kleinkind.freeNumbers.sorted() == ["14", "15"])
  }

  @Test func `Verbindung passt nur, wenn ein Abteil alle Plätze hat`() {
    let coach25 = SeatCoach(number: "25", wagentyp: "I6412", status: ["16": 1, "15": 0, "14": 0, "12": 0, "11": 0])
    let coach35 = SeatCoach(number: "35", wagentyp: "I6412", status: ["16": 1, "15": 0, "14": 0, "12": 0, "11": 0])
    let report = SeatAnalysis.report(coaches: [coach25, coach35], layouts: ["I6412": ice4Coach9])
    let leg = Leg(name: "ICE 1601", product: "ICE", trainNumber: "1601", from: "A", fromEva: "1", departure: "2026-11-10T08:00:00+01:00",
                  departurePlatform: nil, to: "B", toEva: "2", arrival: "2026-11-10T12:00:00+01:00", arrivalPlatform: nil, load: nil)
    let journey = Journey(duration: 0, transfers: 0, departure: leg.departure, arrival: leg.arrival, load: nil, price: nil, legs: [leg], context: nil)
    let two = CheckedJourney(journey: journey, checks: [.checked(report)], seatsNeeded: 2, requireAll: true)
    let one = CheckedJourney(journey: journey, checks: [.checked(report)], seatsNeeded: 1, requireAll: true)
    #expect(!two.ok)   // je ein Platz in zwei Wagen reicht nicht
    #expect(one.ok)
  }

  @Test func `naive Zeit ohne Offset`() {
    #expect(ISO8601.naive("2026-10-20T08:29:00+02:00") == "2026-10-20T08:29:00")
  }
}
