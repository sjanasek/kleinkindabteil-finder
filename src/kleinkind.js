// Erkennung von Kleinkindabteil / Familienbereich im Wagen-Layout und
// Auswertung der Sitzplatzbelegung.
import { fetchSeatMap, fetchLayout, RESERVABLE } from './db.js';

const isFree = (s) => s.status === 1 || s.status === 2;

/**
 * Ermittelt anhand der Layout-Geometrie, welche Sitznummern zum Kleinkindabteil
 * bzw. Familienbereich gehören.
 *  - Kleinkindabteil: Symbol KLEINKINDABTEIL; Bereich zwischen den nächsten
 *    Trennwänden links/rechts (Fallback: Radius um das Symbol).
 *  - Familienbereich: Symbol FAMILIENBEREICH; Plätze im Radius um das Symbol.
 */
export function analyseLayout(layout) {
  const out = { kleinkind: [], familie: [], kinderwagen: false, hasKleinkindSymbol: false, hasFamilieSymbol: false };
  if (!layout) return out;
  const els = layout.elements;
  const seats = els.filter((e) => e.type === 'PLATZ');
  const walls = els.filter((e) => e.type === 'EINBAU' && /^WAND/.test(e.subtype || ''));
  out.kinderwagen = els.some((e) => e.subtype === 'KINDERWAGEN');

  for (const sym of els.filter((e) => e.type === 'SYMBOL' && e.subtype === 'KLEINKINDABTEIL')) {
    out.hasKleinkindSymbol = true;
    const left = walls.filter((w) => w.x <= sym.x).sort((a, b) => b.x - a.x)[0];
    const right = walls.filter((w) => w.x >= sym.x).sort((a, b) => a.x - b.x)[0];
    let lo, hi;
    if (left && right && right.x - left.x <= 24) { lo = left.x; hi = right.x; }
    else { lo = sym.x - 8; hi = sym.x + 8; }
    for (const s of seats) if (s.x >= lo && s.x <= hi) out.kleinkind.push(String(s.nummer));
  }
  for (const sym of els.filter((e) => e.type === 'SYMBOL' && e.subtype === 'FAMILIENBEREICH')) {
    out.hasFamilieSymbol = true;
    for (const s of seats) {
      const n = String(s.nummer);
      if (Math.abs(s.x - sym.x) <= 12 && !out.kleinkind.includes(n) && !out.familie.includes(n)) out.familie.push(n);
    }
  }
  return out;
}

/**
 * Prüft einen Fernverkehrs-Abschnitt. Liefert null, wenn kein Sitzplan
 * verfügbar ist, sonst:
 * { coaches:[{number, kleinkind:{seats:[{number,free}], free, total}, familie:{...}, kinderwagen}],
 *   kleinkindFree, kleinkindTotal, familieFree, familieTotal }
 */
export async function checkLeg(leg, opts = {}) {
  if (!RESERVABLE.has(leg.product)) return { skipped: true };
  const coaches = await fetchSeatMap({
    trainNumber: leg.trainNumber,
    fromEva: leg.fromEva,
    departure: leg.departure,
    toEva: leg.toEva,
    arrival: leg.arrival,
    firstClass: opts.firstClass,
  });
  if (!coaches) return null;
  // kleinkindBest: meiste freie Plätze in EINEM Abteil (Familie sitzt zusammen)
  const result = { coaches: [], kleinkindFree: 0, kleinkindBest: 0, kleinkindTotal: 0, familieFree: 0, familieTotal: 0, kinderwagen: [] };
  for (const c of coaches) {
    const layout = await fetchLayout(c.wagentyp);
    const zones = analyseLayout(layout);
    if (!zones.hasKleinkindSymbol && !zones.hasFamilieSymbol && !zones.kinderwagen) continue;
    const byNr = new Map(c.seats.map((s) => [s.number, s]));
    const zone = (nrs) => {
      const seats = nrs.map((n) => ({ number: n, free: byNr.has(n) ? isFree(byNr.get(n)) : false }));
      return { seats, free: seats.filter((s) => s.free).length, total: seats.length };
    };
    const entry = { number: c.number, kleinkind: zone(zones.kleinkind), familie: zone(zones.familie), kinderwagen: zones.kinderwagen };
    result.coaches.push(entry);
    result.kleinkindFree += entry.kleinkind.free;
    result.kleinkindBest = Math.max(result.kleinkindBest, entry.kleinkind.free);
    result.kleinkindTotal += entry.kleinkind.total;
    result.familieFree += entry.familie.free;
    result.familieTotal += entry.familie.total;
    if (zones.kinderwagen) result.kinderwagen.push(c.number);
  }
  return result;
}
