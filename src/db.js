// Zugriff auf das (inoffizielle) Backend des DB Navigators.
// Endpunkte und Medientypen wurden aus dem Verhalten der App abgeleitet.
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { request } from './http.js';

const BASE = 'https://app.services-bahn.de/mob';
const UA = 'DBNavigator/Android/26.9.0';
const MEDIA = {
  journeys: 'application/x.db.vendo.mob.verbindungssuche.v9+json',
  location: 'application/x.db.vendo.mob.location.v3+json',
  share: 'application/x.db.vendo.mob.verbindungteilen.v1+json',
};

const corr = () => `${randomUUID()}_${randomUUID()}`;

function headers(media) {
  return {
    Accept: media,
    'Content-Type': media,
    'Accept-Language': 'de',
    'User-Agent': UA,
    'X-App-Version': '26.9.0',
    'X-Correlation-ID': corr(),
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function postJson(url, media, body, { retries = 3 } = {}) {
  let lastErr;
  for (let i = 0; i <= retries; i++) {
    const res = await request(url, { method: 'POST', headers: headers(media), body: JSON.stringify(body) });
    if (res.ok) return JSON.parse(res.text);
    const text = res.text;
    lastErr = new Error(`HTTP ${res.status} ${url}: ${text.slice(0, 300)}`);
    if (res.status === 429 || res.status >= 500) {
      await sleep(800 * (i + 1));
      continue;
    }
    throw lastErr;
  }
  throw lastErr;
}

/** Haltestellensuche. Liefert [{name, locationId, evaNr}]. */
export async function searchLocations(term) {
  const list = await postJson(`${BASE}/location/search`, MEDIA.location, {
    locationTypes: ['ALL'],
    searchTerm: term,
  });
  return list
    .filter((l) => l.locationType === 'ST')
    .map((l) => ({ name: l.name, locationId: l.locationId, evaNr: l.evaNr }));
}

/**
 * Verbindungssuche mit Reisendenprofil.
 * reisende: [{typ:'ERWACHSENER'|'KLEINKIND'|'FAMILIENKIND', alter?:number}]
 */
export async function searchJourneys({
  fromLocationId,
  toLocationId,
  dateTime,
  isArrival = false,
  reisende,
  firstClass = false,
  context,
  maxTransfers,
}) {
  const body = {
    autonomeReservierung: false,
    einstiegsTypList: ['STANDARD'],
    fahrverguenstigungen: {
      deutschlandTicketVorhanden: false,
      nurDeutschlandTicketVerbindungen: false,
    },
    klasse: firstClass ? 'KLASSE_1' : 'KLASSE_2',
    reiseHin: {
      wunsch: {
        abgangsLocationId: fromLocationId,
        alternativeHalteBerechnung: true,
        verkehrsmittel: ['ALL'],
        zeitWunsch: {
          reiseDatum: isoWithOffset(dateTime),
          zeitPunktArt: isArrival ? 'ANKUNFT' : 'ABFAHRT',
        },
        zielLocationId: toLocationId,
        ...(maxTransfers != null ? { maxUmstiege: maxTransfers } : {}),
        ...(context ? { context } : {}),
      },
    },
    reisendenProfil: {
      reisende: reisende.map((r) => ({
        ermaessigungen: ['KEINE_ERMAESSIGUNG KLASSENLOS'],
        reisendenTyp: r.typ,
        ...(r.alter != null ? { alter: r.alter } : {}),
      })),
    },
    reservierungsKontingenteVorhanden: false,
  };
  const data = await postJson(`${BASE}/angebote/fahrplan`, MEDIA.journeys, body);
  return {
    journeys: (data.verbindungen || []).map(parseConnection),
    earlier: data.frueherContext,
    later: data.spaeterContext,
  };
}

function parseConnection(c) {
  const v = c.verbindung;
  const legs = (v.verbindungsAbschnitte || [])
    .filter((a) => a.typ === 'FAHRZEUG')
    .map((a) => ({
      name: a.mitteltext,
      product: a.produktGattung,
      trainNumber: String(a.zugNummer || a.verkehrsmittelNummer || ''),
      from: a.abgangsOrt?.name,
      fromEva: a.abgangsOrt?.evaNr,
      departure: a.abgangsDatum,
      departurePlatform: a.halte?.[0]?.gleis,
      to: a.ankunftsOrt?.name,
      toEva: a.ankunftsOrt?.evaNr,
      arrival: a.ankunftsDatum,
      arrivalPlatform: a.halte?.at(-1)?.gleis,
      direction: a.richtung,
      load: loadLevel(a.auslastungsInfos),
      notes: (a.attributNotizen || []).map((n) => n.text),
    }));
  const price = c.angebote?.preise?.gesamt?.ab?.betrag ?? null;
  return {
    duration: v.reiseDauer,
    transfers: v.umstiegeAnzahl,
    departure: legs[0]?.departure,
    arrival: legs.at(-1)?.arrival,
    load: loadLevel(v.auslastungsInfos),
    price,
    legs,
    ctx: v.kontext,
  };
}

/**
 * "Verbindung teilen": Backend erzeugt eine vbid, die auf bahn.de direkt die
 * Verbindung oeffnet (Buchung/Sitzplatzwahl). Braucht den HAFAS-Kontext.
 */
export async function shareJourney(journey) {
  if (!journey.ctx || !journey.ctx.includes('\u00b6')) return null;
  const body = { GH: journey.ctx, HD: journey.departure, SO: journey.legs[0]?.from || '', ZO: journey.legs.at(-1)?.to || '' };
  try {
    const data = await postJson(`${BASE}/angebote/verbindung/teilen`, MEDIA.share, body, { retries: 1 });
    return data?.vbid ? `https://www.bahn.de/buchung/start?vbid=${data.vbid}` : null;
  } catch {
    return null;
  }
}

function loadLevel(infos, klasse = 'KLASSE_2') {
  const i = (infos || []).find((x) => x.klasse === klasse);
  return i ? { level: i.stufe, text: i.anzeigeTextKurz } : null;
}

export function isoWithOffset(d) {
  // lokale Zeit (Europe/Berlin) mit Offset, wie die App sie sendet
  const fmt = new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Europe/Berlin',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
    timeZoneName: 'longOffset',
  });
  const parts = Object.fromEntries(fmt.formatToParts(d).map((p) => [p.type, p.value]));
  const off = parts.timeZoneName.replace('GMT', '') || '+00:00';
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:${parts.second}${off}`;
}

// ---------------------------------------------------------------------------
// Grafische Sitzplatzanzeige (gsd). Nicht hinter Login; Status ist pro Zug,
// Ein-/Ausstieg und Planzeit. Profilcode "FamilieMitKleinkind" schaltet die
// Plätze im Kleinkindabteil frei, "StandardEinzelperson" meldet sie als belegt.
// ---------------------------------------------------------------------------
const GSD = `${BASE}/gsd`;
export const RESERVABLE = new Set(['ICE', 'IC', 'EC', 'ECE']);

export async function fetchSeatMap({
  trainNumber, fromEva, departure, toEva, arrival,
  profile = 'FamilieMitKleinkind', firstClass = false, count = 1,
}) {
  const data = {
    buchungskontext: {
      quellSystem: 'SIMA',
      buchungsKontextId: randomUUID(),
      buchungsKontextDaten: {
        zugnummer: trainNumber,
        zugfahrtKey: '',
        abfahrtHalt: { locationId: fromEva, abfahrtZeit: naive(departure) },
        ankunftHalt: { locationId: toEva, ankunftZeit: naive(arrival) },
        inventarsystem: 'RIFF',
        platzbedarfe: [{ platzprofilCode: profile, anzahl: count, klasse: firstClass ? 'KLASSE_1' : 'KLASSE_2' }],
      },
    },
    correlationID: corr(),
    lang: 'de',
    theme: 'app',
  };
  const url = `${GSD}/gsd_v3?data=${encodeURIComponent(JSON.stringify(data))}`;
  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await request(url, { headers: { 'User-Agent': UA } });
    if (res.status === 409) return null; // kein Sitzplan (z. B. Zug nicht reservierbar / falsche Zeiten)
    if (!res.ok) { await sleep(700 * (attempt + 1)); continue; }
    const html = res.text;
    const m = html.match(/id='ssr_data'\s*>(.*?)<\/script>/s);
    if (!m) { await sleep(700 * (attempt + 1)); continue; }
    const ssr = JSON.parse(m[1]);
    const coaches = [];
    for (const teil of ssr.zugfahrt?.zugteile || []) {
      for (const w of teil.wagen || []) {
        coaches.push({
          number: String(w.nummer),
          wagentyp: w.wagentyp,
          seats: (w.plaetze || []).map((p) => ({ number: String(p.nummer), status: p.status })),
        });
      }
    }
    return coaches.length ? coaches : null;
  }
  throw new Error(`Sitzplan für ${trainNumber} nicht abrufbar`);
}

function naive(iso) {
  return String(iso).replace(/([+-]\d\d:\d\d|Z)$/, '').split('.')[0];
}

// Wagen-Layouts (Geometrie) mit Disk-Cache: der Typ ändert sich nie.
const cacheDir = path.join(os.homedir(), '.cache', 'bahn-kleinkind');
const cacheFile = path.join(cacheDir, 'wagentypen.json');
let layoutCache = null;
function loadCache() {
  if (layoutCache) return layoutCache;
  try { layoutCache = JSON.parse(fs.readFileSync(cacheFile, 'utf8')); }
  catch { layoutCache = {}; }
  return layoutCache;
}
function saveCache() {
  try { fs.mkdirSync(cacheDir, { recursive: true }); fs.writeFileSync(cacheFile, JSON.stringify(layoutCache)); } catch {}
}

export async function fetchLayout(wagentyp) {
  const cache = loadCache();
  if (wagentyp in cache) return cache[wagentyp];
  const url = `${GSD}/api/wagentypen/${encodeURIComponent(wagentyp)}`;
  let layout = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await request(url, { headers: { 'User-Agent': UA }, timeout: 15 });
    if (res.status === 404) break;
    if (!res.ok) { await sleep(500 * (attempt + 1)); continue; }
    const j = JSON.parse(res.text);
    const elements = [];
    for (const t of j.wagenteile || []) for (const e of t.elemente || []) elements.push(e);
    layout = { id: j.id, elements };
    break;
  }
  cache[wagentyp] = layout;
  saveCache();
  return layout;
}
