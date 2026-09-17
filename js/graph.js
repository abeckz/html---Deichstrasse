/**
 * Baut aus der Szene einen Graphen: Knoten sind die Punkte auf den Ringen,
 * Kanten sind genau die "Striche" (Ringsegmente und vertikale Rippen).
 * Neue Striche werden eingefuegt: pro Stufe eine begrenzte Anzahl,
 * damit man das Wachsen schoen beobachten kann.
 */
import { dist } from './geometry.js';

function key(x, y, z) {
  return `${Math.round(x * 1000)}|${Math.round(y * 1000)}|${Math.round(z * 1000)}`;
}

export function buildGraph(scene) {
  const nodes = [];
  const index = new Map();

  const getNode = (p, ringIndex, isCorner) => {
    const k = key(p.x, p.y, p.z);
    let id = index.get(k);
    if (id === undefined) {
      id = nodes.length;
      index.set(k, id);
      nodes.push({ id, pos: { ...p }, ring: ringIndex, isCorner, edges: [], visible: false });
    }
    return id;
  };

  const edges = [];
  const addEdge = (aId, bId, kind) => {
    if (aId === bId) return null;
    const a = nodes[aId], b = nodes[bId];
    const length = dist(a.pos, b.pos);
    if (length < 1e-6) return null;
    const edge = {
      id: edges.length,
      a: aId,
      b: bId,
      length,
      kind, // 'ring' | 'rib'
      level: Math.max(a.ring, b.ring),
      state: 'idle', // idle | tree | rejected | path
      usedInPath: false,
    };
    edges.push(edge);
    a.edges.push(edge);
    b.edges.push(edge);
    return edge;
  };

  const rings = scene.rings;

  // 1) Ringstriche: jeder Ring besteht aus lauter einzelnen Strichen.
  for (const ring of rings) {
    const n = ring.points.length;
    for (let i = 0; i < n; i++) {
      const p = ring.points[i];
      const q = ring.points[(i + 1) % n];
      const a = getNode(p, ring.index, false);
      const b = getNode(q, ring.index, false);
      addEdge(a, b, 'ring');
    }
  }

  // 2) Rippen: vertikale Striche verbinden die Ringe - aber nur an einigen
  // Stellen, damit es echte Sackgassen und Umwege gibt.
  const perRing = rings[0].points.length;
  for (let r = 0; r < rings.length - 1; r++) {
    const lower = rings[r];
    const upper = rings[r + 1];
    let built = 0;
    for (let i = 0; i < perRing; i++) {
      const step = Math.max(1, Math.round(scene.options.ribEvery));
      if (i % step !== 0) continue;
      // Zufaellige Luecken erzeugen Umwege (deterministisch gewuerfelt).
      const gapNoise = Math.sin(i * 12.9898 + r * 78.233 + scene.seed * 0.001);
      if (gapNoise > 0.75) continue;
      const aId = getNode(lower.points[i], lower.index, false);
      const bId = getNode(upper.points[i], upper.index, false);
      if (addEdge(aId, bId, 'rib')) built++;
    }
    // Sicherheitsnetz: jedes Ringpaar braucht mindestens eine Rippe,
    // sonst waere der obere Teil des Schlauches unerreichbar.
    if (built === 0) {
      const i = Math.abs(Math.round(Math.sin(r * 3.1 + scene.seed) * perRing)) % perRing;
      const aId = getNode(lower.points[i], lower.index, false);
      const bId = getNode(upper.points[i], upper.index, false);
      addEdge(aId, bId, 'rib');
    }
  }

  return {
    nodes,
    edges,
    ringCount: rings.length,
    perRing,
    bottomRing: 0,
    topRing: rings.length - 1,
  };
}

/** Start- und Zielknoten: ein Knoten im untersten Ring und einer im obersten. */
export function pickEndpoints(graph, scene) {
  const bottom = graph.nodes.filter((n) => n.ring === graph.bottomRing);
  const top = graph.nodes.filter((n) => n.ring === graph.topRing);

  // Start unten "vorne", Ziel oben moeglichst weit weg (vorne/hinten gemischt),
  // damit der Weg wirklich ein Umweg ist.
  const start = bottom.reduce((best, n) => (n.pos.z > (best?.pos.z ?? -Infinity) ? n : best), null);
  const target = top.reduce((best, n) => (n.pos.z < (best?.pos.z ?? Infinity) ? n : best), null);

  return { startId: start.id, targetId: target.id };
}
