/**
 * Dijkstra als Generator: nach jedem Schritt (bzw. nach n Relaxierungen)
 * wird pausiert und der aktuelle Zustand nach aussen sichtbar.
 */

/** Sehr einfache Binaerheap-basierte Priority Queue (Min-Heap). */
export class MinHeap {
  constructor() {
    this.items = [];
  }
  get size() {
    return this.items.length;
  }
  push(node, dist) {
    const item = { node, dist };
    this.items.push(item);
    let i = this.items.length - 1;
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (this.items[parent].dist <= this.items[i].dist) break;
      [this.items[parent], this.items[i]] = [this.items[i], this.items[parent]];
      i = parent;
    }
    return item;
  }
  pop() {
    const top = this.items[0];
    const last = this.items.pop();
    if (this.items.length > 0) {
      this.items[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let smallest = i;
        if (l < this.items.length && this.items[l].dist < this.items[smallest].dist) smallest = l;
        if (r < this.items.length && this.items[r].dist < this.items[smallest].dist) smallest = r;
        if (smallest === i) break;
        [this.items[smallest], this.items[i]] = [this.items[i], this.items[smallest]];
        i = smallest;
      }
    }
    return top;
  }
}

/**
 * Legt die Dijkstra-Zustaende auf dem Graphen an.
 * Zustand pro Knoten: 'idle' | 'queued' | 'settled'
 */
export function initDijkstra(graph, startId) {
  for (const n of graph.nodes) {
    n.dist = Infinity;
    n.prevEdge = null;
    n.state = 'idle';
    n.relaxCount = 0;
  }
  graph.nodes[startId].dist = 0;
  graph.nodes[startId].state = 'queued';

  const queue = new MinHeap();
  queue.push(startId, 0);

  return {
    graph,
    startId,
    queue,
    settledCount: 0,
    relaxations: 0,
    finished: false,
    justSettled: null,
    justRelaxed: [],
  };
}

/**
 * Führt bis zu `steps` Relaxierungen durch und gibt zurück, ob es weitergeht.
 * Jeder "Schritt" ist das Abarbeiten genau eines Knotens aus der Queue,
 * wobei alle Nachbarn dieses Knotens relaxiert werden (sichtbar als Aufleuchten).
 */
export function dijkstraStep(state, steps = 1) {
  const { graph } = state;
  let done = 0;
  while (done < steps) {
    state.justRelaxed = [];
    if (state.queue.size === 0) {
      state.finished = true;
      state.justSettled = null;
      return false;
    }
    const top = state.queue.pop();
    const node = graph.nodes[top.node];
    // Veralteter Eintrag: Knoten wurde schon abgearbeitet.
    if (node.state === 'settled') continue;
    if (top.dist > node.dist) continue;

    node.state = 'settled';
    state.settledCount++;
    state.justSettled = node.id;
    done++;

    for (const edge of node.edges) {
      const otherId = edge.a === node.id ? edge.b : edge.a;
      const other = graph.nodes[otherId];
      if (other.state === 'settled') continue;
      const candidate = node.dist + edge.length;
      state.relaxations++;
      if (candidate < other.dist) {
        other.dist = candidate;
        other.prevEdge = edge;
        other.state = 'queued';
        edge.state = 'tree';
        edge.usedInPath = false;
        state.queue.push(otherId, candidate);
        state.justRelaxed.push({ nodeId: otherId, edge });
      } else if (!edge.usedInPath) {
        // Nur Kanten, die nicht schon zum vorläufigen Weg gehören, werden
        // als verworfen markiert - sonst flackert die Anzeige.
        edge.state = 'rejected';
      }
    }
  }
  return !state.finished;
}

/** Rekonstruiert den kürzesten Weg von start zum Ziel als Liste von Knoten-Ids + Kanten. */
export function shortestPath(state, targetId) {
  const { graph } = state;
  const target = graph.nodes[targetId];
  if (!Number.isFinite(target.dist)) return null;
  const nodeIds = [targetId];
  const edges = [];
  let cur = target;
  while (cur.prevEdge) {
    edges.push(cur.prevEdge);
    const prevId = cur.prevEdge.a === cur.id ? cur.prevEdge.b : cur.prevEdge.a;
    nodeIds.push(prevId);
    cur = graph.nodes[prevId];
    if (cur.id === state.startId) break;
  }
  nodeIds.reverse();
  edges.reverse();
  return { nodeIds, edges, length: target.dist };
}
