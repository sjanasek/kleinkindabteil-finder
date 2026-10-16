#!/usr/bin/env node
// Lokale Web-Oberfläche: http://localhost:3456
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { searchFamilyFriendly } from './src/search.js';
import { searchLocations } from './src/db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 3456);

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  try {
    if (url.pathname === '/') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(fs.readFileSync(path.join(__dirname, 'public', 'index.html')));
    }
    if (url.pathname === '/api/stations') {
      const hits = await searchLocations(url.searchParams.get('q') || '');
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify(hits.slice(0, 8)));
    }
    if (url.pathname === '/api/search') {
      // NDJSON-Stream: Ereignisse erscheinen, sobald eine Verbindung geprüft ist.
      res.writeHead(200, { 'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-cache' });
      const send = (o) => res.write(JSON.stringify(o) + '\n');
      const q = url.searchParams;
      const date = q.get('date'); const wholeDay = q.get('pages') === 'day'; const time = wholeDay ? '00:00' : (q.get('time') || '08:00');
      const dateTime = new Date(`${date}T${time}:00${tzOffset(date)}`);
      const result = await searchFamilyFriendly({
        from: q.get('from'), to: q.get('to'), dateTime,
        adults: Number(q.get('adults') || 1),
        childAges: (q.get('kids') || '').split(',').filter(Boolean).map(Number),
        minFree: q.get('minFree') ? Number(q.get('minFree')) : undefined,
        showAll: q.get('showAll') === '1',
        pages: wholeDay ? 1 : Number(q.get('pages') || 1),
        wholeDay,
        maxTransfers: q.get('maxTransfers') ? Number(q.get('maxTransfers')) : undefined,
        mode: q.get('mode') === 'any' ? 'any' : 'all',
        onProgress: send,
      });
      send({ type: 'done', journeys: result.journeys, total: result.total, minFree: result.minFree, from: result.from, to: result.to });
      return res.end();
    }
    res.writeHead(404); res.end('not found');
  } catch (e) {
    if (!res.headersSent) res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ type: 'error', message: e.message }) + '\n');
  }
});

server.listen(PORT, '127.0.0.1', () => console.log(`Kleinkindabteil-Finder läuft: http://localhost:${PORT}`));

function tzOffset(date) {
  const d = new Date(`${date}T12:00:00Z`);
  const s = new Intl.DateTimeFormat('en-US', { timeZone: 'Europe/Berlin', timeZoneName: 'longOffset' }).formatToParts(d).find((p) => p.type === 'timeZoneName').value;
  return s.replace('GMT', '') || '+00:00';
}
