import type { BlockId, MarBlock, MarDocument, Selection } from "../model/types";
import { accepts, categoryOf, defaultOptions, emptyContent, makeBlock } from "../model/schema";
import {
  childIds,
  getBlock,
  insertBlock,
  locate,
  putBlocks,
  unlinkBlock,
  updateBlock,
} from "../model/tree";

export const setBlockKind = (
  doc: MarDocument,
  blockId: BlockId,
  kind: string,
  options: Record<string, unknown> = {},
): { doc: MarDocument; selection: Selection } => ({
  doc: updateBlock(doc, blockId, (b) => ({
    ...b,
    type: categoryOf(kind),
    kind,
    options: { ...defaultOptions(kind), ...options },
    content: Array.isArray(b.content) ? b.content : emptyContent(kind),
  })),
  selection: {
    kind: "text",
    anchor: { blockId, offset: 0 },
    head: { blockId, offset: 0 },
  },
});

const wrap = (kind: string, childId: BlockId): MarBlock => makeBlock(kind, {}, [childId]);

export const adapt = (
  doc: MarDocument,
  block: MarBlock,
  destParentKind: string | null,
): { doc: MarDocument; block: MarBlock } => {
  if (accepts(destParentKind, block.kind)) return { doc, block };

  const wrapper =
    destParentKind === "bulletList" || destParentKind === "orderedList"
      ? wrap("listItem", block.id)
      : destParentKind === "taskList"
        ? wrap("taskItem", block.id)
        : destParentKind === "columnList"
          ? wrap("column", block.id)
          : destParentKind === "tableRow"
            ? wrap("tableCell", block.id)
            : null;
  if (wrapper) return { doc: putBlocks(doc, [wrapper]), block: wrapper };

  if (block.kind === "listItem" || block.kind === "taskItem" || block.kind === "column") {
    const first = getBlock(doc, childIds(block)[0] ?? "");
    if (first) return { doc, block: first };
  }
  return { doc, block };
};

const TEMPLATE_ROOT_KINDS = new Set(["section"]);

export const acceptsAtRoot = (doc: MarDocument, kind: string): boolean =>
  doc.type === "template" ? TEMPLATE_ROOT_KINDS.has(kind) : accepts(null, kind);

export const dropBlock = (
  doc: MarDocument,
  dragId: BlockId,
  parentId: BlockId | null,
  refId: BlockId | null,
  before: boolean,
): { doc: MarDocument; selection: Selection | null } => {
  const drag = getBlock(doc, dragId);
  if (!drag) return { doc, selection: null };
  const parentKind = parentId ? getBlock(doc, parentId)?.kind ?? null : null;
  const unlinked = unlinkBlock(doc, dragId);
  const adapted = adapt(unlinked, drag, parentKind);
  let next = adapted.doc;
  if (refId) {
    const loc = locate(next, refId);
    if (!loc) return { doc, selection: null };
    if (loc.parentId === null && !acceptsAtRoot(doc, adapted.block.kind))
      return { doc, selection: null };
    next = insertBlock(next, adapted.block, loc.parentId, loc.index + (before ? 0 : 1));
  } else {
    if (parentId === null && !acceptsAtRoot(doc, adapted.block.kind))
      return { doc, selection: null };
    next = insertBlock(next, adapted.block, parentId, 0);
  }
  return { doc: next, selection: null };
};
