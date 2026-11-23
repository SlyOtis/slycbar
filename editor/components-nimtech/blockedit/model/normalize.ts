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
  MarDocumentType,
  ReadMode,
} from "./types";
import { childIds, defaultText, isSlot, withChildIds, type SharedText } from "./tree";
import { isTextOp, mergeDelta, refOp } from "./delta";
import { contentShapeOf, isTextKind, makeBlock, makeDocument, schema } from "./schema";

const DROP_WHEN_EMPTY = new Set([
  "bulletList",
  "orderedList",
  "taskList",
  "columnList",
  "table",
  "tableRow",
]);

const LIST_KINDS = new Set(["bulletList", "orderedList", "taskList"]);

const REF_NAMES = new Set(["mention", "image", "break"]);

const EDIT_MODES = new Set<EditMode>(["open", "lockBlock", "lockContent", "locked"]);

const READ_MODES = new Set<ReadMode>(["document", "section"]);

const DOCUMENT_TYPES = new Set<MarDocumentType>(["document", "template"]);

const FONT_FAMILIES = new Set<FontFamily>([
  "sans",
  "serif",
  "mono",
  "rounded",
  "inter",
  "source-serif",
  "jetbrains-mono",
  "nunito",
]);

const FONT_SIZES = new Set<FontSize>(["sm", "md", "lg", "xl"]);

const LINE_HEIGHTS = new Set<LineHeight>(["tight", "normal", "relaxed", "loose"]);

const first = <T,>(set: Set<T>, ...values: unknown[]): T | null => {
  for (const value of values) if (set.has(value as T)) return value as T;
  return null;
};

const takeText = (
  source: MarBlock,
  options: Record<string, unknown>,
): SharedText => {
  delete options.fontFamily;
  delete options.fontSize;
  delete options.lineHeight;
  return {
    fontFamily: first(FONT_FAMILIES, source.fontFamily) ?? defaultText.fontFamily,
    fontSize: first(FONT_SIZES, source.fontSize) ?? defaultText.fontSize,
    lineHeight: first(LINE_HEIGHTS, source.lineHeight) ?? defaultText.lineHeight,
  };
};

const sanitizeDelta = (delta: Delta): Delta =>
  mergeDelta(
    delta.filter((op) => {
      if (isTextOp(op)) return typeof op.insert === "string";
      return !!op.insert && REF_NAMES.has(op.insert.ref);
    }),
  );

export const normalize = (doc: MarDocument): MarDocument => {
  const blocks: Record<BlockId, MarBlock> = {};
  const seen = new Set<BlockId>();
  const dropped: MarBlockKind[] = [];

  const deltaOf = (source: MarBlock): Delta => {
    if (Array.isArray(source.content)) return source.content;
    const out: Delta = [];
    for (const childId of childIds(source)) {
      const child = doc.blocks[childId];
      if (!child || seen.has(childId)) continue;
      seen.add(childId);
      out.push(...deltaOf(child));
    }
    return out;
  };

  const normalizeBlock = (source: MarBlock): MarBlock | null => {
    const kind = source.kind;
    const spec = schema[kind];
    if (!spec) {
      dropped.push(kind);
      return null;
    }
    const shape = contentShapeOf(source);
    const options = { ...spec.defaults, ...(source.options ?? {}) };
    const text = takeText(source, options);
    const base: MarBlock = {
      id: source.id,
      type: spec.category,
      kind,
      content: null,
      options,
      attr: source.attr ?? {},
      edit: EDIT_MODES.has(source.edit) ? source.edit : spec.edit,
      read: READ_MODES.has(source.read) ? source.read : spec.read,
      inherits: source.inherits !== false,
      ...text,
    };
    if (shape === "none") return base;
    if (shape === "delta") return { ...base, content: sanitizeDelta(deltaOf(source)) };
    const ids = normalizeIds(childIds(source));
    if (!ids.length) {
      if (DROP_WHEN_EMPTY.has(kind)) return null;
      const paragraph = makeBlock("paragraph");
      blocks[paragraph.id] = paragraph;
      ids.push(paragraph.id);
    }
    return withChildIds(base, ids);
  };

  const normalizeIds = (ids: BlockId[]): BlockId[] => {
    const kept: BlockId[] = [];
    for (const id of ids) {
      if (seen.has(id)) continue;
      const source = doc.blocks[id];
      if (!source) continue;
      seen.add(id);
      const block = normalizeBlock(source);
      if (!block) continue;
      blocks[block.id] = block;
      kept.push(block.id);
    }
    const merged: BlockId[] = [];
    for (const id of kept) {
      const previousId = merged[merged.length - 1];
      const previous = previousId ? blocks[previousId] : undefined;
      const block = blocks[id];
      if (previous && block && LIST_KINDS.has(block.kind) && previous.kind === block.kind) {
        blocks[previous.id] = withChildIds(previous, [
          ...childIds(previous),
          ...childIds(block),
        ]);
        delete blocks[id];
        continue;
      }
      merged.push(id);
    }
    return merged;
  };

  const root = normalizeIds(doc.root);

  if (doc.type === "template") {
    if (!root.length) {
      const paragraph = makeBlock("paragraph");
      const section = { ...makeBlock("section", {}, [paragraph.id]), edit: "open" as EditMode };
      blocks[paragraph.id] = paragraph;
      blocks[section.id] = section;
      root.push(section.id);
    }
  } else {
    if (!root.length) {
      const paragraph = makeBlock("paragraph");
      blocks[paragraph.id] = paragraph;
      root.push(paragraph.id);
    }
    const last = blocks[root[root.length - 1] as BlockId];
    if (last && !isSlot(last) && !isTextKind(last.kind)) {
      const paragraph = makeBlock("paragraph");
      blocks[paragraph.id] = paragraph;
      root.push(paragraph.id);
    }
  }

  if (dropped.length) {
    console.warn(
      `MarBlockEditor dropped ${dropped.length} block(s) of unknown kind: ${[...new Set(dropped)].join(", ")}`,
    );
  }

  const known = DOCUMENT_TYPES.has(doc.type);
  const base = known ? doc : makeDocument();
  return { ...base, type: known ? doc.type : "document", root, blocks };
};

const flatDelta = (doc: MarDocument): Delta => {
  const out: Delta = [];
  const walk = (ids: BlockId[]): void => {
    for (const id of ids) {
      const block = doc.blocks[id];
      if (!block) continue;
      if (Array.isArray(block.content)) {
        if (!block.content.length) continue;
        if (out.length) out.push(refOp("break"));
        out.push(...block.content);
        continue;
      }
      walk(childIds(block));
    }
  };
  walk(doc.root);
  return sanitizeDelta(out);
};

export const fitBlocks = (doc: MarDocument, into?: MarBlockKind): MarDocument => {
  if (!into) return doc;
  const spec = schema[into];
  if (!spec) return doc;
  if (spec.contentShape === "slot") return doc;
  if (spec.contentShape === "none" || !spec.text) return makeDocument();
  const block = makeBlock(into, {}, flatDelta(doc));
  return makeDocument([block.id], { [block.id]: block });
};
