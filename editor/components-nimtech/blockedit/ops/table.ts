import type { BlockId, MarBlock, MarDocument } from "../model/types";
import { makeBlock } from "../model/schema";
import { childBlocks, childIds, getBlock, putBlocks, removeBlock, updateBlock, withChildIds } from "../model/tree";

const colCount = (doc: MarDocument, table: MarBlock): number =>
  Math.max(0, ...childBlocks(doc, table.id).map((row) => childIds(row).length));

const cell = (header: boolean): MarBlock[] => {
  const paragraph = makeBlock("paragraph");
  return [makeBlock(header ? "tableHeader" : "tableCell", {}, [paragraph.id]), paragraph];
};

export const addRow = (doc: MarDocument, tableId: string, at?: number): { doc: MarDocument } => {
  const table = getBlock(doc, tableId);
  if (!table) return { doc };
  const cols = Math.max(1, colCount(doc, table));
  const created: MarBlock[] = [];
  const cellIds: BlockId[] = [];
  for (let i = 0; i < cols; i += 1) {
    const made = cell(false);
    created.push(...made);
    cellIds.push((made[0] as MarBlock).id);
  }
  const row = makeBlock("tableRow", {}, cellIds);
  const withCells = putBlocks(doc, [...created, row]);
  return {
    doc: updateBlock(withCells, tableId, (t) => {
      const rows = [...childIds(t)];
      const index = Math.max(1, Math.min(at ?? rows.length, rows.length));
      rows.splice(index, 0, row.id);
      return withChildIds(t, rows);
    }),
  };
};

export const addColumn = (doc: MarDocument, tableId: string, at?: number): { doc: MarDocument } => {
  const table = getBlock(doc, tableId);
  if (!table) return { doc };
  let working = doc;
  childIds(table).forEach((rowId, i) => {
    const made = cell(i === 0);
    const created = made[0] as MarBlock;
    working = putBlocks(working, made);
    working = updateBlock(working, rowId, (row) => {
      const cells = [...childIds(row)];
      const index = Math.max(0, Math.min(at ?? cells.length, cells.length));
      cells.splice(index, 0, created.id);
      return withChildIds(row, cells);
    });
  });
  return { doc: working };
};

export const deleteRow = (doc: MarDocument, tableId: string, at?: number): { doc: MarDocument } => {
  const table = getBlock(doc, tableId);
  if (!table || childIds(table).length <= 1) return { doc };
  const rows = childIds(table);
  const index = at ?? rows.length - 1;
  if (index <= 0 || index >= rows.length) return { doc };
  return { doc: removeBlock(doc, rows[index] as BlockId) };
};

export const deleteColumn = (doc: MarDocument, tableId: string, at?: number): { doc: MarDocument } => {
  const table = getBlock(doc, tableId);
  if (!table || colCount(doc, table) <= 1) return { doc };
  let working = doc;
  for (const rowId of childIds(table)) {
    const row = getBlock(working, rowId);
    if (!row) continue;
    const cells = childIds(row);
    const index = at ?? cells.length - 1;
    if (index < 0 || index >= cells.length) continue;
    working = removeBlock(working, cells[index] as BlockId);
  }
  return { doc: working };
};
