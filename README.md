# Dijkstra im Schlauch

Interaktive Visualisierung des **Dijkstra-Algorithmus** in einer zufaellig
generierten 3D-Szene:

1. In der x-z-Ebene wird ein **unfoermiges Polygon** mit zufaelligen Ecken erzeugt.
2. Darueber stapeln sich verformte, gedrehte Kopien dieses Polygons zu einem
   **Schlauch**. Die Waende bestehen aus einzelnen **Strichen**
   (Ringsegmente und vertikale Rippen).
3. Der **Dijkstra-Algorithmus** sucht darin den kuerzesten Weg von unten nach oben.
   Jeder Schritt wird sichtbar: Knoten leuchten auf, vorlaeufige Wege faerben sich
   nach Distanz ein, der fertige Weg pulsiert gelb.

Alles laeuft langsam und nachvollziehbar ab - erst waechst der Schlauch,
dann sucht der Algorithmus, dann wird der gefundene Weg zurueckverfolgt.

## Starten

Kein Build, keine Abhaengigkeiten. Einfach `index.html` im Browser oeffnen
(ES-Module sind enthalten, daher bei Bedarf ueber einen lokalen Server):

```powershell
# Variante 1: direkt oeffnen
start index.html

# Variante 2: mit lokalem Server (z. B. via Python, falls installiert)
python -m http.server 8000
# dann http://localhost:8000 aufrufen
```

## Bedienung

| Bedienung | Wirkung |
| --- | --- |
| **Start / Pause** (oder Leertaste) | Animation anhalten und weiterlaufen lassen |
| **Neu suchen** | Suche auf derselben Szene neu starten |
| **Neue Szene** (oder `R`) | neuer Zufalls-Seed, neue Form und neuer Schlauch |
| **Tempo** | Millisekunden pro abgearbeitetem Knoten (groesser = langsamer) |
| **Schlauchhoehe** | Anzahl der Ringe (3 bis 12) |
| **Seed** | reproduzierbare Szene; gleicher Seed = gleiche Form |
| **Distanzwerte** | numerische Distanzen an den Knoten einblenden |
| Ziehen mit der Maus | Szene drehen |
| Mausrad | zoomen |
| Maus ueber Knoten | Tooltip mit Knoten-Id, Ring, Hoehe und Distanz |

## Legende der Farben

- **gruen** – Startknoten (unten)
- **rosa** – Zielknoten (oben)
- **blau** – in der Warteschlange (entdeckt, noch nicht abgearbeitet)
- **gelb** – abgearbeitet (Distanz endgueltig)
- **weiss blinkend** – gerade abgearbeiteter Knoten
- **Farbskala** der Striche – vorlaeufig bester Weg, von kurz (gelb) nach lang (violett)
- **pulsierend gelb** – der endgueltige kuerzeste Weg

## Projektstruktur

```
index.html           Oberflaeche, Canvas und Bedienelemente
styles.css           Layout und Farbgebung
js/rng.js            seedbarer Zufallsgenerator (Mulberry32) und 1D-Rauschen
js/geometry.js       Vektoren, 3D-Drehung, Perspektivprojektion
js/generator.js      Grundpolygon und Schlauch aus gestapelten Ringen
js/graph.js          Graph aus Strichen (Knoten + Kanten), Start/Ziel
js/dijkstra.js       Min-Heap, Dijkstra in Schritten, Weg-Rekonstruktion
js/renderer.js       Zeichnen mit Tiefensortierung, Farben, Picking
js/main.js           Ablaufsteuerung der Phasen und Interaktion
tools/               Verifikationsskripte (siehe unten)
```

## Phasen des Ablaufs

1. **growing** – die Ringe des Schlauches werden von unten nach oben sichtbar.
2. **searching** – pro Tick wird ein Knoten abgearbeitet, seine Nachbarn werden
   relaxiert (blau blinkend) und die Distanzen aktualisiert.
3. **tracing** – der kuerzeste Weg wird Strich fuer Strich gelb nachgezeichnet.
4. **done** – Ergebnis steht im Panel; erneutes Abspielen moeglich.

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
Ecken: 9, Flaeche: 6,967, Radien 1,001 .. 1,900
Knoten: 189, Striche: 313 (Ring 189, Rippen 124)
Abweichungen Dijkstra/Bellman-Ford: 0
Weg: 12 Striche (6 Ringstriche, 6 Rippen), Summe 6,168, Dijkstra 6,168
Hoehe 0,00 -> 3,40, monoton steigend: True
Seeds mit erreichbarem Ziel: 15 / 15
```
