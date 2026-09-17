/**
 * Erzeugt die Szene:
 *  1. ein unregelmäßiges Polygon in der x-z-Ebene (random Ecken),
 *  2. darüber gestapelte, verformte Kopien ("Ringe"), die zusammen einen
 *     Schlauch bilden, dessen Waende aus einzelnen Strichen bestehen.
 *
 * Wichtig: Alle Rippen (vertikale Striche) und alle Ringstuecke werden
 * gleich behandelt - der Dijkstra läuft später über genau diese Striche.
 */
import { makeRng, makeNoise1D } from './rng.js';
import { v3, centroid2D, sortByAngle, lerp3, dist } from './geometry.js';

/**
 * Ein Ring ist eine geschlossene Linie aus Segmenten. Damit man den Weg
 * "nach oben" wirklich suchen muss, ist jeder Ring in mehrere Striche
 * unterteilt, und die Ringe sind untereinander nur über die Rippen verbunden.
 */
/**
 * Erzeugt das Grundpolygon in der x-z-Ebene.
 *
 * Für eine wirklich unförmige Silhouette sorgen drei Dinge zusammen:
 *  1. ungleiche Winkel zwischen den Ecken (nicht gleichmäßig verteilt),
 *  2. stark schwankende Radien (Ausbuchtungen und Einbuchtungen),
 *  3. zusätzliche "Zacken": einzelne Ecken werden weit nach außen gezogen.
 * Dadurch entstehen konkave Stellen mit echten Abzweigungen.
 */
function buildBasePolygon(rng, opts) {
  const { cornerCount, radius, jitter, noise } = opts;
  const corners = [];

  for (let i = 0; i < cornerCount; i++) {
    const u = i / cornerCount;

    // 1. ungleiche Winkel: jeder Schritt schwankt deutlich
    const step = (Math.PI * 2) / cornerCount;
    const angle = i * step + rng.range(-step * 0.35, step * 0.35);

    // 2. Radien mit großer Spannweite: Ausbuchtungen und Einbuchtungen
    const wobble = 1 + noise(u) * 0.55;
    const local = 1 + rng.range(-jitter * 2.2, jitter * 2.2);

    // 3. Zacken: etwa jede vierte Ecke wird deutlich nach außen gezogen
    const spike = rng() < 0.28 ? rng.range(1.25, 1.7) : 1;
    // und etwa jede fünfte Ecke nach innen gedrückt
    const dent = rng() < 0.2 ? rng.range(0.55, 0.78) : 1;

    const r = radius * wobble * local * spike * dent;
    corners.push(v3(Math.cos(angle) * r, 0, Math.sin(angle) * r));
  }
  return sortByAngle(corners, centroid2D(corners));
}

/**
 * Baut einen Ring in einer bestimmten Höhe aus einer Basisform auf.
 * Der Ring wird zusätzlich verdreht, geschrumpft/gestreckt und gedaempft
 * verformt, damit der Schlauch organisch wirkt.
 *
 * Wichtig: die Seiten zwischen den Ecken sind keine geraden Linien. Jeder
 * Zwischenpunkt wird zur Seite hin verschoben (nach aussen oder innen), damit
 * die Silhouette unregelmäßig "eingekerbt" wirkt. Trotzdem bleibt jedes
 * Teilstueck eine eigene, klar sichtbare Strecke.
 */
function buildRing(base, center, level, rng, opts, noiseFns) {
  const t = level.height;
  const twist = level.twist;
  const shrink = level.shrink;
  const bumpAmp = level.bumpAmp;

  const corners = base.map((c, i) => {
    const rel = { x: c.x - center.x, z: c.z - center.z };
    const cs = Math.cos(twist), sn = Math.sin(twist);
    const rx = rel.x * cs - rel.z * sn;
    const rz = rel.x * sn + rel.z * cs;
    const u = i / base.length;
    const bump = 1 + noiseFns.a(u + t) * bumpAmp + noiseFns.b(u * 2 - t) * bumpAmp * 0.5;
    const r = shrink * bump;
    return v3(center.x + rx * r, level.y, center.z + rz * r);
  });

  // Die Striche eines Ringes: jede Seite wird in `cornerSegments` Teilstuecke
  // zerlegt, deren Zwischenpunkte seitlich ausgelenkt werden.
  const pts = [];
  const segs = opts.cornerSegments;
  const dent = opts.segmentDent;

  for (let i = 0; i < corners.length; i++) {
    const a = corners[i];
    const b = corners[(i + 1) % corners.length];
    for (let s = 0; s < segs; s++) {
      const u = (i + s / segs) / corners.length;
      const base = lerp3(a, b, s / segs);
      if (s === 0) {
        // Die echte Ecke bleibt exakt erhalten - sonst verschwindet die Form.
        pts.push(base);
        continue;
      }
      // Verschiebung senkrecht zur Seite, gesteuert durch zwei Rauschwerte,
      // damit benachbarte Ringe unterschiedlich verformt sind. Ein zusätzlicher
      // harter Anteil erzeugt einzelne scharfe Knicke statt nur weicher Wellen.
      const dx = b.x - a.x;
      const dz = b.z - a.z;
      const len = Math.hypot(dx, dz) || 1;
      const nx = -dz / len;
      const nz = dx / len;

      const soft = noiseFns.a(u * 2.3 + t * 1.7) * 0.8 + noiseFns.b(u * 4.1 - t * 1.1) * 0.4;
      // Der harte Anteil springt pro Ecke und Ringstufe zwischen zwei Werten.
      const hard = Math.sin((i * 2.7 + level.index * 1.9) * 3.1) > 0.35 ? 0.85 : -0.5;
      const amount = (soft + hard * 0.6) * dent;

      pts.push(v3(base.x + nx * amount, base.y, base.z + nz * amount));
    }
  }
  return { points: pts, corners, y: level.y, index: level.index };
}

export function buildScene(seed = 20260917, options = {}) {
  const opts = {
    cornerCount: 11,
    cornerSegments: 3, // Unterteilung pro Polygonecke -> Striche pro Ring
    segmentDent: 0.34, // seitliche Auslenkung der Zwischenpunkte (unregelmäßige Seiten)
    rings: 7,
    height: 3.2,
    radius: 1.5,
    jitter: 0.2,
    ribEvery: 1, // jede n-te Rippe wird tatsächlich gebaut (Lücken erzeugen Umwege)
    ...options,
  };

  const rng = makeRng(seed);
  const noiseA = makeNoise1D(rng, 16);
  const noiseB = makeNoise1D(rng, 24);
  const noiseFns = { a: noiseA, b: noiseB };

  const basePolygon = buildBasePolygon(rng, {
    cornerCount: opts.cornerCount,
    radius: opts.radius,
    jitter: opts.jitter,
    noise: noiseA,
  });
  const center = centroid2D(basePolygon);

  // Höhenstufen des Schlauches mit leicht Zufälliger Verteilung.
  const levels = [];
  for (let i = 0; i < opts.rings; i++) {
    const t = i / (opts.rings - 1);
    levels.push({
      index: i,
      height: t,
      y: t * opts.height,
      twist: t * rng.range(0.6, 1.6) + rng.range(-0.05, 0.05),
      shrink: 1 - t * rng.range(0.05, 0.3),
      bumpAmp: rng.range(0.06, 0.2),
    });
  }

  const rings = levels.map((lvl) => buildRing(basePolygon, center, lvl, rng, opts, noiseFns));

  return {
    seed,
    options: opts,
    rng,
    basePolygon,
    center,
    rings,
    totalHeight: opts.height,
  };
}

export { dist };
