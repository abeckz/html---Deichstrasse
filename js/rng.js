/**
 * Deterministischer Zufallsgenerator + einfaches Rauschen.
 * Damit laesst sich jede Szene ueber einen Seed reproduzieren.
 */

/** Mulberry32 - kleiner, schneller, seedbarer PRNG. */
export function makeRng(seed) {
  let a = (seed >>> 0) || 1;
  const rng = function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  rng.range = (min, max) => min + rng() * (max - min);
  rng.int = (min, max) => Math.floor(rng.range(min, max + 1));
  rng.pick = (arr) => arr[Math.floor(rng() * arr.length) % arr.length];
  return rng;
}

/** Erzeugt eine glatte 1D-Rauschfunktion aus ein paar Zufallswerten (Kosinus-Interpolation). */
export function makeNoise1D(rng, points = 12) {
  const values = [];
  for (let i = 0; i < points; i++) values.push(rng() * 2 - 1);
  return (t) => {
    const n = values.length;
    const x = ((t % 1) + 1) % 1;
    const f = x * n;
    const i0 = Math.floor(f) % n;
    const i1 = (i0 + 1) % n;
    const frac = f - Math.floor(f);
    const smooth = (1 - Math.cos(frac * Math.PI)) * 0.5;
    return values[i0] * (1 - smooth) + values[i1] * smooth;
  };
}
