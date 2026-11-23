import type {
  BlockId,
  Delta,
  FontFamily,
  MarBlock,
  MarDocument,
  MarkType,
} from "../model/types";
import { deltaText, isRefOp, isTextOp, linkOf, markNames } from "../model/delta";
import { childIds, sharedText } from "../model/tree";
import { contentShapeOf } from "../model/schema";
import { escapeAttr, escapeText } from "./htmlSerialize";
import type { MarBlockLinkPreview } from "@/components/MarBlockEditor/marBlockEditor.types";

export interface MarEmailOptions {
  title?: string;
  width?: number;
  previews?: Record<string, MarBlockLinkPreview>;
}

interface EmailContext {
  width: number;
  previews: Record<string, MarBlockLinkPreview>;
}

const TEXT = "#2a2720";
const MUTED = "#8a8578";
const BORDER = "#e8e6dc";
const PANEL = "#faf9f5";
const PAGE = "#f4f2ec";
const SURFACE = "#ffffff";
const LINK = "#a44e30";
const CODE_BG = "#f4f2ec";
const FONT =
  "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";
const MONO = "'JetBrains Mono','SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace";

const fontStacks: Record<FontFamily, string> = {
  sans: FONT,
  serif: "Georgia,'Times New Roman',serif",
  mono: MONO,
  rounded: `'SF Pro Rounded',${FONT}`,
  inter: `Inter,${FONT}`,
  "source-serif": "'Source Serif 4',Georgia,'Times New Roman',serif",
  "jetbrains-mono": MONO,
  nunito: `Nunito,${FONT}`,
};

const calloutTones: Record<string, { bg: string; fg: string; border: string }> = {
  info: { bg: "#eff6ff", fg: "#1d4ed8", border: "#bfdbfe" },
  success: { bg: "#ecfdf5", fg: "#047857", border: "#a7f3d0" },
  warn: { bg: "#fffbeb", fg: "#b45309", border: "#fde68a" },
  danger: { bg: "#fef2f2", fg: "#b91c1c", border: "#fecaca" },
  neutral: { bg: PANEL, fg: TEXT, border: BORDER },
};

const headingSizes: Record<number, string> = {
  1: "30px",
  2: "24px",
  3: "20px",
  4: "17px",
  5: "15px",
  6: "14px",
};

const fontSizes: Record<string, string> = {
  sm: "12px",
  md: "15px",
  lg: "16px",
  xl: "18px",
};

const lineHeights: Record<string, string> = {
  normal: "1.6",
  tight: "1.3",
  relaxed: "1.9",
  loose: "2.3",
};

const padTops: Record<string, string> = {
  none: "0",
  sm: "8px",
  md: "16px",
  lg: "32px",
};

const option = (block: MarBlock, key: string): string =>
  String(block.options[key] ?? "");

const numberOption = (block: MarBlock, key: string): number =>
  Number(block.options[key]) || 0;

const listOption = (block: MarBlock, key: string): unknown[] =>
  Array.isArray(block.options[key]) ? (block.options[key] as unknown[]) : [];

const deltaOf = (block: MarBlock): Delta =>
  Array.isArray(block.content) ? block.content : [];

const hostOf = (url: string): string => {
  try {
    return new URL(url).host;
  } catch {
    return url;
  }
};

const markTag = (
  type: MarkType,
  href: string,
  target?: string,
  rel?: string,
): { open: string; close: string } => {
  switch (type) {
    case "bold":
      return { open: `<strong style="font-weight:700;">`, close: "</strong>" };
    case "italic":
      return { open: `<em style="font-style:italic;">`, close: "</em>" };
    case "code":
      return {
        open: `<code style="font-family:${MONO};font-size:13px;background-color:${CODE_BG};padding:1px 4px;border-radius:3px;">`,
        close: "</code>",
      };
    case "strike":
      return { open: `<s style="text-decoration:line-through;">`, close: "</s>" };
    case "link":
      return {
        open: `<a href="${escapeAttr(href)}" style="color:${LINK};text-decoration:underline;"${target ? ` target="${escapeAttr(target)}"` : ""}${rel ? ` rel="${escapeAttr(rel)}"` : ""}>`,
        close: "</a>",
      };
  }
};

const markOrder: MarkType[] = ["link", "bold", "italic", "strike", "code"];

const inlineEmail = (content: Delta): string => {
  let html = "";
  for (const op of content) {
    if (isRefOp(op)) {
      const values = op.attrs ?? {};
      if (op.insert.ref === "break") {
        html += "<br>";
        continue;
      }
      if (op.insert.ref === "image") {
        const src = escapeAttr(String(values.src ?? ""));
        const alt = escapeAttr(String(values.alt ?? ""));
        const href = String(values.href ?? "");
        const img = `<img src="${src}" alt="${alt}" style="max-width:100%;height:auto;border:0;vertical-align:middle;">`;
        html += href
          ? `<a href="${escapeAttr(href)}" style="color:${LINK};text-decoration:none;">${img}</a>`
          : img;
        continue;
      }
      const label = escapeText(String(values.label ?? ""));
      const href = String(values.href ?? "");
      html += href
        ? `<a href="${escapeAttr(href)}" style="color:${LINK};text-decoration:underline;">${label}</a>`
        : `<span style="color:${LINK};">${label}</span>`;
      continue;
    }
    if (!isTextOp(op)) continue;
    const names = markNames(op);
    const link = linkOf(op);
    let open = "";
    let close = "";
    for (const type of markOrder) {
      if (!names.includes(type)) continue;
      const tag = markTag(type, link?.href ?? "", link?.target, link?.rel);
      open += tag.open;
      close = tag.close + close;
    }
    html += open + escapeText(op.insert) + close;
  }
  return html;
};

const shell = (inner: string, style: string): string =>
  `<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;width:100%;${style}"><tr><td style="font-family:${FONT};color:${TEXT};">${inner}</td></tr></table>`;

const panel = (inner: string, bg: string, border: string): string =>
  `<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:separate;width:100%;margin:0 0 16px 0;"><tr><td style="padding:16px;background-color:${bg};border:1px solid ${border};border-radius:6px;font-family:${FONT};color:${TEXT};">${inner}</td></tr></table>`;

const kindLabel = (label: string, color: string): string =>
  `<div style="font-size:11px;letter-spacing:0.08em;text-transform:uppercase;color:${color};margin:0 0 6px 0;">${escapeText(label)}</div>`;

const linkPanel = (
  kind: string,
  label: string,
  href: string,
  sub: string,
): string => {
  const head = href
    ? `<a href="${escapeAttr(href)}" style="color:${LINK};text-decoration:underline;font-weight:600;font-size:15px;">${escapeText(label)}</a>`
    : `<span style="font-weight:600;font-size:15px;color:${TEXT};">${escapeText(label)}</span>`;
  const tail = sub
    ? `<div style="margin:4px 0 0 0;font-size:13px;color:${MUTED};word-break:break-word;">${escapeText(sub)}</div>`
    : "";
  return panel(kindLabel(kind, MUTED) + head + tail, PANEL, BORDER);
};

const textPanel = (kind: string, lines: string[]): string => {
  const body = lines
    .filter(Boolean)
    .map(
      (line) =>
        `<div style="font-size:15px;color:${TEXT};margin:0 0 4px 0;">${escapeText(line)}</div>`,
    )
    .join("");
  return panel(kindLabel(kind, MUTED) + body, PANEL, BORDER);
};

const bulletPanel = (kind: string, title: string, items: string[]): string => {
  const head = title
    ? `<div style="font-weight:600;font-size:15px;color:${TEXT};margin:0 0 8px 0;">${escapeText(title)}</div>`
    : "";
  const list = items.length
    ? `<ul style="margin:0;padding:0 0 0 20px;font-size:15px;color:${TEXT};">${items
        .map((item) => `<li style="margin:0 0 4px 0;">${escapeText(item)}</li>`)
        .join("")}</ul>`
    : "";
  return panel(kindLabel(kind, MUTED) + head + list, PANEL, BORDER);
};

const childrenTight = (
  doc: MarDocument,
  block: MarBlock,
  ctx: EmailContext,
): string => {
  const ids = childIds(block);
  return ids
    .map((childId, index) => blockEmail(doc, childId, ctx, index === ids.length - 1))
    .join("");
};

const captionOf = (block: MarBlock): string => {
  const caption = inlineEmail(deltaOf(block));
  return caption
    ? `<div style="margin:8px 0 0 0;font-size:13px;color:${MUTED};font-family:${FONT};">${caption}</div>`
    : "";
};

const bookmarkEmail = (block: MarBlock, ctx: EmailContext): string => {
  const url = option(block, "url");
  const preview = ctx.previews[url];
  if (!preview) return linkPanel("Link", url || "Link", url, "");
  const title = preview.title || url || "Link";
  const site = preview.siteName || hostOf(url);
  const image = preview.imageUrl
    ? `<a href="${escapeAttr(url)}" style="text-decoration:none;"><img src="${escapeAttr(preview.imageUrl)}" alt="${escapeAttr(title)}" width="100%" style="display:block;width:100%;max-width:100%;height:auto;border:0;border-radius:4px;margin:0 0 12px 0;"></a>`
    : "";
  const description = preview.description
    ? `<div style="margin:6px 0 0 0;font-size:14px;line-height:1.5;color:${MUTED};">${escapeText(preview.description)}</div>`
    : "";
  const foot = `<div style="margin:10px 0 0 0;font-size:12px;color:${MUTED};word-break:break-word;">${escapeText(site)}</div>`;
  const head = `<a href="${escapeAttr(url)}" style="color:${LINK};text-decoration:underline;font-weight:600;font-size:16px;">${escapeText(title)}</a>`;
  return panel(image + head + description + foot, SURFACE, BORDER);
};

const imageEmail = (block: MarBlock): string => {
  const src = option(block, "src");
  if (!src) return "";
  const align = option(block, "align") || "center";
  const height = numberOption(block, "height");
  const size = height ? `height:${height}px;` : "height:auto;";
  return `<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;width:100%;margin:0 0 16px 0;"><tr><td align="${escapeAttr(align)}" style="font-family:${FONT};"><img src="${escapeAttr(src)}" alt="" style="display:block;max-width:100%;border:0;${size}"></td></tr></table>`;
};

const imageGridEmail = (block: MarBlock): string => {
  const images = listOption(block, "images").map(String).filter(Boolean);
  const caption = captionOf(block);
  if (!images.length) return caption ? shell(caption, "margin:0 0 16px 0;") : "";
  const columns = Math.max(1, numberOption(block, "columns") || 1);
  const gap = numberOption(block, "gap");
  const radius = numberOption(block, "radius");
  const cellWidth = Math.floor(100 / columns);
  const rows: string[] = [];
  for (let index = 0; index < images.length; index += columns) {
    const slice = images.slice(index, index + columns);
    const cells = slice
      .map(
        (src) =>
          `<td width="${cellWidth}%" valign="top" style="padding:${gap / 2}px;"><img src="${escapeAttr(src)}" alt="" width="100%" style="display:block;width:100%;max-width:100%;height:auto;border:0;border-radius:${radius}px;"></td>`,
      )
      .join("");
    const filler = "<td></td>".repeat(columns - slice.length);
    rows.push(`<tr>${cells}${filler}</tr>`);
  }
  return `<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;width:100%;margin:0 0 16px 0;">${rows.join("")}</table>${caption}`;
};

const countdownEmail = (block: MarBlock): string => {
  const target = option(block, "target");
  const parsed = target ? new Date(target) : null;
  const moment =
    parsed && !Number.isNaN(parsed.getTime()) ? parsed.toUTCString() : target;
  const body = moment
    ? `<div style="font-size:20px;font-weight:700;color:${TEXT};">${escapeText(moment)}</div>`
    : "";
  return panel(kindLabel("Countdown", MUTED) + body + captionOf(block), PANEL, BORDER);
};

const calloutEmail = (doc: MarDocument, block: MarBlock, ctx: EmailContext): string => {
  const tone = calloutTones[option(block, "variant")] ?? calloutTones.info;
  const inner = childIds(block)
    .map((childId) => blockEmail(doc, childId, ctx))
    .join("");
  return panel(kindLabel(option(block, "variant") || "info", tone.fg) + inner, tone.bg, tone.border);
};

const tableEmail = (doc: MarDocument, block: MarBlock, ctx: EmailContext): string => {
  const rows = childIds(block)
    .map((rowId) => {
      const row = doc.blocks[rowId];
      if (!row) return "";
      const cells = childIds(row)
        .map((cellId) => {
          const cell = doc.blocks[cellId];
          if (!cell) return "";
          const tag = cell.kind === "tableHeader" ? "th" : "td";
          const colspan = numberOption(cell, "colspan");
          const rowspan = numberOption(cell, "rowspan");
          const span =
            (colspan > 1 ? ` colspan="${colspan}"` : "") +
            (rowspan > 1 ? ` rowspan="${rowspan}"` : "");
          const weight = tag === "th" ? "font-weight:700;" : "font-weight:400;";
          const background = tag === "th" ? `background-color:${PANEL};` : "";
          const inner = childrenTight(doc, cell, ctx);
          return `<${tag}${span} valign="top" style="border:1px solid ${BORDER};padding:8px 10px;text-align:${escapeAttr(option(block, "textAlign") || "left")};${weight}${background}font-family:${FONT};font-size:14px;color:${TEXT};">${inner}</${tag}>`;
        })
        .join("");
      return `<tr>${cells}</tr>`;
    })
    .join("");
  return `<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;width:100%;margin:0 0 16px 0;"><tbody>${rows}</tbody></table>`;
};

const columnListEmail = (doc: MarDocument, block: MarBlock, ctx: EmailContext): string => {
  const columns = childIds(block)
    .map((id) => doc.blocks[id])
    .filter((column): column is MarBlock => column !== undefined);
  if (!columns.length) return "";
  const total = columns.reduce(
    (sum, column) => sum + Math.max(1, numberOption(column, "span") || 1),
    0,
  );
  const cells = columns
    .map((column) => {
      const span = Math.max(1, numberOption(column, "span") || 1);
      const width = Math.floor((span / total) * 100);
      const inner = childIds(column)
        .map((childId) => blockEmail(doc, childId, ctx))
        .join("");
      return `<td width="${width}%" valign="top" style="padding:0 8px 0 0;font-family:${FONT};color:${TEXT};">${inner}</td>`;
    })
    .join("");
  return `<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;width:100%;margin:0 0 16px 0;"><tr>${cells}</tr></table>`;
};

const headingIds = (doc: MarDocument, ids: BlockId[], out: MarBlock[]): void => {
  for (const id of ids) {
    const block = doc.blocks[id];
    if (!block) continue;
    if (block.kind === "heading") out.push(block);
    headingIds(doc, childIds(block), out);
  }
};

const tableOfContentsEmail = (doc: MarDocument, block: MarBlock): string => {
  const found: MarBlock[] = [];
  headingIds(doc, doc.root, found);
  const items = found
    .map((heading) => {
      const level = Math.min(6, Math.max(1, numberOption(heading, "level") || 1));
      const text = deltaText(deltaOf(heading));
      if (!text) return "";
      return `<div style="margin:0 0 6px 0;padding-left:${(level - 1) * 16}px;font-size:14px;color:${TEXT};">${escapeText(text)}</div>`;
    })
    .filter(Boolean)
    .join("");
  const title =
    block.options.showTitle === false
      ? ""
      : `<div style="font-weight:700;font-size:16px;margin:0 0 10px 0;color:${TEXT};">Contents</div>`;
  return panel(title + items, PANEL, BORDER);
};

const listEmail = (doc: MarDocument, block: MarBlock, ctx: EmailContext): string => {
  const ordered = block.kind === "orderedList";
  const task = block.kind === "taskList";
  const tag = ordered ? "ol" : "ul";
  const listStyle = task
    ? "list-style:none;"
    : ordered
      ? `list-style:${escapeAttr(option(block, "listStyle") || "decimal")};`
      : "list-style:disc;";
  const items = childIds(block)
    .map((itemId) => {
      const item = doc.blocks[itemId];
      if (!item) return "";
      const inner = childrenTight(doc, item, ctx);
      const box = task
        ? `<span style="color:${MUTED};margin-right:6px;">${item.options.checked === true ? "[x]" : "[ ]"}</span>`
        : "";
      return `<li style="margin:0 0 6px 0;font-family:${FONT};font-size:15px;line-height:1.6;color:${TEXT};">${box}${inner}</li>`;
    })
    .join("");
  return `<${tag} style="margin:0 0 16px 0;padding:0 0 0 24px;${listStyle}">${items}</${tag}>`;
};

const paragraphEmail = (doc: MarDocument, block: MarBlock, tight: boolean): string => {
  const inner = inlineEmail(deltaOf(block));
  const text = sharedText(doc, block.id);
  const align = option(block, "align") || "left";
  const family = fontStacks[text.fontFamily] ?? FONT;
  const size = fontSizes[text.fontSize] ?? fontSizes.md;
  const height = lineHeights[text.lineHeight] ?? lineHeights.normal;
  const pad = padTops[option(block, "padTop")] ?? padTops.none;
  const margin = tight ? "0" : "0 0 12px 0";
  return `<p style="margin:${margin};padding-top:${pad};font-family:${family};font-size:${size};line-height:${height};color:${TEXT};text-align:${escapeAttr(align)};">${inner || "&nbsp;"}</p>`;
};

const headingEmail = (block: MarBlock): string => {
  const level = Math.min(6, Math.max(1, numberOption(block, "level") || 1));
  return `<h${level} style="margin:20px 0 10px 0;font-family:${FONT};font-size:${headingSizes[level]};font-weight:700;line-height:1.3;color:${TEXT};">${inlineEmail(deltaOf(block))}</h${level}>`;
};

const blockEmail = (
  doc: MarDocument,
  id: BlockId,
  ctx: EmailContext,
  tight = false,
): string => {
  const block = doc.blocks[id];
  if (!block) return "";
  const children = (): string =>
    childIds(block)
      .map((childId) => blockEmail(doc, childId, ctx))
      .join("");

  switch (block.kind) {
    case "paragraph":
      return paragraphEmail(doc, block, tight);
    case "heading":
      return headingEmail(block);
    case "titleBlock":
      return `<h1 style="margin:0 0 16px 0;font-family:${FONT};font-size:40px;font-weight:800;line-height:1.2;letter-spacing:-0.01em;color:${TEXT};">${inlineEmail(deltaOf(block))}</h1>`;
    case "blockquote":
      return panel(
        `<div style="font-style:italic;color:${TEXT};">${children()}</div>`,
        PANEL,
        BORDER,
      );
    case "bulletList":
    case "orderedList":
    case "taskList":
      return listEmail(doc, block, ctx);
    case "listItem":
    case "taskItem":
      return children();
    case "codeBlock":
      return panel(
        `<pre style="margin:0;font-family:${MONO};font-size:13px;line-height:1.5;color:${TEXT};white-space:pre-wrap;word-break:break-word;">${escapeText(deltaText(deltaOf(block)))}</pre>`,
        CODE_BG,
        BORDER,
      );
    case "html":
      return shell(String(block.options.html ?? ""), "margin:0 0 16px 0;");
    case "horizontalRule":
      return `<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;width:100%;margin:20px 0;"><tr><td height="1" style="height:1px;line-height:1px;font-size:0;background-color:${BORDER};">&nbsp;</td></tr></table>`;
    case "image":
      return imageEmail(block);
    case "imageGrid":
      return imageGridEmail(block);
    case "table":
      return tableEmail(doc, block, ctx);
    case "callout":
      return calloutEmail(doc, block, ctx);
    case "tableOfContents":
      return tableOfContentsEmail(doc, block);
    case "columnList":
      return columnListEmail(doc, block, ctx);
    case "column":
      return children();
    case "toggle": {
      const summary = option(block, "summary");
      const head = summary
        ? `<div style="font-weight:600;font-size:15px;color:${TEXT};margin:0 0 8px 0;">${escapeText(summary)}</div>`
        : "";
      return panel(head + children(), PANEL, BORDER);
    }
    case "section": {
      const heading = option(block, "heading");
      const head = heading
        ? `<h2 style="margin:20px 0 10px 0;font-family:${FONT};font-size:24px;font-weight:700;color:${TEXT};">${escapeText(heading)}</h2>`
        : "";
      return head + children();
    }
    case "template":
      return contentShapeOf(block) === "slot"
        ? children()
        : paragraphEmail(doc, block, tight);
    case "video":
      return linkPanel("Video", option(block, "name") || "Watch the video", option(block, "src"), option(block, "src"));
    case "audio":
      return linkPanel(
        "Audio",
        option(block, "title") || option(block, "name") || "Listen",
        option(block, "src"),
        option(block, "description") || option(block, "src"),
      );
    case "pdf":
      return linkPanel("PDF", option(block, "name") || "Open the document", option(block, "src"), option(block, "src"));
    case "file":
      return linkPanel("File", option(block, "name") || "Open the file", option(block, "url"), option(block, "mimeType"));
    case "embed":
      return linkPanel("Embed", option(block, "url") || "Open", option(block, "url"), "");
    case "pageBlock":
      return linkPanel("Page", option(block, "label") || "Page", "", "");
    case "bookmark":
    case "linkPreview":
      return bookmarkEmail(block, ctx);
    case "meetingNotes":
      return textPanel("Meeting notes", [option(block, "transcript")]);
    case "map":
      return textPanel("Map", [
        option(block, "label"),
        option(block, "address") ||
          `${numberOption(block, "lat")}, ${numberOption(block, "lng")}`,
      ]);
    case "weather":
      return textPanel("Weather", [
        option(block, "label"),
        option(block, "address") ||
          `${numberOption(block, "lat")}, ${numberOption(block, "lng")}`,
      ]);
    case "textInput":
      return textPanel("Question", [option(block, "label")]);
    case "choiceInput":
      return bulletPanel(
        "Question",
        option(block, "label"),
        listOption(block, "options").map(String),
      );
    case "ratingInput":
      return textPanel("Rating", [
        option(block, "label"),
        `1 to ${numberOption(block, "max") || 5}`,
      ]);
    case "poll":
      return bulletPanel(
        "Poll",
        option(block, "question"),
        listOption(block, "options").map(String),
      );
    case "countdown":
      return countdownEmail(block);
    default:
      return contentShapeOf(block) === "slot"
        ? children()
        : paragraphEmail(doc, block, tight);
  }
};

export const marDocumentToEmailHtml = (
  doc: MarDocument,
  options: MarEmailOptions = {},
): string => {
  const ctx: EmailContext = {
    width: options.width ?? 600,
    previews: options.previews ?? {},
  };
  const body = doc.root.map((id) => blockEmail(doc, id, ctx)).join("");
  const title = escapeText(options.title ?? "");
  return (
    `<!doctype html><html><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1">` +
    `<title>${title}</title></head>` +
    `<body style="margin:0;padding:0;background-color:${PAGE};">` +
    `<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;width:100%;background-color:${PAGE};">` +
    `<tr><td align="center" style="padding:24px 12px;">` +
    `<table role="presentation" border="0" cellpadding="0" cellspacing="0" width="${ctx.width}" style="border-collapse:collapse;width:100%;max-width:${ctx.width}px;background-color:${SURFACE};border-radius:8px;">` +
    `<tr><td style="padding:32px;font-family:${FONT};font-size:15px;line-height:1.6;color:${TEXT};">${body}</td></tr>` +
    `</table></td></tr></table></body></html>`
  );
};
