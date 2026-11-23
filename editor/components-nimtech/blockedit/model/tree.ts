import type {
  BlockId,
  BlockSlot,
  FontFamily,
  FontSize,
  LineHeight,
  MarBlock,
  MarDocument,
} from "./types";

export interface SharedText {
  fontFamily: FontFamily;
  fontSize: FontSize;
  lineHeight: LineHeight;
}

export const defaultText: SharedText = {
  fontFamily: "sans",
  fontSize: "md",
  lineHeight: "normal",
};

export const getBlock = (doc: MarDocument, id: BlockId): MarBlock | null =>
  doc.blocks[id] ?? null;

export const isSlot = (block: MarBlock): boolean =>
  block.content !== null && !Array.isArray(block.content);

export const childIds = (block: MarBlock | null | undefined): BlockId[] =>
  block && isSlot(block) ? (block.content as BlockSlot).blocks ?? [] : [];

export const withChildIds = (block: MarBlock, ids: BlockId[]): MarBlock => ({
  ...block,
  content: { blocks: ids },
});

export const siblingIds = (doc: MarDocument, parentId: BlockId | null): BlockId[] =>
  parentId === null ? doc.root : childIds(doc.blocks[parentId] ?? null);

export const childBlocks = (doc: MarDocument, id: BlockId | null): MarBlock[] =>
  siblingIds(doc, id)
    .map((childId) => doc.blocks[childId])
    .filter((block): block is MarBlock => block !== undefined);

export const parentOf = (doc: MarDocument, id: BlockId): BlockId | null => {
  for (const block of Object.values(doc.blocks)) {
    if (childIds(block).includes(id)) return block.id;
  }
  return null;
};

export interface Location {
  parentId: BlockId | null;
  index: number;
  siblings: MarBlock[];
}

export const locate = (doc: MarDocument, id: BlockId): Location | null => {
  const rootIndex = doc.root.indexOf(id);
  if (rootIndex >= 0) {
    return { parentId: null, index: rootIndex, siblings: childBlocks(doc, null) };
  }
  const parentId = parentOf(doc, id);
  if (parentId === null) return null;
  return {
    parentId,
    index: childIds(doc.blocks[parentId] ?? null).indexOf(id),
    siblings: childBlocks(doc, parentId),
  };
};

export const pathOf = (doc: MarDocument, id: BlockId): BlockId[] | null => {
  if (!doc.blocks[id]) return null;
  const trail: BlockId[] = [id];
  let current = id;
  while (!doc.root.includes(current)) {
    const parent = parentOf(doc, current);
    if (parent === null) return null;
    trail.unshift(parent);
    current = parent;
  }
  return trail;
};

export const adjacentBlockId = (
  doc: MarDocument,
  id: BlockId,
  dir: -1 | 1,
): BlockId | null => {
  let current = id;
  for (let i = 0; i < 32; i += 1) {
    const loc = locate(doc, current);
    if (!loc) return null;
    const next = siblingIds(doc, loc.parentId)[loc.index + dir];
    if (next) return next;
    if (loc.parentId === null) return null;
    current = loc.parentId;
  }
  return null;
};

export const blockRange = (
  doc: MarDocument,
  fromId: BlockId,
  toId: BlockId,
): BlockId[] => {
  const from = pathOf(doc, fromId);
  const to = pathOf(doc, toId);
  if (!from || !to) return [];
  const limit = Math.min(from.length, to.length);
  let depth = 0;
  while (depth < limit && from[depth] === to[depth]) depth += 1;
  if (depth >= limit) depth = limit - 1;
  const start = from[depth];
  const end = to[depth];
  if (!start || !end) return [];
  if (start === end) return [start];
  const siblings = siblingIds(doc, depth === 0 ? null : from[depth - 1] ?? null);
  const a = siblings.indexOf(start);
  const b = siblings.indexOf(end);
  if (a < 0 || b < 0) return [];
  return siblings.slice(Math.min(a, b), Math.max(a, b) + 1);
};

export const sharedText = (doc: MarDocument, id: BlockId): SharedText => {
  const path = pathOf(doc, id) ?? [];
  for (let i = path.length - 1; i >= 0; i -= 1) {
    const block = doc.blocks[path[i] as BlockId];
    if (!block || block.inherits) continue;
    return {
      fontFamily: block.fontFamily,
      fontSize: block.fontSize,
      lineHeight: block.lineHeight,
    };
  }
  return defaultText;
};

export const descendantIds = (doc: MarDocument, id: BlockId): BlockId[] => {
  const out: BlockId[] = [];
  const walk = (current: BlockId): void => {
    for (const child of childIds(doc.blocks[current] ?? null)) {
      out.push(child);
      walk(child);
    }
  };
  walk(id);
  return out;
};

export const containsId = (
  doc: MarDocument,
  blockId: BlockId,
  id: BlockId,
): boolean => blockId === id || descendantIds(doc, blockId).includes(id);

export const updateBlock = (
  doc: MarDocument,
  id: BlockId,
  fn: (block: MarBlock) => MarBlock,
): MarDocument => {
  const block = doc.blocks[id];
  if (!block) return doc;
  return { ...doc, blocks: { ...doc.blocks, [id]: fn(block) } };
};

export const putBlocks = (doc: MarDocument, blocks: MarBlock[]): MarDocument => {
  if (!blocks.length) return doc;
  const next = { ...doc.blocks };
  for (const block of blocks) next[block.id] = block;
  return { ...doc, blocks: next };
};

const setSiblings = (
  doc: MarDocument,
  parentId: BlockId | null,
  ids: BlockId[],
): MarDocument => {
  if (parentId === null) return { ...doc, root: ids };
  return updateBlock(doc, parentId, (block) => withChildIds(block, ids));
};

export const insertBlock = (
  doc: MarDocument,
  block: MarBlock,
  parentId: BlockId | null,
  index: number,
): MarDocument => {
  const withBlock = putBlocks(doc, [block]);
  const ids = [...siblingIds(withBlock, parentId)];
  ids.splice(Math.max(0, Math.min(index, ids.length)), 0, block.id);
  return setSiblings(withBlock, parentId, ids);
};

export const unlinkBlock = (doc: MarDocument, id: BlockId): MarDocument => {
  if (doc.root.includes(id)) {
    return { ...doc, root: doc.root.filter((rootId) => rootId !== id) };
  }
  const parentId = parentOf(doc, id);
  if (parentId === null) return doc;
  return updateBlock(doc, parentId, (block) =>
    withChildIds(
      block,
      childIds(block).filter((childId) => childId !== id),
    ),
  );
};

export const removeBlock = (doc: MarDocument, id: BlockId): MarDocument => {
  if (!doc.blocks[id]) return doc;
  const dropped = new Set([id, ...descendantIds(doc, id)]);
  const unlinked = unlinkBlock(doc, id);
  const blocks: Record<BlockId, MarBlock> = {};
  for (const [blockId, block] of Object.entries(unlinked.blocks)) {
    if (!dropped.has(blockId)) blocks[blockId] = block;
  }
  return { ...unlinked, blocks };
};

export const moveBlock = (
  doc: MarDocument,
  id: BlockId,
  parentId: BlockId | null,
  index: number,
): MarDocument => {
  const block = doc.blocks[id];
  if (!block) return doc;
  const unlinked = unlinkBlock(doc, id);
  const ids = [...siblingIds(unlinked, parentId)];
  ids.splice(Math.max(0, Math.min(index, ids.length)), 0, id);
  return setSiblings(unlinked, parentId, ids);
};

export const isBlockLocked = (block: MarBlock): boolean =>
  block.edit === "lockBlock" || block.edit === "locked";

export const isContentLocked = (block: MarBlock): boolean =>
  block.edit === "lockContent" || block.edit === "locked";

export const ancestorContentLocked = (doc: MarDocument, id: BlockId): boolean => {
  const path = pathOf(doc, id);
  if (!path) return false;
  return path
    .slice(0, -1)
    .some((ancestorId) => isContentLocked(doc.blocks[ancestorId] as MarBlock));
};
