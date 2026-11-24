import type { BlockId, Delta, MarBlock, MarDocument, Selection } from "../model/types";
import { deltaLength, opLength } from "../model/delta";
import { getBlock, locate } from "../model/tree";

const contentOf = (block: MarBlock): Delta =>
  Array.isArray(block.content) ? block.content : [];

export const blockTextLength = (block: MarBlock): number =>
  deltaLength(contentOf(block));

const runRange = (block: MarBlock, offset: number): { from: number; to: number } => {
  let at = 0;
  for (const op of contentOf(block)) {
    const len = opLength(op);
    if (offset < at + len || (offset === at + len && at + len === blockTextLength(block))) {
      return { from: at, to: at + len };
    }
    at += len;
  }
  return { from: 0, to: at };
};

const documentSelection = (doc: MarDocument): Selection => ({
  kind: "blocks",
  ids: [...doc.root],
});

const isDocumentSelection = (doc: MarDocument, ids: BlockId[]): boolean =>
  ids.length === doc.root.length && ids.every((id, index) => doc.root[index] === id);

const textSelection = (blockId: BlockId, from: number, to: number): Selection => ({
  kind: "text",
  anchor: { blockId, offset: from },
  head: { blockId, offset: to },
});

export const selectOutwards = (
  doc: MarDocument,
  selection: Selection | null,
  fallbackId: BlockId | null,
): Selection | null => {
  if (!selection) {
    if (!fallbackId) return doc.root.length ? documentSelection(doc) : null;
    return { kind: "blocks", ids: [fallbackId] };
  }

  if (selection.kind === "node") return { kind: "blocks", ids: [selection.blockId] };

  if (selection.kind === "blocks") {
    if (!selection.ids.length) return documentSelection(doc);
    if (isDocumentSelection(doc, selection.ids)) return null;
    const first = selection.ids[0];
    if (!first) return documentSelection(doc);
    const loc = locate(doc, first);
    if (loc?.parentId) return { kind: "blocks", ids: [loc.parentId] };
    return documentSelection(doc);
  }

  const blockId = selection.anchor.blockId;
  if (blockId !== selection.head.blockId) return { kind: "blocks", ids: [blockId] };
  const block = getBlock(doc, blockId);
  if (!block) return null;
  const length = blockTextLength(block);
  const from = Math.min(selection.anchor.offset, selection.head.offset);
  const to = Math.max(selection.anchor.offset, selection.head.offset);
  if (from === to) {
    const run = runRange(block, from);
    if (run.to > run.from) return textSelection(blockId, run.from, run.to);
  }
  if (length > 0 && !(from === 0 && to === length)) {
    return textSelection(blockId, 0, length);
  }
  return { kind: "blocks", ids: [blockId] };
};
