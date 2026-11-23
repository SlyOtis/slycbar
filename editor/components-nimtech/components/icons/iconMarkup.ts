export interface IconMarkup {
  attrs: Record<string, string>;
  inner: string;
}

export function parseIcon(raw: string): IconMarkup {
  const open = raw.match(/<svg\b([^>]*)>/i);
  const attrs: Record<string, string> = {};
  if (open) {
    const re = /([\w:-]+)="([^"]*)"/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(open[1])) !== null) {
      if (m[1] === "width" || m[1] === "height" || m[1] === "class") continue;
      attrs[m[1]] = m[2];
    }
  }
  const inner = raw
    .replace(/^[\s\S]*?<svg\b[^>]*>/i, "")
    .replace(/<\/svg>\s*$/i, "")
    .trim();
  return { attrs, inner };
}

const svgElements = new Set([
  "svg",
  "g",
  "defs",
  "symbol",
  "use",
  "title",
  "desc",
  "path",
  "circle",
  "ellipse",
  "line",
  "polyline",
  "polygon",
  "rect",
  "text",
  "tspan",
  "linearGradient",
  "radialGradient",
  "stop",
  "clipPath",
  "mask",
  "pattern",
]);

const svgAttributes = new Set([
  "viewBox",
  "preserveAspectRatio",
  "xmlns",
  "xmlns:xlink",
  "version",
  "id",
  "d",
  "x",
  "y",
  "x1",
  "y1",
  "x2",
  "y2",
  "cx",
  "cy",
  "r",
  "rx",
  "ry",
  "fx",
  "fy",
  "dx",
  "dy",
  "width",
  "height",
  "points",
  "pathLength",
  "transform",
  "fill",
  "fill-rule",
  "fill-opacity",
  "stroke",
  "stroke-width",
  "stroke-linecap",
  "stroke-linejoin",
  "stroke-miterlimit",
  "stroke-dasharray",
  "stroke-dashoffset",
  "stroke-opacity",
  "opacity",
  "color",
  "clip-path",
  "clip-rule",
  "mask",
  "display",
  "visibility",
  "vector-effect",
  "paint-order",
  "offset",
  "stop-color",
  "stop-opacity",
  "gradientUnits",
  "gradientTransform",
  "spreadMethod",
  "patternUnits",
  "patternContentUnits",
  "patternTransform",
  "maskUnits",
  "maskContentUnits",
  "clipPathUnits",
  "font-family",
  "font-size",
  "font-weight",
  "font-style",
  "text-anchor",
  "dominant-baseline",
  "letter-spacing",
  "style",
  "href",
  "xlink:href",
]);

const unsafeValue = /javascript:|vbscript:|data:|expression\s*\(|@import|url\(\s*["']?(?!#)/i;

function cleanSvgNode(el: Element): void {
  for (const attr of Array.from(el.attributes)) {
    const keep =
      svgAttributes.has(attr.name) &&
      !unsafeValue.test(attr.value) &&
      (!attr.name.endsWith("href") || attr.value.trim().startsWith("#"));
    if (!keep) el.removeAttribute(attr.name);
  }
  for (const child of Array.from(el.childNodes)) {
    if (child.nodeType === 1) {
      if (svgElements.has((child as Element).localName) && (child as Element).localName !== "svg") cleanSvgNode(child as Element);
      else child.remove();
    } else if (child.nodeType !== 3) child.remove();
  }
}

export function sanitizeSvg(raw: string): string | null {
  if (typeof DOMParser === "undefined") return null;
  const doc = new DOMParser().parseFromString(raw.trim(), "image/svg+xml");
  const root = doc.documentElement;
  if (root.localName !== "svg" || doc.getElementsByTagName("parsererror").length) return null;
  cleanSvgNode(root);
  const width = parseFloat(root.getAttribute("width") ?? "");
  const height = parseFloat(root.getAttribute("height") ?? "");
  if (!root.hasAttribute("viewBox") && width > 0 && height > 0) root.setAttribute("viewBox", `0 0 ${width} ${height}`);
  if (!root.hasAttribute("fill")) root.setAttribute("fill", "currentColor");
  return new XMLSerializer().serializeToString(root);
}
