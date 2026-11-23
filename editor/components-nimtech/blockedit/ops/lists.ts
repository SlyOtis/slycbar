import type { MarBlock, MarDocument, Selection } from "../model/types";
import { deltaLength, splitDelta } from "../model/delta";
import { isTextKind, makeBlock } from "../model/schema";
import {
  childBlocks,
  childIds,
  getBlock,
  insertBlock,
  locate,
  putBlocks,
  removeBlock,
  unlinkBlock,
  updateBlock,
  withChildIds,
} from "../model/tree";
import { contentOf, setBlockContent } from "./text";

const lastTextDescendant = (doc: MarDocument, block: MarBlock): MarBlock | null => {
  const kids = childBlocks(doc, block.id);
  for (let i = kids.length - 1; i >= 0; i -= 1) {
    const kid = kids[i];
    if (!kid) continue;
    if (isTextKind(kid.kind)) return kid;
    const deeper = lastTextDescendant(doc, kid);
    if (deeper) return deeper;
  }
  return null;
};

const caret = (blockId: string, offset: number): Selection => ({
  kind: "text",
  anchor: { blockId, offset },
  head: { blockId, offset },
});

const itemOf = (doc: MarDocument, paragraphId: string) => {
  const paragraphLoc = locate(doc, paragraphId);
  if (!paragraphLoc?.parentId) return null;
  const item = getBlock(doc, paragraphLoc.parentId);
  if (!item || (item.kind !== "listItem" && item.kind !== "taskItem")) return null;
  const itemLoc = locate(doc, item.id);
  if (!itemLoc) return null;
  return { item, itemLoc };
};

export const isInList = (doc: MarDocument, paragraphId: string): boolean =>
  itemOf(doc, paragraphId) !== null;

export const removeListItem = (
  doc: MarDocument,
  paragraphId: string,
): { doc: MarDocument; selection: Selection } | null => {
  const found = itemOf(doc, paragraphId);
  if (!found) return null;
  const { item, itemLoc } = found;
  if (deltaLength(contentOf(doc, paragraphId)) > 0) return null;
  if (itemLoc.index > 0) {
    const previousItem = itemLoc.siblings[itemLoc.index - 1];
    const previousParagraph =
      (previousItem ? lastTextDescendant(doc, previousItem) : null) ??
      (previousItem ? childBlocks(doc, previousItem.id).slice(-1)[0] ?? null : null);
    const offset = previousParagraph
      ? deltaLength(contentOf(doc, previousParagraph.id))
      : 0;
    return {
      doc: removeBlock(doc, item.id),
      selection: caret(
        previousParagraph?.id ?? previousItem?.id ?? paragraphId,
        offset,
      ),
    };
  }
  return outdentList(doc, paragraphId, 0);
};

export const enterInList = (
  doc: MarDocument,
  paragraphId: string,
  offset = 0,
): { doc: MarDocument; selection: Selection } | null => {
  const found = itemOf(doc, paragraphId);
  if (!found) return null;
  const { item, itemLoc } = found;
  if (!deltaLength(contentOf(doc, paragraphId))) return outdentList(doc, paragraphId, 0);
  const [left, right] = splitDelta(contentOf(doc, paragraphId), offset);
  let working = setBlockContent(doc, paragraphId, left).doc;
  const newParagraph = makeBlock("paragraph", {}, right);
  const newItem = makeBlock(item.kind, {}, [newParagraph.id]);
  working = putBlocks(working, [newParagraph]);
  working = insertBlock(working, newItem, itemLoc.parentId, itemLoc.index + 1);
  return { doc: working, selection: caret(newParagraph.id, 0) };
};

export const indentList = (
  doc: MarDocument,
  paragraphId: string,
  offset: number,
): { doc: MarDocument; selection: Selection } | null => {
  const found = itemOf(doc, paragraphId);
  if (!found) return null;
  const { item, itemLoc } = found;
  if (itemLoc.index === 0 || !itemLoc.parentId) return null;
  const list = getBlock(doc, itemLoc.parentId);
  const previous = itemLoc.siblings[itemLoc.index - 1];
  if (!list || !previous) return null;
  const nested = childBlocks(doc, previous.id).find((c) => c.kind === list.kind);
  const working = unlinkBlock(doc, item.id);
  if (nested) {
    return {
      doc: insertBlock(working, item, nested.id, childIds(nested).length),
      selection: caret(paragraphId, offset),
    };
  }
  const newNested = makeBlock(list.kind, {}, [item.id]);
  return {
    doc: insertBlock(working, newNested, previous.id, childBlocks(working, previous.id).length),
    selection: caret(paragraphId, offset),
  };
};

export const setListType = (
  doc: MarDocument,
  itemId: string,
  newKind: string,
  listStyle?: string,
): { doc: MarDocument } => {
  const itemLoc = locate(doc, itemId);
  if (!itemLoc?.parentId) return { doc };
  const list = getBlock(doc, itemLoc.parentId);
  if (!list) return { doc };
  const listLoc = locate(doc, list.id);
  if (!listLoc) return { doc };

  const itemKind = newKind === "taskList" ? "taskItem" : "listItem";
  const items = childBlocks(doc, list.id);
  const moved = items.slice(itemLoc.index);
  let working = doc;
  const movedIds: string[] = [];
  for (const it of moved) {
    if (it.kind === itemKind) {
      movedIds.push(it.id);
      continue;
    }
    const replacement = makeBlock(itemKind, {}, childIds(it));
    working = putBlocks(working, [replacement]);
    movedIds.push(replacement.id);
  }
  const newList = makeBlock(newKind, listStyle ? { listStyle } : {}, movedIds);

  if (itemLoc.index === 0) {
    working = updateBlock(working, list.id, (b) => withChildIds(b, []));
    working = removeBlock(working, list.id);
    working = insertBlock(working, newList, listLoc.parentId, listLoc.index);
    return { doc: working };
  }
  working = updateBlock(working, list.id, (b) =>
    withChildIds(b, childIds(b).slice(0, itemLoc.index)),
  );
  working = insertBlock(working, newList, listLoc.parentId, listLoc.index + 1);
  return { doc: working };
};

export const outdentList = (
  doc: MarDocument,
  paragraphId: string,
  offset: number,
): { doc: MarDocument; selection: Selection } | null => {
  const found = itemOf(doc, paragraphId);
  if (!found) return null;
  const { item, itemLoc } = found;
  if (!itemLoc.parentId) return null;
  const listLoc = locate(doc, itemLoc.parentId);
  if (!listLoc) return null;
  const listParent = listLoc.parentId ? getBlock(doc, listLoc.parentId) : null;
  if (listParent && (listParent.kind === "listItem" || listParent.kind === "taskItem")) {
    const parentItemLoc = locate(doc, listParent.id);
    if (!parentItemLoc?.parentId) return null;
    const working = unlinkBlock(doc, item.id);
    return {
      doc: insertBlock(working, item, parentItemLoc.parentId, parentItemLoc.index + 1),
      selection: caret(paragraphId, offset),
    };
  }
  const lifted = makeBlock("paragraph", {}, contentOf(doc, paragraphId));
  let working = removeBlock(doc, item.id);
  working = insertBlock(working, lifted, listLoc.parentId, listLoc.index + 1);
  return { doc: working, selection: caret(lifted.id, offset) };
};
