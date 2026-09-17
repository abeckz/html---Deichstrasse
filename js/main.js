/**
 * Hauptsteuerung: Szene bauen, Graph bauen, Dijkstra animiert ablaufen lassen.
 * Die Animation läuft über einen "Tick"-Zähler, damit man alles sehen kann.
 */
import { buildScene } from './generator.js';
import { buildGraph, pickEndpoints } from './graph.js';
import { initDijkstra, dijkstraStep, shortestPath } from './dijkstra.js';
import { Renderer } from './renderer.js';

const ui = {
  canvas: document.getElementById('scene'),
  seed: document.getElementById('seedInput'),
  speed: document.getElementById('speed'),
  speedLabel: document.getElementById('speedLabel'),
  density: document.getElementById('density'),
  densityLabel: document.getElementById('densityLabel'),
  regenerate: document.getElementById('regenerate'),
  playPause: document.getElementById('playPause'),
  reset: document.getElementById('reset'),
  resetView: document.getElementById('resetView'),
  showDist: document.getElementById('showDist'),
  showHidden: document.getElementById('showHidden'),
  showNodes: document.getElementById('showNodes'),
  statNodes: document.getElementById('statNodes'),
  statEdges: document.getElementById('statEdges'),
  statSettled: document.getElementById('statSettled'),
  statReached: document.getElementById('statReached'),
  statDist: document.getElementById('statDist'),
  statState: document.getElementById('statState'),
  progress: document.getElementById('progress'),
  tooltip: document.getElementById('tooltip'),
  summary: document.getElementById('summary'),
};

const app = {
  seed: Number(ui.seed.value) || 20260917,
  scene: null,
  graph: null,
  state: null,
  renderer: null,
  running: false,
  phase: 'growing', // growing | searching | tracing | done
  growLevel: 0,
  growTimer: 0,
  traceIndex: 0,
  traceTimer: 0,
  lastTime: 0,
  accTime: 0,
};

function buildWorld(seed) {
  app.seed = seed;
  app.scene = buildScene(seed, {
    // Echte, konkave Polygone: viele Ecken mit Zacken und Einschnitten.
    cornerCount: 12,
    cornerSegments: 3,
    segmentDent: 0.38,
    spikeChance: 0.35,
    dentChance: 0.3,
    rings: Number(ui.density.value),
    // Deutlich höher als breit, damit sich die Ringe nicht überlagern.
    height: 5.0,
    radius: 1.5,
    jitter: 0.3,
    ribEvery: 1,
  });
  app.graph = buildGraph(app.scene);
  const { startId, targetId } = pickEndpoints(app.graph, app.scene);
  app.startId = startId;
  app.targetId = targetId;

  if (!app.renderer) {
    app.renderer = new Renderer(ui.canvas, app.scene, app.graph);
  } else {
    app.renderer.scene = app.scene;
    app.renderer.graph = app.graph;
  }
  // Anzeigeoptionen aus den Bedienelementen übernehmen.
  app.renderer.showDistances = ui.showDist.checked;
  app.renderer.showHidden = ui.showHidden.checked;
  app.renderer.showNodes = ui.showNodes.checked ? 'on' : 'off';
  // Jede neue Szene beginnt mit demselben Blick: schräg von oben.
  app.renderer.resetView();

  resetSearch(true);
  updateStaticStats();
  ui.summary.textContent = '';
}

function resetSearch(autoStart = false) {
  app.state = initDijkstra(app.graph, app.startId);
  app.state.targetId = app.targetId;
  app.state.justSettledId = null;
  app.phase = 'growing';
  app.running = autoStart;
  app.growLevel = 0;
  app.growTimer = 0;
  app.traceIndex = 0;
  app.accTime = 0;
  app.renderer.hoverEdgeId = null;
  for (const e of app.graph.edges) e.state = 'idle';
  for (const n of app.graph.nodes) {
    n.onPath = false;
    n.visible = false;
  }
  app.renderer.maxDist = Infinity;
  ui.playPause.textContent = autoStart ? 'Pause' : 'Start';
  ui.progress.style.width = '0%';
  updateStats();
}

function updateStaticStats() {
  ui.statNodes.textContent = app.graph.nodes.length;
  ui.statEdges.textContent = app.graph.edges.length;
}

function updateStats() {
  const s = app.state;
  if (!s) return;
  let reached = 0;
  for (const n of s.graph.nodes) if (Number.isFinite(n.dist)) reached++;
  ui.statSettled.textContent = `${s.settledCount} / ${s.graph.nodes.length}`;
  ui.statReached.textContent = reached;

  const target = s.graph.nodes[app.targetId];
  ui.statDist.textContent = Number.isFinite(target.dist) ? target.dist.toFixed(3) : '-';

  const labels = {
    growing: 'Schlauch wächst ...',
    search: 'suche ...',
    searching: 'suche ...',
    tracing: 'Weg zurückverfolgen ...',
    done: 'fertig',
  };
  ui.statState.textContent = labels[app.phase] || 'bereit';

  const total = s.graph.nodes.length || 1;
  ui.progress.style.width = `${Math.min(100, (s.settledCount / total) * 100).toFixed(1)}%`;
}

/* ------------------------------- Animation ------------------------------- */

function loop(now) {
  const dt = Math.min(0.05, (now - app.lastTime) / 1000 || 0);
  app.lastTime = now;

  if (app.running) {
    if (app.phase === 'growing') {
      advanceGrowth(dt);
    } else {
      const secondsPerStep = Number(ui.speed.value) / 1000; // Zeit pro Knoten
      app.accTime += dt;
      let guard = 0;
      while (app.accTime >= secondsPerStep && guard++ < 40) {
        app.accTime -= secondsPerStep;
        advance();
      }
    }
  }

  if (app.phase === 'tracing') {
    app.traceTimer -= dt;
    if (app.traceTimer <= 0) advanceTrace();
  }

  app.renderer.draw(app.state, { onlyPath: false });
  requestAnimationFrame(loop);
}

/**
 * Aufbauphase: die Ringe des Schlauches werden von unten nach oben sichtbar,
 * so dass man zuerst sieht, wie der Schlauch entsteht - und danach erst sucht
 * der Algorithmus darin.
 */
function advanceGrowth(dt) {
  const total = app.graph.ringCount || 1;
  app.growTimer += dt;
  const secondsPerRing = Math.max(0.06, (Number(ui.speed.value) / 1000) * 8);

  while (app.growTimer >= secondsPerRing && app.growLevel < total) {
    app.growTimer -= secondsPerRing;
    app.growLevel++;
    for (const n of app.graph.nodes) {
      if (n.ring < app.growLevel) n.visible = true;
    }
  }

  const pct = Math.min(100, (app.growLevel / total) * 100);
  ui.progress.style.width = `${pct.toFixed(1)}%`;

  if (app.growLevel >= total) {
    app.phase = 'searching';
    app.accTime = 0;
    ui.progress.style.width = '0%';
    ui.statState.textContent = 'suche ...';
  }
}

/** Ein animierter Schritt des Dijkstra. */
function advance() {
  if (app.phase !== 'searching') return;

  const more = dijkstraStep(app.state, 1);

  // Farbnormierung laufend anpassen, damit die Farben im Rahmen bleiben.
  let max = 0;
  for (const n of app.graph.nodes) if (Number.isFinite(n.dist) && n.dist > max) max = n.dist;
  app.renderer.maxDist = max || 1;

  // Die Suche läuft vollständig durch, damit man alle Abzweigungen sieht.
  // Erst wenn die Warteschlange leer ist, wird der gefundene Weg nachgezeichnet.
  if (!more) startTracing();
  updateStats();
}

/**
 * Startet das langsame Nachzeichnen des kürzesten Weges.
 * Wird erst aufgerufen, nachdem der Turm vollständig aufgebaut ist und die
 * Suche alle Knoten abgearbeitet hat.
 */
function startTracing() {
  const path = shortestPath(app.state, app.targetId);
  if (!path) {
    app.phase = 'done';
    app.running = false;
    ui.playPause.textContent = 'Start';
    ui.summary.textContent = 'Ziel wurde nicht erreicht - die Rippen haben eine unpassierbare Lücke.';
    return;
  }
  app.tracePath = path;
  app.traceIndex = 0;
  app.phase = 'tracing';
  app.traceTimer = 0.35;

  for (const n of app.graph.nodes) n.onPath = false;
  for (const e of app.graph.edges) e.usedInPath = false;

  ui.summary.textContent = `Kürzester Weg gefunden: ${path.edges.length} Striche, Länge ${path.length.toFixed(3)}`;
  updateStats();
}

/** Setzt Schritt für Schritt den Weg frei (leuchtet langsam auf). */
function advanceTrace() {
  const path = app.tracePath;
  if (app.traceIndex >= path.edges.length) {
    app.phase = 'done';
    app.running = false;
    ui.playPause.textContent = 'Erneut abspielen';
    ui.statState.textContent = 'fertig';
    return;
  }
  const edge = path.edges[app.traceIndex];
  const nodeId = path.nodeIds[app.traceIndex];
  edge.usedInPath = true;
  edge.state = 'path';
  app.graph.nodes[nodeId].onPath = true;
  if (app.traceIndex === path.edges.length - 1) {
    app.graph.nodes[path.nodeIds[path.nodeIds.length - 1]].onPath = true;
  }
  app.traceIndex++;
  app.traceTimer = (Number(ui.speed.value) / 1000) * 0.6;
}

/* ------------------------------ Interaktion ------------------------------ */

function setRunning(value) {
  // In der Aufbau- und Suchphase wird nur pausiert bzw. fortgesetzt.
  if (app.phase !== 'done') {
    app.running = value;
    ui.playPause.textContent = value ? 'Pause' : 'Weiter';
    return;
  }
  // Nach dem Ende startet der Knopf einen kompletten neuen Durchlauf.
  if (value) {
    resetSearch(true);
  }
}

/** Der Knopf schaltet um: läuft etwas, wird pausiert - sonst gestartet. */
function toggleRunning() {
  if (app.phase === 'done') {
    resetSearch(true);
    return;
  }
  setRunning(!app.running);
}

ui.playPause.addEventListener('click', toggleRunning);
ui.reset.addEventListener('click', () => resetSearch(true));
ui.resetView.addEventListener('click', () => app.renderer.resetView());

ui.regenerate.addEventListener('click', () => {
  const seed = Math.floor(Math.random() * 1e9);
  ui.seed.value = seed;
  buildWorld(seed);
});

ui.seed.addEventListener('change', () => {
  const seed = Number(ui.seed.value) || 1;
  buildWorld(seed);
});

ui.speed.addEventListener('input', () => {
  ui.speedLabel.textContent = `${ui.speed.value} ms`;
});
ui.density.addEventListener('input', () => {
  ui.densityLabel.textContent = ui.density.value;
  buildWorld(Number(ui.seed.value) || app.seed);
});
ui.showDist.addEventListener('change', () => {
  app.renderer.showDistances = ui.showDist.checked;
});
ui.showHidden.addEventListener('change', () => {
  app.renderer.showHidden = ui.showHidden.checked;
});
ui.showNodes.addEventListener('change', () => {
  app.renderer.showNodes = ui.showNodes.checked ? 'on' : 'off';
});

// Maussteuerung:
//   Ziehen             = Ansicht drehen
//   Strg + Ziehen      = Ansicht verschieben (Pan)
//   Umschalt + Ziehen  = Kamerahöhe ändern
//   Rad                = zoomen
//   Zeigen             = Tooltip am Knoten
let dragging = false, lastX = 0, lastY = 0, dragMode = 'orbit';

ui.canvas.addEventListener('pointerdown', (e) => {
  dragging = true;
  lastX = e.clientX;
  lastY = e.clientY;
  // Strg gedrückt: verschieben statt drehen
  dragMode = e.ctrlKey || e.metaKey ? 'pan' : (e.shiftKey ? 'height' : 'orbit');
  ui.canvas.setPointerCapture(e.pointerId);
  ui.canvas.style.cursor = dragMode === 'pan' ? 'move' : 'grabbing';
});

ui.canvas.addEventListener('pointerup', (e) => {
  dragging = false;
  if (ui.canvas.hasPointerCapture(e.pointerId)) ui.canvas.releasePointerCapture(e.pointerId);
  ui.canvas.style.cursor = 'grab';
});

ui.canvas.addEventListener('pointermove', (e) => {
  const rect = ui.canvas.getBoundingClientRect();

  if (dragging) {
    const dx = e.clientX - lastX;
    const dy = e.clientY - lastY;
    lastX = e.clientX;
    lastY = e.clientY;

    if (dragMode === 'pan') {
      // Verschieben: funktioniert auch, wenn mittendrin Strg losgelassen wird
      // oder zusätzlich gedrückt wird, deshalb prüfen wir die Taste live.
      if (e.ctrlKey || e.metaKey) app.renderer.panBy(dx, dy);
      else app.renderer.rotateBy(dx, dy);
    } else if (dragMode === 'height' || e.shiftKey) {
      app.renderer.rotateBy(dx * 0.4, dy);
    } else {
      app.renderer.rotateBy(dx, dy);
    }
    return;
  }

  const hit = app.renderer.pickNode(e.clientX - rect.left, e.clientY - rect.top);
  if (hit) {
    const n = hit.node;
    ui.tooltip.style.display = 'block';
    ui.tooltip.style.left = `${e.clientX - rect.left + 14}px`;
    ui.tooltip.style.top = `${e.clientY - rect.top + 14}px`;
    const d = Number.isFinite(n.dist) ? n.dist.toFixed(3) : 'unerreicht';
    ui.tooltip.textContent = `Knoten #${n.id} · Ring ${n.ring} · Höhe ${n.pos.y.toFixed(2)} · dist ${d}`;
  } else {
    ui.tooltip.style.display = 'none';
  }
});

ui.canvas.addEventListener('pointerleave', () => {
  ui.tooltip.style.display = 'none';
});

ui.canvas.addEventListener('wheel', (e) => {
  e.preventDefault();
  app.renderer.zoomBy(e.deltaY > 0 ? 1.08 : 0.92);
}, { passive: false });

// Strg gedrückt halten zeigt den Verschiebe-Cursor an.
window.addEventListener('keydown', (e) => {
  if ((e.ctrlKey || e.metaKey) && !app.running) ui.canvas.style.cursor = 'move';
});
window.addEventListener('keyup', (e) => {
  if (!e.ctrlKey && !e.metaKey) ui.canvas.style.cursor = dragging ? 'grabbing' : 'grab';
});

window.addEventListener('resize', () => app.renderer.resize());
window.addEventListener('keydown', (e) => {
  if (e.code === 'Space') {
    e.preventDefault();
    toggleRunning();
  }
  if (e.code === 'KeyR') {
    ui.regenerate.click();
  }
  // Null setzt die Ansicht auf den Startblick zurück.
  if (e.code === 'Digit0' || e.code === 'Numpad0') {
    app.renderer.resetView();
  }
});

/* --------------------------------- Start --------------------------------- */

buildWorld(Number(ui.seed.value) || app.seed);
app.lastTime = performance.now();
requestAnimationFrame(loop);
// Animation sofort starten: erst wächst der Turm, dann sucht Dijkstra.
setRunning(true);

