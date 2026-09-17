/**
 * Erzeugt die Szene: ein unregelmäßiges, konkaves Grundpolygon in der x-z-Ebene
 * und darüber einen Turm aus stark verformten Ringen.
 *
 * Ziel der Formgebung: echte Vielecke mit Zacken, Buchten und einspringenden
 * Ecken - keine gleichmäßig abgerundeten "Quader". Dafür sorgen:
 *   1. stark ungleiche Winkel zwischen den Ecken,
 *   2. Radien mit großer Spannweite (Ausbuchtungen und Einbuchtungen),
 *   3. gezielte Zacken und Einschnitte, die auch die Winkelordnung ändern,
 *   4. ein prozeduraler "Wackel"-Anteil, der die Ringe gegeneinander versetzt.
 */
import { makeRng, makeNoise1D } from './rng.js';
import { v3, centroid2D, sortByAngle, lerp3, dist } from './geometry.js';

/**
 * Baut ein konkaves, unregelmäßiges Polygon in der x-z-Ebene.
 *
 * Die Ecken werden über eine Winkelreihenfolge verteilt und mit stark
 * schwankenden Radien versehen. Ein Teil der Ecken wird zusätzlich seitlich
 * verschoben, sodass die Kanten in unterschiedliche Richtungen zeigen.
 */
function buildBasePolygon(rng, opts) {
  const { cornerCount, radius, noise, spikeChance, dentChance } = opts;
  const corners = [];

  for (let i = 0; i < cornerCount; i++) {
    const u = i / cornerCount;
    const step = (Math.PI * 2) / cornerCount;

    // 1. stark ungleiche Winkel: bis zu 45 % Abweichung pro Schritt
    const angle = i * step + rng.range(-step * 0.45, step * 0.45);

    // 2. Radien mit großer Spannweite
    const wobble = 1 + noise(u) * 0.6;
    const local = 1 + rng.range(-0.4, 0.4);

    // 3. Zacken nach außen und Einschnitte nach innen
    const spike = rng() < spikeChance ? rng.range(1.3, 1.95) : 1;
    const dent = rng() < dentChance ? rng.range(0.45, 0.72) : 1;

    const r = radius * wobble * local * spike * dent;

    // Zusätzliche seitliche Verschiebung: dadurch zeigen die Kanten in
    // verschiedene Richtungen und das Vieleck wird wirklich unförmig.

/**
 * Baut einen Ring in einer bestimmten Höhe.
 *
 * Jeder Ring wird eigenständig verformt (nicht nur als Kopie verschoben):
 * eigene Verdrehung, eigene Schrumpfung und eigene Auslenkung der
 * Zwischenpunkte. Dadurch wird die Turmwand unregelmäßig und es entstehen
 * viele unterschiedliche Striche.
 */
function buildRing(base, center, level, rng, opts, noiseFns) {
  const t = level.height;
  const twist = level.twist;
  const shrink = level.shrink;
  const bumpAmp = level.bumpAmp;

  // Ecken dieses Ringes: verdreht, skaliert und mit eigenen Störungen
  const corners = base.map((c, i) => {
    const rel = { x: c.x - center.x, z: c.z - center.z };
    const cs = Math.cos(twist), sn = Math.sin(twist);
    const rx = rel.x * cs - rel.z * sn;
    const rz = rel.x * sn + rel.z * cs;

    const u = i / base.length;
    // weiche Welle plus harter, pro Ring wechselnder Anteil
    const wave = noiseFns.a(u + t * 1.3) * bumpAmp + noiseFns.b(u * 2 - t) * bumpAmp * 0.5;
    const jag = Math.sin((i * 2.3 + level.index * 2.7) * 2.1) * level.jagAmp;

    const r = shrink * (1 + wave + jag);
    return v3(center.x + rx * r, level.y, center.z + rz * r);
  });

  // Striche: jede Seite in mehrere Teilstücke, Zwischenpunkte ausgelenkt.
  const pts = [];
  const segs = opts.cornerSegments;
  const dent = opts.segmentDent;

  for (let i = 0; i < corners.length; i++) {
    const a = corners[i];
    const b = corners[(i + 1) % corners.length];
    for (let s = 0; s < segs; s++) {
      const u = (i + s / segs) / corners.length;
      const basePt = lerp3(a, b, s / segs);
      if (s === 0) {
        // Die echte Ecke bleibt erhalten, sonst verschwindet die Form.
        pts.push(basePt);
        continue;
      }

      const dx = b.x - a.x;
      const dz = b.z - a.z;
      const l = Math.hypot(dx, dz) || 1;
      const nx = -dz / l;
      const nz = dx / l;

      const soft = noiseFns.a(u * 2.3 + t * 1.7) * 0.8 + noiseFns.b(u * 4.1 - t * 1.1) * 0.4;
      const hard = Math.sin((i * 2.7 + level.index * 1.9) * 3.1) > 0.35 ? 0.9 : -0.55;
      const amount = (soft + hard * 0.7) * dent;

      // Zusätzlich Verschiebung in der Höhe: die Ringe sind nicht eben,
      // dadurch entstehen schräge, unterschiedlich lange Striche.
      const lift = Math.sin((i + 1) * 1.7 + level.index * 2.3) * level.warpAmp;

      pts.push(v3(basePt.x + nx * amount, basePt.y + lift, basePt.z + nz * amount));
    }
  }
  return { points: pts, corners, y: level.y, index: level.index };
}

    const sideShift = rng.range(-0.35, 0.35) * radius;

    corners.push(v3(
      Math.cos(angle) * r + sideShift,
      0,
export function buildScene(seed = 20260917, options = {}) {
  const opts = {
    cornerCount: 12,
    cornerSegments: 3,
    segmentDent: 0.38,
    spikeChance: 0.35,
    dentChance: 0.3,
    rings: 7,
    height: 5.0,
    radius: 1.5,
    jitter: 0.3,
    ribEvery: 1,
    ...options,
  };

  const rng = makeRng(seed);
  const noiseA = makeNoise1D(rng, 16);
  const noiseB = makeNoise1D(rng, 24);
  const noiseFns = { a: noiseA, b: noiseB };

  const basePolygon = buildBasePolygon(rng, {
    cornerCount: opts.cornerCount,
    radius: opts.radius,
    noise: noiseA,
    spikeChance: opts.spikeChance,
    dentChance: opts.dentChance,
  });
  const center = centroid2D(basePolygon);

  // Höhenstufen: jede mit eigenen Verformungsstärken, damit sich die Ringe
  // deutlich voneinander unterscheiden.
  const levels = [];
  for (let i = 0; i < opts.rings; i++) {
    const t = i / (opts.rings - 1 || 1);
    levels.push({
      index: i,
      height: t,
      y: t * opts.height,
      twist: t * rng.range(0.5, 1.5) + rng.range(-0.1, 0.1),
      shrink: 1 - t * rng.range(0.05, 0.35),
      bumpAmp: rng.range(0.08, 0.22),
      jagAmp: rng.range(0.04, 0.14),
      warpAmp: rng.range(0.02, 0.09),
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

      Math.sin(angle) * r + rng.range(-0.35, 0.35) * radius,
    ));
  }
  return sortByAngle(corners, centroid2D(corners));
}
