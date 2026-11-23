import * as Y from "yjs";
import type { BlockId, Delta, MarBlock, MarDocument } from "../model/types";
import { isTextOp, sameMarks } from "../model/delta";
import { childIds } from "../model/tree";
import { blockToY, contentToYText, deltaToY, type YDeltaOp } from "./yDoc";

const plainText = (content: Delta): string =>
  content.map((op) => (isTextOp(op) ? op.insert : " ")).join("");

const sameAttributes = (a: Delta, b: Delta): boolean =>
  a.length === b.length && a.every((op, i) => sameMarks(op, b[i] as Delta[number]));

const attributesAt = (content: Delta, offset: number): Record<string, unknown> | undefined => {
  let seen = 0;
  for (const op of content) {
    const len = isTextOp(op) ? op.insert.length : 1;
    if (offset <= seen + len) {
      if (isTextOp(op)) return (deltaToY([op])[0] as YDeltaOp | undefined)?.attributes;
      return undefined;
    }
    seen += len;
  }
  return undefined;
};

const diffText = (ytext: Y.Text, prev: Delta, next: Delta): void => {
  const structural = prev.some((op) => !isTextOp(op)) || next.some((op) => !isTextOp(op));
  const prevPlain = plainText(prev);
  const nextPlain = plainText(next);
  const marksEqual = sameAttributes(prev, next);

  if (prevPlain === nextPlain && marksEqual) return;

  if (structural || (prevPlain === nextPlain && !marksEqual)) {
    ytext.delete(0, ytext.length);
    ytext.applyDelta(deltaToY(next));
    return;
  }

  let prefix = 0;
  const maxPrefix = Math.min(prevPlain.length, nextPlain.length);
  while (prefix < maxPrefix && prevPlain[prefix] === nextPlain[prefix]) prefix++;

  let suffix = 0;
  const maxSuffix = Math.min(prevPlain.length, nextPlain.length) - prefix;
  while (
    suffix < maxSuffix &&
    prevPlain[prevPlain.length - 1 - suffix] === nextPlain[nextPlain.length - 1 - suffix]
  ) {
    suffix++;
  }

  const deleteLen = prevPlain.length - prefix - suffix;
  const insertStr = nextPlain.slice(prefix, nextPlain.length - suffix);

  if (deleteLen > 0) ytext.delete(prefix, deleteLen);
  if (insertStr.length > 0) {
    ytext.insert(prefix, insertStr, attributesAt(next, prefix + 1));
  }

  if (!marksEqual) {
    ytext.delete(0, ytext.length);
    ytext.applyDelta(deltaToY(next));
  }
};

const syncRecord = (
  map: Y.Map<unknown>,
  key: string,
  prev: Record<string, unknown>,
  next: Record<string, unknown>,
): void => {
  const target = map.get(key) as Y.Map<unknown> | undefined;
  if (!target) return;
  for (const name of Object.keys(prev)) {
    if (!(name in next)) target.delete(name);
  }
  for (const [name, value] of Object.entries(next)) {
    if (JSON.stringify(prev[name]) !== JSON.stringify(value)) target.set(name, value);
  }
};

const syncBlock = (
  map: Y.Map<unknown>,
  prevDoc: MarDocument,
  nextDoc: MarDocument,
  prev: MarBlock,
  next: MarBlock,
): void => {
  if (prev.kind !== next.kind) map.set("kind", next.kind);
  if (prev.edit !== next.edit) map.set("edit", next.edit);
  if (prev.read !== next.read) map.set("read", next.read);
  if (prev.inherits !== next.inherits) map.set("inherits", next.inherits);
  if (prev.fontFamily !== next.fontFamily) map.set("fontFamily", next.fontFamily);
  if (prev.fontSize !== next.fontSize) map.set("fontSize", next.fontSize);
  if (prev.lineHeight !== next.lineHeight) map.set("lineHeight", next.lineHeight);
  syncRecord(map, "options", prev.options, next.options);
  syncRecord(map, "attr", prev.attr, next.attr);

  const prevDelta = Array.isArray(prev.content) ? prev.content : null;
  const nextDelta = Array.isArray(next.content) ? next.content : null;
  if (nextDelta && !prevDelta) {
    map.delete("children");
    map.set("content", contentToYText(nextDelta));
  } else if (!nextDelta && prevDelta) {
    map.delete("content");
  } else if (nextDelta && prevDelta) {
    const ytext = map.get("content") as Y.Text | undefined;
    if (ytext) diffText(ytext, prevDelta, nextDelta);
    else map.set("content", contentToYText(nextDelta));
  }

  if (nextDelta) return;

  const prevChildren = childIds(prev);
  const nextChildren = childIds(next);
  const arr = map.get("children") as Y.Array<Y.Map<unknown>> | undefined;
  if (!arr) {
    const children = new Y.Array<Y.Map<unknown>>();
    children.insert(
      0,
      nextChildren
        .map((id) => blockToY(nextDoc, id))
        .filter((child): child is Y.Map<unknown> => child !== null),
    );
    map.set("children", children);
    return;
  }
  syncBlockArray(arr, prevDoc, nextDoc, prevChildren, nextChildren);
};

const syncBlockArray = (
  arr: Y.Array<Y.Map<unknown>>,
  prevDoc: MarDocument,
  nextDoc: MarDocument,
  prev: BlockId[],
  next: BlockId[],
): void => {
  const nextIds = new Set(next);

  for (let i = arr.length - 1; i >= 0; i--) {
    const id = (arr.get(i) as Y.Map<unknown>).get("id") as string;
    if (!nextIds.has(id)) arr.delete(i, 1);
  }

  for (let i = 0; i < next.length; i++) {
    const id = next[i] as BlockId;
    const block = nextDoc.blocks[id];
    if (!block) continue;
    let currentIndex = -1;
    for (let j = i; j < arr.length; j++) {
      if (((arr.get(j) as Y.Map<unknown>).get("id") as string) === id) {
        currentIndex = j;
        break;
      }
    }
    const made = (): void => {
      const built = blockToY(nextDoc, id);
      if (built) arr.insert(i, [built]);
    };
    if (currentIndex === -1) {
      made();
      continue;
    }
    if (currentIndex !== i) {
      arr.delete(currentIndex, 1);
      made();
      continue;
    }
    const previous = prevDoc.blocks[id];
    if (previous && prev.includes(id)) {
      syncBlock(arr.get(i) as Y.Map<unknown>, prevDoc, nextDoc, previous, block);
    }
  }
};

export const applyDocDiff = (
  root: Y.Array<Y.Map<unknown>>,
  prev: MarDocument,
  next: MarDocument,
): void => {
  syncBlockArray(root, prev, next, prev.root, next.root);
};
