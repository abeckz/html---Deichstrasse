/**
 * Vektor- und Geometriehelfer sowie eine echte Kamera für die 3D-Szene.
 *
 * Koordinatensystem: x nach rechts, y nach oben, z in die Tiefe.
 * Die Grundfläche der Polygone liegt in der x-z-Ebene bei y = 0.
 *
 * Für den Blick von schräg oben gibt es `makeLookAtCamera`: sie erzeugt aus
 * einem echten Kamerastandort und einem Blickziel die drei Achsen
 * (right, up, forward) und projiziert damit korrekt. Damit ist "von oben"
 * eine Eigenschaft der Kameraposition und keine Einstellungssache.
 */

export const v3 = (x = 0, y = 0, z = 0) => ({ x, y, z });

export const sub = (a, b) => v3(a.x - b.x, a.y - b.y, a.z - b.z);
export const add = (a, b) => v3(a.x + b.x, a.y + b.y, a.z + b.z);
export const scale = (a, s) => v3(a.x * s, a.y * s, a.z * s);
export const len = (a) => Math.hypot(a.x, a.y, a.z);
export const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z);

export function norm(a) {
  const l = len(a) || 1;
  return v3(a.x / l, a.y / l, a.z / l);
}

export function cross(a, b) {
  return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

export function dot(a, b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}

export function lerp3(a, b, t) {
  return v3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
}

/**
 * Erzeugt eine Kamera, die von `eye` auf `target` blickt.
 *
 * Die Kamera schaut entlang der positiven forward-Achse. `upHint` gibt die
 * ungefähre Hochrichtung an; daraus werden right und up orthogonal berechnet.
 */
export function makeLookAtCamera(eye, target, upHint = v3(0, 1, 0), fov = 1.34) {
  const forward = norm(sub(target, eye));
  let up = norm(upHint);

  // right = forward x up  (zeigt nach rechts im Bild)
  let right = cross(forward, up);
  if (len(right) < 1e-6) {
    // Sonderfall: Blick fast parallel zu up, anderes up verwenden
    up = v3(0, 0, 1);
    right = cross(forward, up);
  }
  right = norm(right);
  // up neu berechnen, damit alle drei Achsen exakt senkrecht stehen
  up = norm(cross(right, forward));

  return { eye, forward, right, up, fov };
}

/**
 * Projiziert einen Weltpunkt mit einer echten Kamera.
 *
 * 1. Vektor von der Kamera zum Punkt bilden.
 * 2. In Kameraachsen zerlegen: rechts, oben, in Blickrichtung.
 * 3. Perspektivisch teilen: weiter entfernte Punkte werden kleiner.
 *
 * In Canvas zeigt y nach unten, daher wird die Bild-Y-Koordinate negiert.
 */
export function projectWithCamera(p, cam, w, h, panX = 0, panY = 0) {
  const d = sub(p, cam.eye);
  const cx = dot(d, cam.right);
  const cy = dot(d, cam.up);
  const cz = dot(d, cam.forward);

  // Punkte hinter der Kamera abfangen, sonst entstehen Spiegelbilder.
  const safeZ = Math.max(cz, 0.05);
  const k = (cam.fov * (Math.min(w, h) / 2)) / safeZ;

  return {
    x: w / 2 + cx * k + panX,
    y: h / 2 - cy * k + panY,
    depth: safeZ,
    scale: k,
    inFront: cz > 0.05,
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
    const crossV = poly[j].x * poly[i].z - poly[i].x * poly[j].z;
    a += crossV;
    cx += (poly[j].x + poly[i].x) * crossV;
    cz += (poly[j].z + poly[i].z) * crossV;
  }
  a *= 0.5;
  if (Math.abs(a) < 1e-9) return { x: 0, z: 0 };
  return { x: cx / (6 * a), z: cz / (6 * a) };
}

/** Sortiert Punkte nach Winkel um einen Mittelpunkt. */
export function sortByAngle(points, center) {
  return points
    .map((p) => ({ p, a: Math.atan2(p.z - center.z, p.x - center.x) }))
    .sort((u, w) => u.a - w.a)
    .map((e) => e.p);
}
