# 🚆👶 Kleinkindabteil-Finder

Mit kleinen Kindern Bahn fahren heißt: Kleinkindabteil oder Stress. Ob dort noch Platz ist, verrät der DB Navigator aber erst, wenn man jede Verbindung einzeln anklickt und bis zur Sitzplatzwahl durchgeht.

Dieses Tool nimmt dir das ab. Du gibst Start, Ziel, Datum und Reisende an, und es prüft für jeden ICE/IC des Tages die Sitzplatzanzeige. Angezeigt werden nur Verbindungen, in denen ein einzelnes Kleinkindabteil genug freie Plätze für alle Erwachsenen und Kinder hat, mit Wagen, Platznummern, Familienbereich als Ausweichoption, Kinderwagen-Stellplatz, Preis und einem Direktlink zur Buchung auf bahn.de.

- 🌐 **Web-Oberfläche** auf `localhost:3456` oder ⌨️ **Kommandozeile**
- 🗓️ **Ganzer Tag** auf einmal, oder ab einer Uhrzeit
- 👨‍👩‍👧 Plätze müssen **zusammen in einem Abteil** frei sein
- 🔗 **Buchungslink** öffnet genau diese Verbindung auf bahn.de
- 📦 Kein Login, keine npm-Abhängigkeiten, nur Node ≥ 20 und curl

> Inoffiziell: nutzt das Backend des DB Navigators lesend. Momentaufnahme ohne Gewähr, ob ein Platz wirklich buchbar ist, entscheidet die Buchung.

## Start

Voraussetzungen: Node ≥ 20 und `curl` (auf macOS vorhanden). Keine npm-Abhängigkeiten.

```sh
git clone https://github.com/sjanasek/kleinkindabteil-finder.git
cd kleinkindabteil-finder

# Web-Oberfläche (http://localhost:3456)
npm start

# Kommandozeile
node cli.js "Berlin Hbf" "München Hbf" 2026-11-10 08:00 --kids 2
node cli.js "Hamburg Hbf" "Köln Hbf" 2026-11-12 09:00 --adults 2 --kids 1,4 --min-free 2 --max-transfers 0
node cli.js "Berlin Hbf" "München Hbf" 2026-11-10 --day --adults 2 --kids 1,3
node cli.js "Berlin Hbf" "München Hbf" 2026-11-10 08:00 --pages 3 --any --json
```

Optionen (CLI und Web):

| Option | Bedeutung |
|---|---|
| `--kids 1,4` | Alter der Kinder (0–5 = Kleinkind, 6–14 = Kind), beeinflusst Preise |
| `--adults 2` | Anzahl Erwachsene |
| `--all` | auch volle / nicht prüfbare Verbindungen zeigen (Standard: nur passende) |
| `--min-free 2` | Mindestzahl freier Plätze überschreiben (Standard: Erwachsene + Kinder) |
| `--day` | ganzen Tag durchsuchen (Uhrzeit wird ignoriert) |
| `--pages 2` | sonst: weitere Zeitfenster nach hinten laden |
| `--max-transfers 0` | Direktverbindungen |
| `--any` | reicht, wenn *ein* Fernverkehrszug der Verbindung frei hat (Standard: alle) |
| `--json` | Rohdaten ausgeben |

Jede passende Verbindung bekommt einen Direktlink (`bahn.de/buchung/start?vbid=…`,
erzeugt wie „Verbindung teilen“ in der App), der die Verbindung auf bahn.de zur
Buchung und Sitzplatzwahl öffnet.

Ausgabe pro Verbindung: ✅ Kleinkindabteil frei · ❌ voll · ❓ nicht prüfbar
(z. B. FlixTrain, kein Sitzplan). Pro Zug: Wagen, freie Plätze mit Platznummern,
Familienbereich, Kinderwagen-Stellplatz, erwartete Auslastung.

## Wie es funktioniert

1. `location/search` → Haltestellen-IDs.
2. `angebote/fahrplan` mit Reisendenprofil (Erwachsene + Kleinkinder) → Verbindungen inkl. Preis ab.
3. Für jeden ICE/IC/EC-Abschnitt die grafische Sitzplatzanzeige `gsd/gsd_v3`
   mit `platzprofilCode: "FamilieMitKleinkind"`. Nur dieses Profil meldet die
   Plätze des Kleinkindabteils als wählbar; mit `StandardEinzelperson` erscheinen
   sie immer als belegt.
4. `gsd/api/wagentypen/{typ}` liefert die Wagen-Geometrie (lokal gecacht in
   `~/.cache/bahn-kleinkind/`). Das Kleinkindabteil sind die Plätze zwischen den
   Trennwänden um das Symbol `KLEINKINDABTEIL`; der Familienbereich die Plätze
   um das Symbol `FAMILIENBEREICH`.
5. Platzstatus 1/2 = frei, 0 = belegt. Eine Verbindung passt, wenn in jedem
   ICE/IC ein einzelnes Kleinkindabteil genug freie Plätze für alle Reisenden hat.

HTTP läuft über das System-`curl`, weil der DB-Edge Node's eigenen TLS-Stack mit
`OPS_BLOCKED` abweist. Bei vielen Anfragen kurz hintereinander kann die DB
drosseln; das Tool prüft darum max. 2 Verbindungen parallel.

## Grenzen

- Nur DB-Fernverkehr mit Reservierungssystem (ICE, IC, EC). Nahverkehr hat kein
  Kleinkindabteil, dort gilt der Mehrzweckbereich.
- Ob ein Platz wirklich buchbar ist, entscheidet erst die Buchung auf bahn.de/Navigator.
- Die Erkennung des Abteils ist geometrisch; bei exotischen Wagentypen können
  Platznummern abweichen. Die Platznummern werden deshalb mit ausgegeben.
