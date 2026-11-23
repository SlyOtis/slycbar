import * as Y from "yjs";
import type {
  BlockId,
  Delta,
  EditMode,
  FontFamily,
  FontSize,
  LineHeight,
  MarBlock,
  MarDocument,
  Marks,
  ReadMode,
} from "../model/types";
import { isTextOp, refOp, textOp } from "../model/delta";
import { categoryOf, makeDocument } from "../model/schema";
import { childIds, defaultText } from "../model/tree";

export const LOCAL_ORIGIN = "blockedit-local";

export interface YDeltaOp {
  insert: string | Record<string, unknown>;
  attributes?: Record<string, unknown>;
}

export const deltaToY = (content: Delta): YDeltaOp[] => {
  const ops: YDeltaOp[] = [];
  for (const op of content) {
    if (isTextOp(op)) {
      if (!op.insert) continue;
      ops.push(op.marks ? { insert: op.insert, attributes: { ...op.marks } } : { insert: op.insert });
      continue;
    }
    ops.push({ insert: { ref: op.insert.ref, attrs: op.attrs ?? {} } });
  }
  return ops;
};

export const yToDelta = (ops: YDeltaOp[]): Delta => {
  const out: Delta = [];
  for (const op of ops) {
    if (typeof op.insert === "string") {
      out.push(textOp(op.insert, op.attributes as Marks | undefined));
      continue;
    }
    const embed = op.insert as { ref?: unknown; attrs?: unknown };
    if (embed.ref === "mention" || embed.ref === "image" || embed.ref === "break") {
      out.push(refOp(embed.ref, (embed.attrs as Record<string, unknown>) ?? {}));
    }
  }
  return out;
};

export const contentToYText = (content: Delta): Y.Text => {
  const text = new Y.Text();
  text.applyDelta(deltaToY(content));
  return text;
};

const recordToY = (values: Record<string, unknown>): Y.Map<unknown> => {
  const map = new Y.Map<unknown>();
  for (const [key, value] of Object.entries(values)) map.set(key, value);
  return map;
};

const yToRecord = (map: Y.Map<unknown> | undefined): Record<string, unknown> => {
  const out: Record<string, unknown> = {};
  map?.forEach((value, key) => {
    out[key] = value;
  });
  return out;
};

export const blockToY = (doc: MarDocument, id: BlockId): Y.Map<unknown> | null => {
  const block = doc.blocks[id];
  if (!block) return null;
  const map = new Y.Map<unknown>();
  map.set("id", block.id);
  map.set("kind", block.kind);
  map.set("options", recordToY(block.options));
  map.set("attr", recordToY(block.attr));
  map.set("edit", block.edit);
  map.set("read", block.read);
  map.set("inherits", block.inherits);
  map.set("fontFamily", block.fontFamily);
  map.set("fontSize", block.fontSize);
  map.set("lineHeight", block.lineHeight);
  if (Array.isArray(block.content)) map.set("content", contentToYText(block.content));
  else if (block.content !== null) {
    const children = new Y.Array<Y.Map<unknown>>();
    children.insert(
      0,
      childIds(block)
        .map((childId) => blockToY(doc, childId))
        .filter((child): child is Y.Map<unknown> => child !== null),
    );
    map.set("children", children);
  }
  return map;
};

export const yToBlock = (map: Y.Map<unknown>, blocks: Record<BlockId, MarBlock>): BlockId => {
  const kind = (map.get("kind") as string) ?? "paragraph";
  const id = (map.get("id") as string) ?? "";
  const category = categoryOf(kind);
  const content = map.get("content") as Y.Text | undefined;
  const children = map.get("children") as Y.Array<Y.Map<unknown>> | undefined;
  const block: MarBlock = {
    id,
    type: category,
    kind,
    content:
      category === "shape"
        ? null
        : content
          ? yToDelta(content.toDelta() as YDeltaOp[])
          : children
            ? { blocks: children.toArray().map((child) => yToBlock(child, blocks)) }
            : [],
    options: yToRecord(map.get("options") as Y.Map<unknown> | undefined),
    attr: yToRecord(map.get("attr") as Y.Map<unknown> | undefined),
    edit: (map.get("edit") as EditMode) ?? "open",
    read: (map.get("read") as ReadMode) ?? "document",
    inherits: map.get("inherits") !== false,
    fontFamily: (map.get("fontFamily") as FontFamily) ?? defaultText.fontFamily,
    fontSize: (map.get("fontSize") as FontSize) ?? defaultText.fontSize,
    lineHeight: (map.get("lineHeight") as LineHeight) ?? defaultText.lineHeight,
  };
  blocks[id] = block;
  return id;
};

export const docToY = (doc: MarDocument, root: Y.Array<Y.Map<unknown>>): void => {
  if (root.length > 0) root.delete(0, root.length);
  root.insert(
    0,
    doc.root
      .map((id) => blockToY(doc, id))
      .filter((block): block is Y.Map<unknown> => block !== null),
  );
};

export const yToDoc = (root: Y.Array<Y.Map<unknown>>): MarDocument => {
  const blocks: Record<BlockId, MarBlock> = {};
  const ids = root.toArray().map((map) => yToBlock(map, blocks));
  return makeDocument(ids, blocks);
};
