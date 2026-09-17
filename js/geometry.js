/**
 * Kleine Vektor- und Geometriehelfer für die 3D-Szene.
 * Koordinaten: x nach rechts, y nach oben, z in die Tiefe (Höhe des Schlauches = y).
 * Die "Bodenebene" des Polygons ist also x-z.
 */

export const v3 = (x = 0, y = 0, z = 0) => ({ x, y, z });

export const sub = (a, b) => v3(a.x - b.x, a.y - b.y, a.z - b.z);
export const add = (a, b) => v3(a.x + b.x, a.y + b.y, a.z + b.z);
export const scale = (a, s) => v3(a.x * s, a.y * s, a.z * s);
export const len = (a) => Math.hypot(a.x, a.y, a.z);
export const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z);

export function lerp3(a, b, t) {
  return v3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
}

/** Rotation um die Y-Achse (Drehen des Schlauches) und anschliessend um X (Kippen). */
export function rotate(p, yaw, pitch) {
  const cy = Math.cos(yaw), sy = Math.sin(yaw);
  const x1 = p.x * cy - p.z * sy;
  const z1 = p.x * sy + p.z * cy;
  const cx = Math.cos(pitch), sx = Math.sin(pitch);
  const y1 = p.y * cx - z1 * sx;
  const z2 = p.y * sx + z1 * cx;
  return v3(x1, y1, z2);
}

/**
 * Perspektivprojektion auf die CanvasFläche.
 *
 * Die Kamera schwebt bei (0, cameraHeight, distance) und schaut auf die
 * GrundFläche hinab. `pitch` kippt zusätzlich die Ansicht. Damit ist der
 * Blick von oben physikalisch eindeutig und nicht nur eine Verzerrung.
 *
 * In Canvas zeigt y nach unten, daher wird der gedrehte y-Wert abgezogen.
 */
export function project(p, view, w, h) {
  const camY = view.cameraHeight || 0;
  const r = rotate(v3(p.x, p.y - camY, p.z), view.yaw, view.pitch);

  const zc = Math.max(r.z + view.distance, 0.2);
  const k = (view.fov * (Math.min(w, h) / 2)) / zc;
  return {
    x: w / 2 + r.x * k,
    y: h / 2 - r.y * k + view.offsetY,
    depth: zc,
    scale: k,
  };
}

/** Punkt-in-Polygon (Ray-Casting) in der x-z-Ebene. */
export function pointInPolygon2D(px, pz, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const xi = poly[i].x, zi = poly[i].z;
    const xj = poly[j].x, zj = poly[j].z;
    const intersect = zi > pz !== zj > pz && px < ((xj - xi) * (pz - zi)) / (zj - zi || 1e-9) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

/** Flächenschwerpunkt eines Polygons in der x-z-Ebene. */
export function centroid2D(poly) {
  let a = 0, cx = 0, cz = 0;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const cross = poly[j].x * poly[i].z - poly[i].x * poly[j].z;
    a += cross;
    cx += (poly[j].x + poly[i].x) * cross;
    cz += (poly[j].z + poly[i].z) * cross;
  }
  a *= 0.5;
  if (Math.abs(a) < 1e-9) return { x: 0, z: 0 };
  return { x: cx / (6 * a), z: cz / (6 * a) };
}

/** Sortiert Punkte nach Winkel um einen Mittelpunkt (für unregelmäßige Ringe). */
export function sortByAngle(points, center) {
  return points
    .map((p) => ({ p, a: Math.atan2(p.z - center.z, p.x - center.x) }))
    .sort((u, w) => u.a - w.a)
    .map((e) => e.p);
}
