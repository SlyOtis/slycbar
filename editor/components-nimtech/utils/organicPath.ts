export type OrganicPathEdge = "top" | "right" | "bottom" | "left";

export type OrganicPathOptions = {
  wobble?: number;
  inset?: number;
  points?: number;
  rectangular?: boolean;
  edges?: OrganicPathEdge | OrganicPathEdge[] | "vertical" | "horizontal";
};

export type ResolvedOrganicOptions = {
  wobble: number;
  inset: number;
  points: number;
  rectangular: boolean;
  activeEdges: Set<OrganicPathEdge>;
};

const EDGES: OrganicPathEdge[] = ["top", "right", "bottom", "left"];

export const getOrganicSeed = (): number => {
  const nav = navigator as Navigator & { deviceMemory?: number };
  const hw = [
    nav.hardwareConcurrency ?? 0,
    nav.deviceMemory ?? 0,
    screen.width,
    screen.height,
    screen.colorDepth,
    nav.userAgent.length,
  ].join(":");
  let h = Date.now() % 2147483647;
  for (let i = 0; i < hw.length; i++) {
    h = (h * 31 + hw.charCodeAt(i)) % 2147483647;
  }
  return h || 1;
};

export function resolveOrganicOptions(options?: OrganicPathOptions): ResolvedOrganicOptions {
  const o = options ?? {};
  let edgeList: OrganicPathEdge[];

  if (!o.edges) {
    edgeList = EDGES;
  } else if (o.edges === "vertical") {
    edgeList = ["top", "bottom"];
  } else if (o.edges === "horizontal") {
    edgeList = ["left", "right"];
  } else if (typeof o.edges === "string") {
    edgeList = [o.edges];
  } else {
    edgeList = o.edges;
  }

  return {
    wobble: o.wobble ?? 0.07,
    inset: o.inset ?? 0.01,
    points: o.points ?? 8,
    rectangular: o.rectangular ?? false,
    activeEdges: new Set(edgeList),
  };
}

function makeRand(seed: number): () => number {
  let s = Math.abs(seed) || 1;
  return () => {
    s = (s * 16807 + 0) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

function generateRectPath(seed: number, w: number, h: number, opts: ResolvedOrganicOptions): string {
  const rand = makeRand(seed);
  const min = Math.min(w, h);
  const wobble = min * opts.wobble;
  const insetPx = min * opts.inset;
  const allActive = opts.activeEdges.size === 4;
  const pointsPerEdge = Math.max(Math.round(opts.points / 4), 3);

  const phase1 = rand() * Math.PI * 2;
  const phase2 = rand() * Math.PI * 2;
  const phase3 = rand() * Math.PI * 2;
  const a1 = 0.4 + rand() * 0.3;
  const a2 = 0.2 + rand() * 0.3;
  const a3 = 0.1 + rand() * 0.2;
  const f1 = 2 + Math.floor(rand() * 2);
  const f2 = 3 + Math.floor(rand() * 2);

  function getWobble(angle: number): number {
    return (
      wobble *
      (Math.sin(angle * f1 + phase1) * a1 +
        Math.sin(angle * f2 + phase2) * a2 +
        Math.sin(angle + phase3) * a3)
    );
  }

  if (allActive) {
    const left = insetPx;
    const top = insetPx;
    const right = w - insetPx;
    const bottom = h - insetPx;
    const rw = right - left;
    const rh = bottom - top;
    const totalPoints = pointsPerEdge * 4;

    type Pt = { x: number; y: number };
    const pts: Pt[] = [];
    for (let i = 0; i < totalPoints; i++) {
      const t = i / totalPoints;
      const angle = t * Math.PI * 2;
      const r = getWobble(angle);
      const edgeIndex = Math.floor(i / pointsPerEdge);
      const edgeT = (i % pointsPerEdge) / pointsPerEdge;

      let x: number, y: number;
      switch (edgeIndex) {
        case 0: x = left + edgeT * rw; y = top + r; break;
        case 1: x = right - r; y = top + edgeT * rh; break;
        case 2: x = right - edgeT * rw; y = bottom - r; break;
        default: x = left + r; y = bottom - edgeT * rh; break;
      }
      pts.push({ x, y });
    }

    return buildSmoothPath(pts, totalPoints);
  }

  type Pt = { x: number; y: number };
  const corners: Pt[] = [
    { x: 0, y: 0 },
    { x: w, y: 0 },
    { x: w, y: h },
    { x: 0, y: h },
  ];

  const fmt = (n: number) => n.toFixed(2);
  let d = `M ${fmt(corners[0].x)} ${fmt(corners[0].y)}`;

  for (let edge = 0; edge < 4; edge++) {
    const active = opts.activeEdges.has(EDGES[edge]);
    const start = corners[edge];
    const end = corners[(edge + 1) % 4];

    if (!active) {
      d += ` L ${fmt(end.x)} ${fmt(end.y)}`;
      continue;
    }

    const prevActive = opts.activeEdges.has(EDGES[(edge + 3) % 4]);
    const nextActive = opts.activeEdges.has(EDGES[(edge + 1) % 4]);

    const pts: Pt[] = [];
    for (let i = 0; i <= pointsPerEdge; i++) {
      const t = i / pointsPerEdge;
      let taper = 1;
      if (!prevActive && t < 0.5) taper = Math.sin(t * Math.PI);
      if (!nextActive && t > 0.5) taper = Math.sin(t * Math.PI);
      const angle = ((edge + t) / 4) * Math.PI * 2;
      const r = getWobble(angle) * taper;

      const bx = start.x + (end.x - start.x) * t;
      const by = start.y + (end.y - start.y) * t;

      switch (edge) {
        case 0: pts.push({ x: bx, y: by + r }); break;
        case 1: pts.push({ x: bx - r, y: by }); break;
        case 2: pts.push({ x: bx, y: by - r }); break;
        default: pts.push({ x: bx + r, y: by }); break;
      }
    }

    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[Math.max(i - 1, 0)];
      const p1 = pts[i];
      const p2 = pts[i + 1];
      const p3 = pts[Math.min(i + 2, pts.length - 1)];

      const c1x = p1.x + (p2.x - p0.x) / 6;
      const c1y = p1.y + (p2.y - p0.y) / 6;
      const c2x = p2.x - (p3.x - p1.x) / 6;
      const c2y = p2.y - (p3.y - p1.y) / 6;

      d += ` C ${fmt(c1x)} ${fmt(c1y)} ${fmt(c2x)} ${fmt(c2y)} ${fmt(p2.x)} ${fmt(p2.y)}`;
    }
  }

  d += " Z";
  return `path('${d}')`;
}

function buildSmoothPath(pts: { x: number; y: number }[], N: number): string {
  const idx = (i: number) => ((i % N) + N) % N;

  const sx = (pts[idx(-1)].x + 4 * pts[0].x + pts[1].x) / 6;
  const sy = (pts[idx(-1)].y + 4 * pts[0].y + pts[1].y) / 6;

  let d = `M ${sx.toFixed(2)} ${sy.toFixed(2)}`;

  for (let i = 0; i < N; i++) {
    const p1 = pts[idx(i)];
    const p2 = pts[idx(i + 1)];
    const p3 = pts[idx(i + 2)];

    const c1x = (2 * p1.x + p2.x) / 3;
    const c1y = (2 * p1.y + p2.y) / 3;
    const c2x = (p1.x + 2 * p2.x) / 3;
    const c2y = (p1.y + 2 * p2.y) / 3;
    const ex = (p1.x + 4 * p2.x + p3.x) / 6;
    const ey = (p1.y + 4 * p2.y + p3.y) / 6;

    d += ` C ${c1x.toFixed(2)} ${c1y.toFixed(2)} ${c2x.toFixed(2)} ${c2y.toFixed(2)} ${ex.toFixed(2)} ${ey.toFixed(2)}`;
  }

  d += " Z";
  return `path('${d}')`;
}

export function generateOrganicPath(seed: number, w: number, h: number, opts: ResolvedOrganicOptions): string {
  if (opts.rectangular) return generateRectPath(seed, w, h, opts);

  const rand = makeRand(seed);
  const min = Math.min(w, h);
  const N = opts.points;
  const wobble = min * opts.wobble;

  const cx = w / 2;
  const cy = h / 2;
  const rx = w / 2 - min * opts.inset;
  const ry = h / 2 - min * opts.inset;

  const phase1 = rand() * Math.PI * 2;
  const phase2 = rand() * Math.PI * 2;
  const phase3 = rand() * Math.PI * 2;
  const a1 = 0.4 + rand() * 0.3;
  const a2 = 0.2 + rand() * 0.3;
  const a3 = 0.1 + rand() * 0.2;
  const f1 = 2 + Math.floor(rand() * 2);
  const f2 = 3 + Math.floor(rand() * 2);

  const pts: { x: number; y: number }[] = [];
  for (let i = 0; i < N; i++) {
    const angle = (i / N) * Math.PI * 2;
    const r =
      wobble *
      (Math.sin(angle * f1 + phase1) * a1 +
        Math.sin(angle * f2 + phase2) * a2 +
        Math.sin(angle + phase3) * a3);
    pts.push({
      x: cx + Math.cos(angle) * (rx + r),
      y: cy + Math.sin(angle) * (ry + r),
    });
  }

  return buildSmoothPath(pts, N);
}
