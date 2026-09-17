/**
 * Erzeugt die Szene:
 *  1. ein unregelmaessiges Polygon in der x-z-Ebene (random Ecken),
 *  2. darueber gestapelte, verformte Kopien ("Ringe"), die zusammen einen
 *     Schlauch bilden, dessen Waende aus einzelnen Strichen bestehen.
 *
 * Wichtig: Alle Rippen (vertikale Striche) und alle Ringstuecke werden
 * gleich behandelt - der Dijkstra laeuft spaeter ueber genau diese Striche.
 */
import { makeRng, makeNoise1D } from './rng.js';
import { v3, centroid2D, sortByAngle, lerp3, dist } from './geometry.js';

/**
 * Ein Ring ist eine geschlossene Linie aus Segmenten. Damit man den Weg
 * "nach oben" wirklich suchen muss, ist jeder Ring in mehrere Striche
 * unterteilt, und die Ringe sind untereinander nur ueber die Rippen verbunden.
 */
function buildBasePolygon(rng, opts) {
  const { cornerCount, radius, jitter, noise } = opts;
  const corners = [];
  for (let i = 0; i < cornerCount; i++) {
    const angle = (i / cornerCount) * Math.PI * 2 + rng.range(-0.12, 0.12);
    const wobble = 1 + noise(i / cornerCount) * 0.35;
    const r = radius * wobble * (1 + rng.range(-jitter, jitter));
    corners.push(v3(Math.cos(angle) * r, 0, Math.sin(angle) * r));
  }
  return sortByAngle(corners, centroid2D(corners));
}

/**
 * Baut einen Ring in einer bestimmten Hoehe aus einer Basisform auf.
 * Der Ring wird zusaetzlich verdreht, geschrumpft/gestreckt und gedaempft
 * verformt, damit der Schlauch organisch wirkt.
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

  // Die Ecken sind die echten Polygon-Ecken; dazwischen liegen Unterteilungspunkte
  // ("Sprossen"), die spaeter die Knoten der einzelnen Striche bilden.
  const pts = [];
  const segs = opts.cornerSegments;
  for (let i = 0; i < corners.length; i++) {
    const a = corners[i];
    const b = corners[(i + 1) % corners.length];
    for (let s = 0; s < segs; s++) {
      pts.push(lerp3(a, b, s / segs));
    }
  }
  return { points: pts, corners, y: level.y, index: level.index };
}

export function buildScene(seed = 20260917, options = {}) {
  const opts = {
    cornerCount: 9,
    cornerSegments: 3, // Unterteilung pro Polygonecke -> Striche pro Ring
    rings: 7,
    height: 3.2,
    radius: 1.5,
    jitter: 0.18,
    ribEvery: 1, // jede n-te Rippe wird tatsaechlich gebaut (Luecken erzeugen Umwege)
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

  // Hoehenstufen des Schlauches mit leicht zufaelliger Verteilung.
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
