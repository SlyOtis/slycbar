import type { BlockId, MarBlock, MarDocument, Selection } from "../model/types";
import { categoryOf, isTextKind, makeBlock } from "../model/schema";
import {
  childIds,
  getBlock,
  insertBlock,
  locate,
  pathOf,
  putBlocks,
  removeBlock,
} from "../model/tree";
import { acceptsAtRoot, setBlockKind } from "../ops/blocks";
import { contentOf } from "../ops/text";
import type { BlockEngine } from "../engine/BlockEngine";

const focusSelection = (block: MarBlock): Selection => {
  const focusId =
    categoryOf(block.kind) === "layout" ? childIds(block)[0] ?? block.id : block.id;
  return {
    kind: "text",
    anchor: { blockId: focusId, offset: 0 },
    head: { blockId: focusId, offset: 0 },
  };
};

export const placeBlock = (
  engine: BlockEngine,
  blockId: BlockId,
  block: MarBlock,
  created: MarBlock[] = [],
): void => {
  engine.dispatch((doc) => {
    const current = getBlock(doc, blockId);
    const loc = locate(doc, blockId);
    if (!loc) return { doc };
    const seeded = putBlocks(doc, created);
    if (doc.type === "template" && acceptsAtRoot(doc, block.kind)) {
      const rootId = pathOf(seeded, blockId)?.[0] ?? blockId;
      const rootLoc = locate(seeded, rootId);
      const at = rootLoc ? rootLoc.index + 1 : seeded.root.length;
      return {
        doc: insertBlock(seeded, block, null, at),
        selection: focusSelection(block),
      };
    }
    const isEmptyParagraph =
      current?.kind === "paragraph" && !contentOf(seeded, blockId).length;
    let next = isEmptyParagraph
      ? insertBlock(removeBlock(seeded, blockId), block, loc.parentId, loc.index)
      : insertBlock(seeded, block, loc.parentId, loc.index + 1);
    if (categoryOf(block.kind) !== "layout" && !isTextKind(block.kind)) {
      const at = locate(next, block.id);
      if (at) {
        const trailing = makeBlock("paragraph");
        next = insertBlock(next, trailing, at.parentId, at.index + 1);
        return {
          doc: next,
          selection: {
            kind: "text",
            anchor: { blockId: trailing.id, offset: 0 },
            head: { blockId: trailing.id, offset: 0 },
          },
        };
      }
    }
    return { doc: next, selection: focusSelection(block) };
  });
};

export const turnInto = (
  engine: BlockEngine,
  blockId: BlockId,
  kind: string,
  options: Record<string, unknown> = {},
): void => {
  engine.dispatch((doc) => setBlockKind(doc, blockId, kind, options));
};

export const wrapInList = (
  engine: BlockEngine,
  blockId: BlockId,
  listKind: "bulletList" | "orderedList" | "taskList",
): void => {
  const itemKind = listKind === "taskList" ? "taskItem" : "listItem";
  engine.dispatch((doc: MarDocument) => {
    const current = getBlock(doc, blockId);
    const loc = locate(doc, blockId);
    if (!current || !loc) return { doc };
    const paragraph = makeBlock("paragraph", {}, contentOf(doc, blockId));
    const item = makeBlock(itemKind, {}, [paragraph.id]);
    const list = makeBlock(listKind, {}, [item.id]);
    let next = putBlocks(doc, [paragraph, item]);
    next = removeBlock(next, blockId);
    next = insertBlock(next, list, loc.parentId, loc.index);
    return {
      doc: next,
      selection: {
        kind: "text",
        anchor: { blockId: paragraph.id, offset: 0 },
        head: { blockId: paragraph.id, offset: 0 },
      },
    };
  });
};

export const para = (): MarBlock => makeBlock("paragraph");

export const layoutBlock = (
  kind: string,
  options: Record<string, unknown> = {},
): { block: MarBlock; created: MarBlock[] } => {
  const inner = para();
  return { block: makeBlock(kind, options, [inner.id]), created: [inner] };
};

export const columnsBlock = (): { block: MarBlock; created: MarBlock[] } => {
  const first = para();
  const second = para();
  const left = makeBlock("column", {}, [first.id]);
  const right = makeBlock("column", {}, [second.id]);
  return {
    block: makeBlock("columnList", {}, [left.id, right.id]),
    created: [first, second, left, right],
  };
};

export const tableBlock = (
  rows = 3,
  cols = 3,
): { block: MarBlock; created: MarBlock[] } => {
  const created: MarBlock[] = [];
  const rowIds: BlockId[] = [];
  for (let r = 0; r < rows; r += 1) {
    const cellIds: BlockId[] = [];
    for (let c = 0; c < cols; c += 1) {
      const paragraph = para();
      const cell = makeBlock(r === 0 ? "tableHeader" : "tableCell", {}, [paragraph.id]);
      created.push(paragraph, cell);
      cellIds.push(cell.id);
    }
    const row = makeBlock("tableRow", {}, cellIds);
    created.push(row);
    rowIds.push(row.id);
  }
  return { block: makeBlock("table", {}, rowIds), created };
};
