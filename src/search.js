// Orchestrierung: Verbindungen suchen, Fernverkehrs-Abschnitte auf freies
// Kleinkindabteil prüfen, filtern.
import { searchLocations, searchJourneys, shareJourney, RESERVABLE } from './db.js';

const REGIONAL = new Set(['REGIONAL', 'SBAHN', 'BUS', 'SCHIFF', 'UBAHN', 'TRAM', 'ANRUFPFLICHTIG', 'RE', 'RB', 'IRE', 'S']);
import { checkLeg } from './kleinkind.js';

export function buildTravellers({ adults = 1, childAges = [] }) {
  const list = [];
  for (let i = 0; i < adults; i++) list.push({ typ: 'ERWACHSENER' });
  for (const age of childAges) {
    if (age <= 5) list.push({ typ: 'KLEINKIND', alter: age });
    else list.push({ typ: 'FAMILIENKIND', alter: age });
  }
  return list;
}

export async function resolveStation(term) {
  const hits = await searchLocations(term);
  if (!hits.length) throw new Error(`Keine Haltestelle gefunden für "${term}"`);
  const norm = (x) => x.toLowerCase().replace(/\s+/g, ' ').trim();
  return hits.find((h) => norm(h.name) === norm(term)) || hits[0];
}

/**
 * opts: { from, to, dateTime, adults, childAges, minFree, pages, maxTransfers,
 *         mode:'all'|'any', onProgress(event) }
 * Liefert Verbindungen mit `checks` (pro Fernverkehrs-Leg) und `ok`.
 */
export async function searchFamilyFriendly(opts) {
  const progress = opts.onProgress || (() => {});
  const [from, to] = await Promise.all([resolveStation(opts.from), resolveStation(opts.to)]);
  progress({ type: 'stations', from, to });

  const reisende = buildTravellers(opts);
  let context;
  const journeys = [];
  const seen = new Set();
  // Ganzer Tag: ab 0:00 Uhr so lange weiterblättern, bis die Abfahrten am Folgetag liegen.
  const dayKey = (iso) => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Berlin', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(iso));
  const wantedDay = dayKey(opts.dateTime);
  const maxPages = opts.wholeDay ? 40 : (opts.pages || 1);
  for (let p = 0; p < maxPages; p++) {
    const r = await searchJourneys({
      fromLocationId: from.locationId,
      toLocationId: to.locationId,
      dateTime: opts.dateTime,
      reisende,
      context,
      maxTransfers: opts.maxTransfers,
    });
    let beyondDay = false;
    for (const j of r.journeys) {
      if (!j.departure) continue;
      if (opts.wholeDay && dayKey(j.departure) !== wantedDay) { beyondDay = true; continue; }
      const key = j.legs.map((l) => `${l.name}@${l.departure}`).join('|');
      if (!seen.has(key)) { seen.add(key); journeys.push(j); }
    }
    context = r.later;
    if (!context || beyondDay || !r.journeys.length) break;
    progress({ type: 'page', page: p + 1, count: journeys.length });
  }
  progress({ type: 'journeys', count: journeys.length });

  // Jeder Reisende (Erwachsene und Kinder) braucht einen Platz, und zwar zusammen in einem Kleinkindabteil.
  const travellers = (opts.adults || 1) + (opts.childAges || []).length;
  const minFree = opts.minFree ?? travellers;
  progress({ type: 'need', minFree });
  const limit = pLimit(2);
  await Promise.all(journeys.map((j, idx) => limit(async () => {
    j.checks = [];
    for (const leg of j.legs) {
      let check;
      try { check = await checkLeg(leg); }
      catch (e) { check = { error: e.message }; }
      j.checks.push(check);
    }
    const relevant = j.checks.filter((c) => c && !c.skipped);
    const okLegs = relevant.filter((c) => c.kleinkindBest >= minFree);
    // Fernverkehr ohne DB-Sitzplan (z. B. FlixTrain, Nachtzug) gilt als „nicht prüfbar", nicht als „voll".
    const foreign = j.legs.filter((l) => !RESERVABLE.has(l.product) && !REGIONAL.has(l.product)).length;
    j.hasLongDistance = relevant.length > 0 || j.checks.some((c) => c === null) || foreign > 0;
    j.unknown = j.checks.filter((c) => c === null || c?.error).length + foreign;
    if (!relevant.length) j.ok = false;
    else if (opts.mode === 'any') j.ok = okLegs.length > 0 && j.unknown === 0;
    else j.ok = okLegs.length === relevant.length && j.unknown === 0;
    if (j.ok) j.link = await shareJourney(j); // Direktlink zur Buchung auf bahn.de
    progress({ type: 'checked', index: idx, journey: j });
  })));

  journeys.sort((a, b) => (b.ok - a.ok) || new Date(a.departure) - new Date(b.departure));
  const shown = opts.showAll ? journeys : journeys.filter((j) => j.ok);
  return { from, to, journeys: shown, total: journeys.length, minFree };
}

function pLimit(n) {
  let active = 0; const queue = [];
  const next = () => { active--; if (queue.length) queue.shift()(); };
  return (fn) => new Promise((resolve, reject) => {
    const run = () => { active++; fn().then(resolve, reject).finally(next); };
    if (active < n) run(); else queue.push(run);
  });
}
