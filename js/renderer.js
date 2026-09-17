/**
 * Zeichnet die Szene auf ein 2D-Canvas, projiziert aus 3D.
 * Keine Bibliotheken, damit die Datei einfach im Browser läuft.
 */
import { project } from './geometry.js';

/** Farbskala von "sehr kurz" (gelb) nach "lang/unerreicht" (gedaempftes Blau). */
function heatColor(t) {
  const stops = [
    [0.0, [255, 231, 130]],
    [0.25, [255, 170, 70]],
    [0.5, [250, 105, 105]],
    [0.75, [140, 90, 220]],
    [1.0, [70, 90, 160]],
  ];
  let a = stops[0], b = stops[stops.length - 1];
  for (let i = 0; i < stops.length - 1; i++) {
    if (t >= stops[i][0] && t <= stops[i + 1][0]) {
      a = stops[i];
      b = stops[i + 1];
      break;
    }
  }
  const span = b[0] - a[0] || 1;
  const f = (t - a[0]) / span;
  const c = [0, 0, 0];
  for (let i = 0; i < 3; i++) c[i] = Math.round(a[1][i] + (b[1][i] - a[1][i]) * f);
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

export class Renderer {
  constructor(canvas, scene, graph, dpi = window.devicePixelRatio || 1) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.scene = scene;
    this.graph = graph;
    this.dpi = dpi;
    // Fester Startblick: Die Kamera schwebt auf Höhe 3.4 über der Szene und
    // blickt schräg auf die Grundfläche hinab. Beide Werte sind nötig:
    // cameraHeight hebt die Kamera an, pitch (positiv) kippt die Ansicht so,
    // dass der Boden als Fläche sichtbar wird. Geprüft mit tools/check_view.ps1.
    this.homeView = {
      yaw: -0.6,
      pitch: 0.55,
      cameraHeight: 3.4,
      distance: 9.0,
      fov: 1.35,
      offsetY: 30,
    };
    this.view = { ...this.homeView };
    this.hoverEdgeId = null;
    this.showDistances = false;
    // showHidden: verborgene Rückseiten-Striche schwach andeuten (3D-Eindruck).
    // showNodes: 'on' = kleine Verbindungspunkte, 'off' = nur Linien.
    this.showHidden = true;
    this.showNodes = 'on';
    this.maxDist = Infinity;
    this.projected = [];
    this.resize();
  }

  resize() {
    const rect = this.canvas.getBoundingClientRect();
    const w = Math.max(320, rect.width);
    const h = Math.max(240, rect.height);
    this.canvas.width = Math.floor(w * this.dpi);
    this.canvas.height = Math.floor(h * this.dpi);
    this.width = w;
    this.height = h;
    this.ctx.setTransform(this.dpi, 0, 0, this.dpi, 0, 0);
  }

  rotateBy(dx, dy) {
    this.view.yaw += dx * 0.006;
    this.view.pitch = Math.max(-1.2, Math.min(1.2, this.view.pitch + dy * 0.006));
  }

  /** Setzt den Blick auf die feste Startansicht zurück (schräg von oben). */
  resetView() {
    this.view = { ...this.homeView };
  }

  zoomBy(factor) {
    this.view.distance = Math.max(2.5, Math.min(20, this.view.distance * factor));
  }

  /** Projektion für alle Knoten einmal pro Frame berechnen (Performance). */
  computeScreenNodes() {
    const view = this.view;
    const w = this.width, h = this.height;
    this.projected = this.graph.nodes.map((n) => project(n.pos, view, w, h));
  }

  edgeColor(edge) {
    if (edge.usedInPath) return '#ffe066';
    if (edge.state === 'tree') {
      const max = Number.isFinite(this.maxDist) && this.maxDist > 0 ? this.maxDist : 1;
      const d = Math.max(this.graph.nodes[edge.a].dist, this.graph.nodes[edge.b].dist);
      return heatColor(Math.min(1, (Number.isFinite(d) ? d : max) / max));
    }
    if (edge.state === 'rejected') return 'rgba(150, 160, 190, 0.25)';
    if (edge.state === 'active') return '#ffffff';
    return 'rgba(120, 140, 190, 0.42)';
  }

  /** Zeichnet die komplette Szene. */
  draw(state, opts = {}) {
    const ctx = this.ctx;
    const { width: w, height: h } = this;

    const grad = ctx.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, '#0b1020');
    grad.addColorStop(1, '#141a2e');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    this.computeScreenNodes();
    this.drawFloor();

    const drawList = this.graph.edges
      .filter((e) => !opts.onlyPath || e.usedInPath)
      .filter((e) => this.isEdgeVisible(e))
      .map((e) => {
        const pa = this.projected[e.a], pb = this.projected[e.b];
        // Ein Streckenzug liegt "hinten", wenn sein Mittelpunkt hinter dem
        // Zentrum des Schlauches liegt. Solche Striche werden gedaempft,
        // damit man die Form als Koerper und nicht als Knaeuel sieht.
        const depth = (pa.depth + pb.depth) * 0.5;
        const behind = this.isBehindCenter(e);
        return { e, pa, pb, depth, behind };
      })
      .sort((u, v) => v.depth - u.depth);

    // Erst alle hinteren Striche gedaempft, dann die vorderen kraeftig.
    for (const d of drawList) {
      if (d.behind) this.drawEdge(d, state, true);
    }
    for (const d of drawList) {
      if (!d.behind) this.drawEdge(d, state, false);
    }

    this.drawNodes(state, opts);
    if (this.showDistances) this.drawDistanceLabels();
  }

  /**
   * Prueft, ob ein Strich auf der abgewandten Seite des Schlauches liegt.
   * Dazu wird die Höhe des Strichs betrachtet: der Mittelpunkt des Ringes
   * in dieser Höhe liegt näher an der Kamera als der Strich selbst.
   */
  isBehindCenter(edge) {
    if (!this.showHidden) return false;
    const a = this.projected[edge.a];
    const b = this.projected[edge.b];
    if (!a || !b) return false;
    const mid = { x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5, depth: (a.depth + b.depth) * 0.5 };
    const center = this.projectCenterAt(mid.y, edge.level);
    return center !== null && center.depth < mid.depth;
  }

  /** Projiziert den Mittelpunkt der Schlauchachse auf gleicher Höhe. */
  projectCenterAt(screenY, level) {
    if (!this.scene || !this.scene.center) return null;
    const c = this.scene.center;
    const rings = this.scene.rings || [];
    const ring = rings[Math.min(rings.length - 1, Math.max(0, level || 0))];
    const y = ring ? ring.y : 0;
    return project({ x: c.x, y, z: c.z }, this.view, this.width, this.height);
  }

  /** Waehrend der Aufbauphase werden noch nicht erzeugte Ringe ausgeblendet. */
  isEdgeVisible(edge) {
    const a = this.graph.nodes[edge.a];
    const b = this.graph.nodes[edge.b];
    if (a.visible === false || b.visible === false) return false;
    return true;
  }

  drawEdge(d, state, behind) {
    const ctx = this.ctx;
    const { e, pa, pb } = d;
    const dim = e.state === 'idle' && !e.usedInPath;

    // Feste, duenne Linienbreite: jede Strecke bleibt als klare Linie erkennbar.
    const width = e.usedInPath ? 3.2 : (e.state === 'tree' ? 2.2 : 1.4);

    ctx.globalAlpha = behind ? 0.16 : (dim ? 0.5 : 1);
    ctx.strokeStyle = this.edgeColor(e);
    ctx.lineWidth = width;
    // Scharfe Enden statt runder Kappen, sonst verschmieren kurze Striche.
    ctx.lineCap = 'butt';

    if (!behind && e.usedInPath) {
      ctx.shadowColor = 'rgba(255, 224, 102, 0.8)';
      ctx.shadowBlur = 10;
    } else if (!behind && state && state.justRelaxed && state.justRelaxed.some((r) => r.edge === e)) {
      ctx.shadowColor = 'rgba(120, 220, 255, 0.8)';
      ctx.shadowBlur = 8;
    }

    ctx.beginPath();
    ctx.moveTo(pa.x, pa.y);
    ctx.lineTo(pb.x, pb.y);
    ctx.stroke();
    ctx.shadowBlur = 0;
    ctx.globalAlpha = 1;

    if (e.id === this.hoverEdgeId) {
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = 1.2;
      ctx.stroke();
    }
  }

  drawNodes(state, opts) {
    if (this.showNodes === false) return;

    const ctx = this.ctx;
    const order = this.graph.nodes
      .map((n, i) => ({ n, p: this.projected[i] }))
      .sort((u, v) => v.p.depth - u.p.depth);

    // Sehr kleiner Grundradius: die Linien bleiben die Hauptdarsteller.
    const baseR = 1.5;

    for (const { n, p } of order) {
      if (opts.onlyPath && !n.onPath) continue;
      if (n.visible === false) continue;

      let color = null;
      let radius = baseR;

      if (n.state === 'settled') {
        color = '#ffd166';
        radius = baseR * 1.5;
      } else if (n.state === 'queued') {
        color = 'rgba(120, 200, 255, 0.95)';
        radius = baseR * 1.3;
      }
      if (state && n.id === state.startId) {
        color = '#5ee1a8';
        radius = baseR * 2.6;
      } else if (state && n.id === state.targetId) {
        color = '#ff8fb1';
        radius = baseR * 2.6;
      }
      if (state && n.id === state.justSettledId) {
        color = '#ffffff';
        radius = baseR * 2.4;
      }

      // Unauffaellige Verbindungspunkte werden nur als winziger Punkt gesetzt,
      // damit die Striche klar getrennt bleiben.
      if (color === null) {
        if (this.showNodes === 'off') continue;
        color = 'rgba(200, 214, 245, 0.7)';
      }

      ctx.beginPath();
      ctx.fillStyle = color;
      ctx.arc(p.x, p.y, radius, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  drawDistanceLabels() {
    const ctx = this.ctx;
    const max = Number.isFinite(this.maxDist) && this.maxDist > 0 ? this.maxDist : 1;
    ctx.font = '10px ui-monospace, monospace';
    ctx.textAlign = 'center';
    for (const n of this.graph.nodes) {
      if (!Number.isFinite(n.dist)) continue;
      if (n.visible === false) continue;
      const p = this.projected[n.id];
      ctx.fillStyle = heatColor(Math.min(1, n.dist / max));
      ctx.fillText(n.dist.toFixed(2), p.x, p.y - 6);
    }
  }

  /** Bodenraster für die Raumwirkung. */
  drawFloor() {
    const ctx = this.ctx;
    const gridHalf = 3.2, step = 0.4;
    ctx.strokeStyle = 'rgba(90, 110, 160, 0.16)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let i = -gridHalf; i <= gridHalf + 1e-6; i += step) {
      const a = project({ x: i, y: 0, z: -gridHalf }, this.view, this.width, this.height);
      const b = project({ x: i, y: 0, z: gridHalf }, this.view, this.width, this.height);
      const c = project({ x: -gridHalf, y: 0, z: i }, this.view, this.width, this.height);
      const d = project({ x: gridHalf, y: 0, z: i }, this.view, this.width, this.height);
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
      ctx.moveTo(c.x, c.y);
      ctx.lineTo(d.x, d.y);
    }
    ctx.stroke();
  }

  /** Nächstgelegener Knoten zu einer Mausposition (Tooltip). */
  pickNode(mx, my) {
    if (this.projected.length === 0) return null;
    let best = null;
    for (let i = 0; i < this.projected.length; i++) {
      const p = this.projected[i];
      if (this.graph.nodes[i].visible === false) continue;
      const d = Math.hypot(p.x - mx, p.y - my);
      if (d < 14 && (!best || d < best.d)) best = { d, node: this.graph.nodes[i], screen: p };
    }
    return best;
  }
}
