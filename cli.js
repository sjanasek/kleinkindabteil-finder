#!/usr/bin/env node
// Nutzung: node cli.js "Berlin Hbf" "München Hbf" 2026-11-10 08:00 [--kids 2,4] [--adults 2] [--min-free 2] [--pages 2] [--max-transfers 1] [--any] [--json]
import { searchFamilyFriendly } from './src/search.js';

const args = process.argv.slice(2);
const pos = []; const flags = {};
for (let i = 0; i < args.length; i++) {
  if (args[i].startsWith('--')) {
    const k = args[i].slice(2);
    if (k === 'any' || k === 'json' || k === 'all' || k === 'day') flags[k] = true; else flags[k] = args[++i];
  } else pos.push(args[i]);
}
if (pos.length < 3) {
  console.error('Nutzung: bahn-kleinkind <von> <nach> <YYYY-MM-DD> [HH:MM] [--kids 2,4] [--adults 2] [--day | --pages n] [--max-transfers n] [--any] [--all] [--min-free n] [--json]');
  process.exit(1);
}
const [from, to, date, time = '08:00'] = pos;
const dateTime = new Date(`${date}T${flags.day ? '00:00' : time}:00${tzOffset(date)}`);

const result = await searchFamilyFriendly({
  from, to, dateTime,
  adults: Number(flags.adults || 1),
  childAges: (flags.kids || '2').split(',').map(Number),
  minFree: flags['min-free'] != null ? Number(flags['min-free']) : undefined,
  showAll: Boolean(flags.all),
  pages: Number(flags.pages || 1),
  wholeDay: Boolean(flags.day),
  maxTransfers: flags['max-transfers'] != null ? Number(flags['max-transfers']) : undefined,
  mode: flags.any ? 'any' : 'all',
  onProgress: (e) => {
    if (flags.json) return;
    if (e.type === 'stations') console.error(`${e.from.name} → ${e.to.name}`);
    if (e.type === 'page') console.error(`  … Zeitfenster ${e.page} geladen (${e.count} Verbindungen bisher)`);
    if (e.type === 'journeys') console.error(`${e.count} Verbindungen gefunden, prüfe Kleinkindabteile …`);
    if (e.type === 'need') console.error(`Gesucht: ${e.minFree} freie Plätze im Kleinkindabteil je Zug`);
  },
});

if (flags.json) { console.log(JSON.stringify(result, null, 2)); process.exit(0); }

const hhmm = (iso) => new Date(iso).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Berlin' });
console.log('');
if (!result.journeys.length) console.log(`Keine der ${result.total} Verbindungen hat ${result.minFree} freie Plätze im Kleinkindabteil. (--all zeigt trotzdem alle, --pages 2 sucht später am Tag.)`);
for (const j of result.journeys) {
  const mark = j.ok ? '✅' : (j.unknown ? '❓' : '❌');
  const dur = `${Math.floor(j.duration / 3600)}h${String(Math.floor((j.duration % 3600) / 60)).padStart(2, '0')}`;
  console.log(`${mark} ${hhmm(j.departure)} → ${hhmm(j.arrival)}  ${dur}, ${j.transfers} Umstieg(e)${j.price != null ? `, ab ${j.price.toFixed(2)} €` : ''}`);
  if (j.link) console.log(`     \u{1F517} ${j.link}`);
  j.legs.forEach((leg, i) => {
    const c = j.checks[i];
    let info;
    if (c?.skipped) info = ['ICE','IC','EC','ECE'].includes(leg.product) ? 'keine Prüfung' : (/^(FLX|NJ|RJ|TGV|EN|D)$/.test(leg.product) ? 'kein DB-Reservierungssystem, nicht prüfbar' : 'Nahverkehr, keine Reservierung (Mehrzweckbereich nutzen)');
    else if (c === null) info = 'kein Sitzplan abrufbar';
    else if (c?.error) info = `Fehler: ${c.error}`;
    else {
      const parts = [];
      for (const w of c.coaches) {
        if (w.kleinkind.total) parts.push(`Wagen ${w.number}: Kleinkindabteil ${w.kleinkind.free}/${w.kleinkind.total} frei${w.kleinkind.free ? ` (Platz ${w.kleinkind.seats.filter((s) => s.free).map((s) => s.number).join(', ')})` : ''}`);
        if (w.familie.total) parts.push(`Wagen ${w.number}: Familienbereich ${w.familie.free}/${w.familie.total} frei`);
      }
      if (!parts.length) parts.push('kein Kleinkindabteil in diesem Zug');
      if (c.kinderwagen.length) parts.push(`Kinderwagen: Wagen ${c.kinderwagen.join(', ')}`);
      info = parts.join(' · ');
    }
    console.log(`     ${leg.name.padEnd(9)} ${hhmm(leg.departure)} ${leg.from} (Gl. ${leg.departurePlatform || '?'}) → ${hhmm(leg.arrival)} ${leg.to}${leg.load ? `  [${leg.load.text}]` : ''}`);
    console.log(`               ${info}`);
  });
  console.log('');
}

function tzOffset(date) {
  const d = new Date(`${date}T12:00:00Z`);
  const s = new Intl.DateTimeFormat('en-US', { timeZone: 'Europe/Berlin', timeZoneName: 'longOffset' }).formatToParts(d).find((p) => p.type === 'timeZoneName').value;
  return s.replace('GMT', '') || '+00:00';
}
