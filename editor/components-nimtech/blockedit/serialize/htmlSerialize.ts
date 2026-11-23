import type { Delta, MarBlock, MarDocument, MarkType } from "../model/types";
import { deltaText, isRefOp, isTextOp, linkOf, markNames } from "../model/delta";
import { childIds } from "../model/tree";
import { contentShapeOf, isTextKind } from "../model/schema";
import { specByType, mentionAttrs, type AttrSpec } from "./domSpec";

export const escapeText = (text: string): string =>
  text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");

export const escapeAttr = (value: string): string =>
  value.replace(/&/g, "&amp;").replace(/"/g, "&quot;");

const markOrder: MarkType[] = ["link", "bold", "italic", "strike", "code"];

const markTag = (
  type: MarkType,
  href: string,
  target?: string,
  rel?: string,
): { open: string; close: string } => {
  switch (type) {
    case "bold":
      return { open: "<strong>", close: "</strong>" };
    case "italic":
      return { open: "<em>", close: "</em>" };
    case "code":
      return { open: "<code>", close: "</code>" };
    case "strike":
      return { open: "<s>", close: "</s>" };
    case "link":
      return {
        open: `<a href="${escapeAttr(href)}"${target ? ` target="${escapeAttr(target)}"` : ""}${rel ? ` rel="${escapeAttr(rel)}"` : ""}>`,
        close: "</a>",
      };
  }
};

const renderAttrs = (
  options: Record<string, unknown>,
  specs: AttrSpec[],
): string => {
  const out: string[] = [];
  for (const spec of specs) {
    const rendered = spec.render(options[spec.name]);
    if (!rendered) continue;
    for (const [key, value] of Object.entries(rendered)) {
      out.push(` ${key}="${escapeAttr(value)}"`);
    }
  }
  return out.join("");
};

export const mentionDeclared = (type: unknown, declared?: string[]): boolean =>
  !declared?.length || (typeof type === "string" && declared.includes(type));

export const serializeInline = (
  content: Delta,
  display = false,
  mentionTypes?: string[],
): string => {
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
        const href = values.href ? String(values.href) : "";
        const hrefAttr = href ? ` data-href="${escapeAttr(href)}"` : "";
        const img = `<img data-type="inline-image" class="mar-be-inline-image" src="${src}" alt="${alt}"${hrefAttr}>`;
        html += display && href ? `<a href="${escapeAttr(href)}" target="_blank" rel="noopener">${img}</a>` : img;
        continue;
      }
      const attrs = renderAttrs(values, mentionAttrs);
      if (display) {
        const label = escapeText(String(values.label ?? ""));
        const linkClass =
          values.href && mentionDeclared(values.type, mentionTypes)
            ? " mar-be-mention-link"
            : "";
        html += `<span data-type="mention" class="mar-be-mention${linkClass}" contenteditable="false"${attrs}><span class="mar-be-mention-icon"></span><span class="mar-be-mention-label">${label}</span></span>`;
      } else {
        html += `<span data-type="mention"${attrs}></span>`;
      }
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
    const text =
      display && op === content[content.length - 1]
        ? op.insert.replace(/ +$/, (m) => " ".repeat(m.length))
        : op.insert;
    html += open + escapeText(text) + close;
  }
  return html;
};

const serializeImage = (block: MarBlock): string => {
  const o = block.options;
  const parts: string[] = [`src="${escapeAttr(String(o.src ?? ""))}"`];
  parts.push(`data-align="${escapeAttr(String(o.align ?? "center"))}"`);
  parts.push(`data-fit="${o.fit === false ? "0" : "1"}"`);
  parts.push(`data-object-fit="${escapeAttr(String(o.objectFit ?? "cover"))}"`);
  const style = o.height ? ` style="height:${Number(o.height)}px"` : "";
  return `<div class="mar-image"><img ${parts.join(" ")}${style}></div>`;
};

const serializeCodeBlock = (block: MarBlock): string => {
  const lang = String(block.options.language ?? "plaintext");
  const text = escapeText(deltaText((block.content as Delta | null) ?? []));
  const lineNumbers = block.options.lineNumbers === false ? ` data-line-numbers="false"` : "";
  const lineWrap = block.options.lineWrap === true ? ` data-line-wrap="true"` : "";
  return `<pre${lineNumbers}${lineWrap}><code class="language-${escapeAttr(lang)}">${text}</code></pre>`;
};

const serializeTaskItem = (doc: MarDocument, block: MarBlock): string => {
  const checked = block.options.checked === true;
  const label = `<label><input type="checkbox"${checked ? " checked" : ""}><span></span></label>`;
  const body = `<div>${childIds(block).map((id) => serializeBlock(doc, id)).join("")}</div>`;
  return `<li data-checked="${checked ? "true" : "false"}" data-type="taskItem">${label}${body}</li>`;
};

const serializeHtmlBlock = (block: MarBlock): string => {
  const source = block.options.source === true ? ` data-source="true"` : "";
  return `<div data-type="html"${source}>${String(block.options.html ?? "")}</div>`;
};

export const serializeBlock = (doc: MarDocument, id: string): string => {
  const block = doc.blocks[id];
  if (!block) return "";
  if (block.kind === "image") return serializeImage(block);
  if (block.kind === "codeBlock") return serializeCodeBlock(block);
  if (block.kind === "html") return serializeHtmlBlock(block);
  if (block.kind === "taskItem") return serializeTaskItem(doc, block);

  const spec = specByType.get(block.kind);
  if (!spec) return "";

  const shared =
    (block.edit !== "open" ? ` data-edit-mode="${escapeAttr(block.edit)}"` : "") +
    (block.read !== "document" ? ` data-read-mode="${escapeAttr(block.read)}"` : "") +
    (block.inherits
      ? ""
      : ` data-ff="${escapeAttr(block.fontFamily)}" data-fs="${escapeAttr(block.fontSize)}" data-lh="${escapeAttr(block.lineHeight)}"`);

  if (block.kind === "heading") {
    const level = Number(block.options.level ?? 1);
    const attrs = renderAttrs(block.options, spec.attrs);
    return `<h${level}${attrs}${shared}>${serializeInline((block.content as Delta | null) ?? [])}</h${level}>`;
  }

  if (spec.tag === "hr") return "<hr>";

  const dataType = spec.dataType ? ` data-type="${spec.dataType}"` : "";
  const attrs = renderAttrs(block.options, spec.attrs);
  const shape = contentShapeOf(block);

  if (shape === "none" || (shape === "delta" && !isTextKind(block.kind))) {
    return `<${spec.tag}${dataType}${attrs}${shared}></${spec.tag}>`;
  }

  let inner: string;
  if (shape === "delta") {
    inner = serializeInline((block.content as Delta | null) ?? []);
  } else if (block.kind === "table") {
    inner = `<tbody>${childIds(block).map((childId) => serializeBlock(doc, childId)).join("")}</tbody>`;
  } else {
    inner = childIds(block).map((childId) => serializeBlock(doc, childId)).join("");
  }
  return `<${spec.tag}${dataType}${attrs}${shared}>${inner}</${spec.tag}>`;
};

export const marDocumentToHtml = (doc: MarDocument): string =>
  doc.root.map((id) => serializeBlock(doc, id)).join("");
