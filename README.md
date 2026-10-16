# 🚆👶 Kleinkindabteil-Finder

Mit kleinen Kindern Bahn fahren heißt: Kleinkindabteil oder Stress. Ob dort noch Platz ist, verrät der DB Navigator aber erst, wenn man jede Verbindung einzeln anklickt und bis zur Sitzplatzwahl durchgeht.

Dieses Tool nimmt dir das ab. Du gibst Start, Ziel, Datum und Reisende an, und es prüft für jeden ICE/IC des Tages die Sitzplatzanzeige. Angezeigt werden nur Verbindungen, in denen ein einzelnes Kleinkindabteil genug freie Plätze für alle Erwachsenen und Kinder hat, mit Wagen, Platznummern, Familienbereich als Ausweichoption, Kinderwagen-Stellplatz, Preis und einem Direktlink zur Buchung auf bahn.de.

- 🌐 **Web-Oberfläche** auf `localhost:3456` oder ⌨️ **Kommandozeile**
- 🗓️ **Ganzer Tag** auf einmal, oder ab einer Uhrzeit
- 👨‍👩‍👧 Plätze müssen **zusammen in einem Abteil** frei sein
- 🔗 **Buchungslink** öffnet genau diese Verbindung auf bahn.de
- 📦 Kein Login, keine npm-Abhängigkeiten, nur Node ≥ 20 und curl

> Inoffiziell: nutzt das Backend des DB Navigators lesend. Momentaufnahme ohne Gewähr, ob ein Platz wirklich buchbar ist, entscheidet die Buchung.
