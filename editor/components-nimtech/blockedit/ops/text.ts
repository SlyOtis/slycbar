import type { Delta, MarDocument, Selection } from "../model/types";
import { deltaLength, mergeDelta, splitDelta } from "../model/delta";
import { isTextKind, makeBlock } from "../model/schema";
import {
  getBlock,
  insertBlock,
  locate,
  removeBlock,
  updateBlock,
} from "../model/tree";

export const contentOf = (doc: MarDocument, blockId: string): Delta => {
  const block = getBlock(doc, blockId);
  return block && Array.isArray(block.content) ? block.content : [];
};

const caret = (blockId: string, offset: number): Selection => ({
  kind: "text",
  anchor: { blockId, offset },
  head: { blockId, offset },
});

export const setBlockContent = (
  doc: MarDocument,
  blockId: string,
  content: Delta,
): { doc: MarDocument } => ({
  doc: updateBlock(doc, blockId, (b) => ({ ...b, content: mergeDelta(content) })),
});

export const deleteInlineRange = (
  doc: MarDocument,
  blockId: string,
  from: number,
  to: number,
): { doc: MarDocument; selection: Selection } => {
  const [head, tail] = splitDelta(contentOf(doc, blockId), to);
  const [left] = splitDelta(head, from);
  return {
    ...setBlockContent(doc, blockId, [...left, ...tail]),
    selection: caret(blockId, from),
  };
};

export const insertInlineAt = (
  doc: MarDocument,
  blockId: string,
  offset: number,
  ops: Delta,
): { doc: MarDocument; selection: Selection } => {
  const [left, right] = splitDelta(contentOf(doc, blockId), offset);
  return {
    ...setBlockContent(doc, blockId, [...left, ...ops, ...right]),
    selection: caret(blockId, offset + deltaLength(ops)),
  };
};

export const splitTextBlock = (
  doc: MarDocument,
  blockId: string,
  offset: number,
): { doc: MarDocument; selection: Selection } | null => {
  const loc = locate(doc, blockId);
  const block = getBlock(doc, blockId);
  if (!loc || !block) return null;
  const [left, right] = splitDelta(contentOf(doc, blockId), offset);
  const keepKind = block.kind === "heading" ? "paragraph" : block.kind;
  const newBlock = makeBlock(keepKind, {}, right);
  let next = setBlockContent(doc, blockId, left).doc;
  next = insertBlock(next, newBlock, loc.parentId, loc.index + 1);
  return { doc: next, selection: caret(newBlock.id, 0) };
};

export const mergeWithPrevious = (
  doc: MarDocument,
  blockId: string,
): { doc: MarDocument; selection: Selection } | null => {
  const loc = locate(doc, blockId);
  const block = getBlock(doc, blockId);
  if (!loc || !block || loc.index === 0) return null;
  const previous = loc.siblings[loc.index - 1];
  if (!previous) return null;
  if (!isTextKind(previous.kind)) {
    if (deltaLength(contentOf(doc, blockId)) > 0) return null;
    return {
      doc: removeBlock(doc, blockId),
      selection: { kind: "node", blockId: previous.id },
    };
  }
  const joinOffset = deltaLength(contentOf(doc, previous.id));
  const merged = [...contentOf(doc, previous.id), ...contentOf(doc, blockId)];
  let next = setBlockContent(doc, previous.id, merged).doc;
  next = removeBlock(next, blockId);
  return { doc: next, selection: caret(previous.id, joinOffset) };
};
