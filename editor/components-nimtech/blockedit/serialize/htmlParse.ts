import type {
  BlockId,
  Delta,
  EditMode,
  FontFamily,
  FontSize,
  LineHeight,
  MarBlock,
  MarBlockKind,
  MarDocument,
  Marks,
  ReadMode,
} from "../model/types";
import { textOp, refOp } from "../model/delta";
import { makeBlock, makeDocument, contentShapeOf, isTextKind } from "../model/schema";
import { fitBlocks } from "../model/normalize";
import { specByType, mentionAttrs, type AttrSpec } from "./domSpec";

type Blocks = Record<BlockId, MarBlock>;

const markFromEl = (el: HTMLElement): Marks | null => {
  const tag = el.tagName.toLowerCase();
  if (tag === "strong" || tag === "b") return { bold: true };
  if (tag === "em" || tag === "i") return { italic: true };
  if (tag === "code") return { code: true };
  if (tag === "s" || tag === "del" || tag === "strike") return { strike: true };
  if (tag === "a") {
    return {
      link: {
        href: el.getAttribute("href") ?? "",
        target: el.getAttribute("target") ?? undefined,
        rel: el.getAttribute("rel") ?? undefined,
      },
    };
  }
  return null;
};

const readAttrs = (el: HTMLElement, specs: AttrSpec[]): Record<string, unknown> => {
  const out: Record<string, unknown> = {};
  for (const spec of specs) out[spec.name] = spec.parse(el);
  return out;
};

const parseInlineNode = (node: ChildNode, marks: Marks, out: Delta): void => {
  if (node.nodeType === 3) {
    const text = (node.textContent ?? "").replace(/ /g, " ");
    if (text) out.push(textOp(text, marks));
    return;
  }
  if (node.nodeType !== 1) return;
  const el = node as HTMLElement;
  if (el.tagName.toLowerCase() === "br") {
    if (!el.hasAttribute("data-filler")) out.push(refOp("break"));
    return;
  }
  if (el.tagName.toLowerCase() === "span" && el.getAttribute("data-type") === "mention") {
    out.push(refOp("mention", readAttrs(el, mentionAttrs)));
    return;
  }
  if (el.tagName.toLowerCase() === "img" && el.getAttribute("data-type") === "inline-image") {
    out.push(
      refOp("image", {
        src: el.getAttribute("src") ?? "",
        alt: el.getAttribute("alt") ?? "",
        href: el.getAttribute("data-href") ?? "",
      }),
    );
    return;
  }
  const mark = markFromEl(el);
  parseInline(el, mark ? { ...marks, ...mark } : marks, out);
};

const parseInline = (parent: HTMLElement, marks: Marks, out: Delta): void => {
  parent.childNodes.forEach((node) => parseInlineNode(node, marks, out));
};

export const inlineOf = (el: HTMLElement): Delta => {
  const out: Delta = [];
  parseInline(el, {}, out);
  return out;
};

const kindByTag = new Map(
  [...specByType.values()]
    .filter((spec) => !spec.dataType && spec.tag !== "h" && spec.tag !== "div")
    .map((spec) => [spec.tag, spec.type] as const),
);

const kindByDataType = new Map(
  [...specByType.values()]
    .filter((spec) => !!spec.dataType)
    .map((spec) => [`${spec.tag}|${spec.dataType}`, spec.type] as const),
);

const resolveKind = (el: HTMLElement): string | null => {
  const tag = el.tagName.toLowerCase();
  const dataType = el.getAttribute("data-type");
  if (tag === "img") return "image";
  if (tag === "div" && el.classList.contains("mar-image")) return "image";
  if (/^h[1-6]$/.test(tag)) return dataType === "title" ? "titleBlock" : "heading";
  if (dataType) {
    const byDataType = kindByDataType.get(`${tag}|${dataType}`);
    if (byDataType) return byDataType;
  }
  return kindByTag.get(tag) ?? null;
};

const isWhitespace = (node: ChildNode): boolean =>
  node.nodeType === 3 && !(node.textContent ?? "").trim();

const put = (blocks: Blocks, block: MarBlock): BlockId => {
  blocks[block.id] = block;
  return block.id;
};

const withShared = (block: MarBlock, el: HTMLElement): MarBlock => {
  const edit = el.getAttribute("data-edit-mode");
  const read = el.getAttribute("data-read-mode");
  const fontFamily = el.getAttribute("data-ff");
  const fontSize = el.getAttribute("data-fs");
  const lineHeight = el.getAttribute("data-lh");
  const owns = !!(fontFamily || fontSize || lineHeight);
  return {
    ...block,
    edit: (edit as EditMode | null) ?? block.edit,
    read: (read as ReadMode | null) ?? block.read,
    inherits: owns ? false : block.inherits,
    fontFamily: (fontFamily as FontFamily | null) ?? block.fontFamily,
    fontSize: (fontSize as FontSize | null) ?? block.fontSize,
    lineHeight: (lineHeight as LineHeight | null) ?? block.lineHeight,
  };
};

const childIdsOf = (parent: HTMLElement, blocks: Blocks): BlockId[] => {
  const ids: BlockId[] = [];
  let pending: Delta = [];
  const flush = (): void => {
    if (!pending.length) return;
    ids.push(put(blocks, makeBlock("paragraph", {}, pending)));
    pending = [];
  };
  parent.childNodes.forEach((node) => {
    const isBlockEl = node.nodeType === 1 && resolveKind(node as HTMLElement) != null;
    if (isBlockEl) {
      flush();
      const id = parseBlock(node as HTMLElement, blocks);
      if (id) ids.push(id);
      return;
    }
    if (isWhitespace(node) && !pending.length) return;
    parseInlineNode(node, {}, pending);
  });
  flush();
  return ids;
};

const parseImage = (el: HTMLElement, blocks: Blocks): BlockId => {
  const img = (el.tagName.toLowerCase() === "img" ? el : el.querySelector("img")) as HTMLElement | null;
  const heightRaw = img ? parseInt(img.style.height, 10) : NaN;
  return put(
    blocks,
    makeBlock("image", {
      src: img?.getAttribute("src") ?? "",
      align: img?.getAttribute("data-align") ?? "center",
      fit: img?.getAttribute("data-fit") !== "0",
      objectFit: img?.getAttribute("data-object-fit") ?? "cover",
      height: Number.isFinite(heightRaw) ? heightRaw : null,
    }),
  );
};

const parseBlock = (el: HTMLElement, blocks: Blocks): BlockId | null => {
  const kind = resolveKind(el);
  if (!kind) return null;
  if (kind === "image") return parseImage(el, blocks);

  if (kind === "heading") {
    const level = Number(el.tagName.slice(1)) || 1;
    const spec = specByType.get("heading");
    return put(
      blocks,
      withShared(
        makeBlock(kind, { level, ...readAttrs(el, spec?.attrs ?? []) }, inlineOf(el)),
        el,
      ),
    );
  }

  if (kind === "codeBlock") {
    const code = el.querySelector("code");
    const cls = code?.getAttribute("class") ?? "";
    const language = /language-(\S+)/.exec(cls)?.[1] ?? "plaintext";
    return put(
      blocks,
      makeBlock(
        kind,
        {
          language,
          lineNumbers: el.getAttribute("data-line-numbers") !== "false",
          lineWrap: el.getAttribute("data-line-wrap") === "true",
        },
        [textOp(code?.textContent ?? "")],
      ),
    );
  }

  if (kind === "html") {
    return put(
      blocks,
      makeBlock(kind, {
        html: el.innerHTML,
        source: el.getAttribute("data-source") === "true",
      }),
    );
  }

  if (kind === "taskItem") {
    const body = el.querySelector(":scope > div") as HTMLElement | null;
    return put(
      blocks,
      makeBlock(
        kind,
        { checked: el.getAttribute("data-checked") === "true" },
        body ? childIdsOf(body, blocks) : [],
      ),
    );
  }

  const spec = specByType.get(kind);
  if (!spec) return null;
  const options = readAttrs(el, spec.attrs);

  const shape = contentShapeOf(kind);
  if (shape === "none") {
    return put(blocks, withShared(makeBlock(kind, options), el));
  }
  if (shape === "delta") {
    return put(
      blocks,
      withShared(makeBlock(kind, options, isTextKind(kind) ? inlineOf(el) : []), el),
    );
  }
  if (kind === "table") {
    const body = (el.querySelector(":scope > tbody") as HTMLElement | null) ?? el;
    return put(blocks, withShared(makeBlock(kind, options, childIdsOf(body, blocks)), el));
  }
  return put(blocks, withShared(makeBlock(kind, options, childIdsOf(el, blocks)), el));
};

export const marDocumentFromHtml = (html: string): MarDocument => {
  const dom = new DOMParser().parseFromString(`<body>${html}</body>`, "text/html");
  const blocks: Blocks = {};
  const root = childIdsOf(dom.body, blocks);
  return makeDocument(root, blocks);
};

export const marBlocksFromHtml = (
  html: string,
  into?: MarBlockKind,
): MarDocument => fitBlocks(marDocumentFromHtml(html), into);
