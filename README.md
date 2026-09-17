# Dijkstra im Schlauch

Interaktive Visualisierung des **Dijkstra-Algorithmus** in einer zufaellig
generierten 3D-Szene:

1. In der x-z-Ebene wird ein **unfoermiges Polygon** mit zufaelligen Ecken erzeugt.
2. Darüber stapeln sich verformte, gedrehte Kopien dieses Polygons zu einem
   **Schlauch**. Die Waende bestehen aus einzelnen **Strichen**
   (Ringsegmente und vertikale Rippen).
3. Der **Dijkstra-Algorithmus** sucht darin den kürzesten Weg von unten nach oben.
   Jeder Schritt wird sichtbar: Knoten leuchten auf, vorläufige Wege färben sich
   nach Distanz ein, der fertige Weg pulsiert gelb.

Alles läuft langsam und nachvollziehbar ab - erst waechst der Schlauch,
dann sucht der Algorithmus, dann wird der gefundene Weg zurückverfolgt.

## Starten

**Wichtig:** Ein direkter Doppelklick auf `index.html` funktioniert in Chrome
**nicht**. Der Browser blockiert ES-Module über `file://` aus Sicherheitsgruenden
und meldet:

```
Access to script at 'file:///...js/main.js' from origin 'null'
has been blocked by CORS policy
```

Dafür gibt es zwei Wege:

### Variante 1: Einzeldatei (kein Server noetig)

`dijkstra-schlauch.html` ist eine fertige Einzeldatei: alle Module und Stile
sind eingebettet, es gibt keine `import`-Anweisungen mehr. Diese Datei läuft
per Doppelklick:

```powershell
start dijkstra-schlauch.html
```

Nach Aenderungen an den Quelldateien neu erzeugen:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build_single_file.ps1
```

### Variante 2: Lokaler Server (arbeitet mit den Einzeldateien)

Der mitgelieferte Server nutzt nur Windows-Bordmittel (kein Node, kein Python):

```powershell
powershell -ExecutionPolicy Bypass -File tools\serve.ps1
```

Der Browser oeffnet sich automatisch unter <http://localhost:8080/>.
Anderer Port bei Bedarf:

```powershell
powershell -ExecutionPolicy Bypass -File tools\serve.ps1 -Port 8081
```

Beenden mit **Strg + C**. Vorteil dieser Variante: du bearbeitest die
einzelnen Dateien in `js/` und laedt im Browser nur neu - kein Build-Schritt.

## Bedienung

| Bedienung | Wirkung |
| --- | --- |
| **Start / Pause** (oder Leertaste) | startet, pausiert und setzt fort; nach dem Ende startet der Knopf einen neuen Durchlauf |
| **Neu suchen** | Aufbau und Suche auf derselben Szene von vorne beginnen |
| **Neue Szene** (oder `R`) | neuer Zufalls-Seed, neue Form und neuer Schlauch |
| **Tempo** | Millisekunden pro abgearbeitetem Knoten (größer = langsamer) |
| **SchlauchHöhe** | Anzahl der Ringe (3 bis 12) |
| **Seed** | reproduzierbare Szene; gleicher Seed = gleiche Form |
| **Distanzwerte** | numerische Distanzen an den Knoten einblenden |
| **Rückseite schwach andeuten** | entfernte Striche mit 16 % Deckkraft zeichnen (3D-Eindruck); ohne Haken sieht man nur die vordere Wand |
| **Knotenpunkte anzeigen** | kleine Verbindungspunkte ein-/ausblenden; ohne Haken bleiben nur die Linien |
| Ziehen mit der Maus | Szene drehen |
| Mausrad | zoomen |
| Maus über Knoten | Tooltip mit Knoten-Id, Ring, Höhe und Distanz |

## Legende der Farben

- **gruen** – Startknoten (unten)
- **rosa** – Zielknoten (oben)
- **blau** – in der Warteschlange (entdeckt, noch nicht abgearbeitet)
- **gelb** – abgearbeitet (Distanz endgültig)
- **weiss blinkend** – gerade abgearbeiteter Knoten
- **Farbskala** der Striche – vorläufig bester Weg, von kurz (gelb) nach lang (violett)
- **pulsierend gelb** – der endgültige kürzeste Weg

## Geometrie

Die Polygone sind absichtlich stark unförmig, damit viele echte Abzweigungen
entstehen:

| Größe | Wert |
| --- | --- |
| Ecken pro Ring | 12 |
| Teilstücke pro Seite | 3 |
| Striche pro Ring | 36 |
| Ringe | 3 bis 12 (Regler) |
| Höhe gesamt | 5,0 |
| Auslenkung der Zwischenpunkte | 0,38 |
| Zacken- und Einschnitt-Wahrscheinlichkeit | 0,35 / 0,3 |

Gemessen mit `tools/check_polygon_shape.ps1` über 5 Seeds:

```
Ecken pro Polygon     : 12
Radien-Spanne         : 1,49 bis 3,60      (bei einem Kreis 0)
Seiten-Spanne         : 0,93 bis 3,57      (beim Quadrat 0)
Innenwinkel-Spanne    : bis 360 Grad       (beim regelmäßigen Vieleck 0)
konkave Ecken         : 19 über 5 Polygone (Einbuchtungen, Winkel > 180 Grad)
```

Konkave Ecken sind der entscheidende Punkt: Sie entstehen nur, wenn eine Ecke
nach innen springt. Genau das macht ein Vieleck unregelmäßig statt quaderförmig.

Vier Ursachen sorgen für diese Form (`buildBasePolygon` und `buildRing` in
`js/generator.js`):

1. **ungleiche Winkel** – jeder Eckenabstand schwankt um bis zu 45 Prozent,
2. **stark schwankende Radien** – Ausbuchtungen und Einbuchtungen,
3. **Zacken und Einschnitte** – Ecken werden nach außen gezogen (Faktor bis 1,95)
   oder nach innen gedrückt (Faktor bis 0,45),
4. **seitliche Verschiebung** und **Höhenversatz** der Ringe – dadurch zeigen die
   Striche in verschiedene Richtungen und sind unterschiedlich lang.

Ohne diese Verformung liegen die Zwischenpunkte exakt auf der Geraden und das
Polygon wirkt trotz vieler Punkte wie ein simples Vieleck. Geprüft mit
`tools/check_selfintersect.ps1`: Die Winkelreihenfolge der Punkte bleibt über
25 Seeds stabil, es gibt also keine Selbstüberschneidung.

## Startansicht und Steuerung

Die Kamera ist eine **echte 3D-Kamera** (`makeLookAtCamera` in
`js/geometry.js`): Sie hat einen Standort im Raum und eine Blickrichtung, die
aus Standort und Blickziel berechnet wird. Der Blick von oben ist damit eine
Eigenschaft der Kameraposition und keine Einstellungssache.

| Wert | Startwert | Bedeutung |
| --- | --- | --- |
| `orbit` | -0,55 | Drehung der Kamera um den Turm |
| `eyeHeight` | 4,8 | Höhe der Kamera über der Grundfläche |
| `distance` | 6,5 | waagerechter Abstand zur Mitte |
| `targetHeight` | 1,6 | Höhe des Blickziels |

Daraus ergibt sich ein Blickwinkel von **26,2 Grad unter der Waagerechten** und
ein Blickvektor mit `y = -0,442` – die Kamera schaut also nach unten.
Nachrechnen lässt sich das mit `tools/check_view.ps1`.

### Bedienung mit der Maus

| Eingabe | Wirkung |
| --- | --- |
| Ziehen | Kamera um den Turm drehen (waagerecht) und Höhe ändern (senkrecht) |
| **Strg + Ziehen** | Ansicht verschieben (Pan) |
| Umschalt + Ziehen | nur die Kamerahöhe ändern |
| Mausrad | zoomen |
| Zeigen auf Knoten | Tooltip mit Knoten-Id, Ring, Höhe und Distanz |
| Taste `0` | Blick und Verschiebung zurücksetzen |
| Knopf **Blick zurücksetzen** | dasselbe per Klick |

Der Pan-Versatz wird direkt in Bildschirmkoordinaten geführt (`panX`, `panY`),
funktioniert also unabhängig von Drehung und Zoom.

## Darstellung

- feste, dünne Linienbreite (1,4 px normal, 2,2 px Suchbaum, 3,2 px Lösung)
- scharfe Linienenden statt runder Kappen
- winzige Knotenpunkte (1,5 px) ohne Schlagschatten
- Striche auf der Rückseite mit 16 Prozent Deckkraft

## Projektstruktur

```
index.html                  Oberfläche, Canvas und Bedienelemente
dijkstra-schlauch.html      fertige Einzeldatei, läuft per Doppelklick (file://)
styles.css                  Layout und Farbgebung
js/rng.js                   seedbarer Zufallsgenerator (Mulberry32) und 1D-Rauschen
js/geometry.js              Vektoren, 3D-Drehung, Perspektivprojektion
js/generator.js             Grundpolygon und Schlauch aus gestapelten Ringen
js/graph.js                 Graph aus Strichen (Knoten + Kanten), Start/Ziel
js/dijkstra.js              Min-Heap, Dijkstra in Schritten, Weg-Rekonstruktion
js/renderer.js              Zeichnen mit Tiefensortierung, Farben, Picking
js/main.js                  Ablaufsteuerung der Phasen und Interaktion
tools/serve.ps1             lokaler HTTP-Server (nur Windows-Bordmittel)
tools/build_single_file.ps1 erzeugt dijkstra-schlauch.html aus den Quelldateien
tools/run_verify.ps1        Szenen-, Graph- und Dijkstra-Prüfung
tools/test_part5.ps1        Zufallsgraphen gegen Bellman-Ford
tools/test_ui_flow.ps1      Klickpfade der Bedienoberfläche
tools/check_view.ps1        prüft die Startansicht (schräg von oben)
tools/find_view.ps1         sucht gültige Kamera-Kombinationen
tools/check_shape.ps1       misst Knoten, Striche und Abzweigungen
tools/check_connectivity.ps1 prüft die Erreichbarkeit des oberen Rings
tools/check_selfintersect.ps1 prüft die Ringe auf Selbstüberschneidung
tools/check_visibility.ps1  zählt sichtbare und verdeckte Striche
tools/preview_render.ps1    rendert eine Vorschau als SVG (ohne Browser)
```

## Ablauf der Animation

1. **growing** – der Turm wird Ring für Ring von unten nach oben aufgebaut.
2. **searching** – Dijkstra arbeitet Knoten für Knoten ab. Die Suche läuft
   **vollständig durch**, bis die Warteschlange leer ist, damit man alle
   Abzweigungen und den wachsenden Suchbaum sieht.
3. **tracing** – erst **nach** dem vollständigen Aufbau des Turms und **nach**
   Abschluss der Suche wird der gefundene kürzeste Weg Strich für Strich
   nachgezeichnet.
4. **done** – Ergebnis steht im Panel; erneutes Abspielen möglich.

## Verifikation

Da das Projekt ohne Laufzeitumgebung auskommt, liegen die Pruefungen als
PowerShell-Skripte bei. Sie bilden die Kernformeln von Generator, Graph und
Dijkstra nach und vergleichen sie mit einer Bellman-Ford-Gegenprobe:

```powershell
# Szenen-, Graph- und Dijkstra-Pruefung (inkl. 15 Seeds)
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run_verify.ps1

# Zufallsgraphen: Dijkstra gegen Bellman-Ford, Pfadverfolgung
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_part5.ps1
```

Erwartete Ausgabe (gekuerzt):

```
Ecken: 9, Fläche: 6,967, Radien 1,001 .. 1,900
Knoten: 189, Striche: 313 (Ring 189, Rippen 124)
Abweichungen Dijkstra/Bellman-Ford: 0
Weg: 12 Striche (6 Ringstriche, 6 Rippen), Summe 6,168, Dijkstra 6,168
Höhe 0,00 -> 3,40, monoton steigend: True
Seeds mit erreichbarem Ziel: 15 / 15
```
