import type { BlockEngine } from "../engine/BlockEngine";
import type { BlockId } from "../model/types";
import { accepts, isLayout } from "../model/schema";
import { acceptsAtRoot, adapt } from "../ops/blocks";
import { getBlock, containsId, locate, childIds as childIdsOf } from "../model/tree";
import { blockEl, isHorizontalContainer } from "./dom";

const LIST_CONTAINERS = new Set(["bulletList", "orderedList", "taskList"]);
const COLUMN_CONTAINERS = new Set(["columnList", "column"]);

export interface DropTarget {
  parentId: BlockId | null;
  refId: BlockId | null;
  before: boolean;
  indicator: {
    orientation: "horizontal" | "vertical";
    top: number;
    left: number;
    length: number;
  };
}

const containerElsUnder = (
  root: HTMLElement,
  engine: BlockEngine,
  x: number,
  y: number,
): { id: BlockId; el: HTMLElement; depth: number }[] => {
  const out: { id: BlockId; el: HTMLElement; depth: number }[] = [];
  const els = Array.from(root.querySelectorAll<HTMLElement>("[data-block-id]"));
  for (const el of els) {
    const id = el.getAttribute("data-block-id");
    if (!id) continue;
    const block = getBlock(engine.doc.value, id);
    if (!block || !isLayout(block.kind)) continue;
    const r = el.getBoundingClientRect();
    if (x < r.left - 4 || x > r.right + 4 || y < r.top || y > r.bottom) continue;
    let depth = 0;
    let node: HTMLElement | null = el.parentElement;
    while (node && node !== root) {
      if (node.hasAttribute("data-block-id")) depth += 1;
      node = node.parentElement;
    }
    out.push({ id, el, depth });
  }
  return out.sort((a, b) => b.depth - a.depth);
};

export const computeDropTarget = (
  engine: BlockEngine,
  root: HTMLElement,
  frame: HTMLElement,
  x: number,
  y: number,
  dragId: BlockId | null,
): DropTarget | null => {
  const drag = dragId ? getBlock(engine.doc.value, dragId) : null;
  if (dragId && !drag) return null;
  const rootRect = frame.getBoundingClientRect();

  const tryContainer = (
    parentId: BlockId | null,
    containerEl: HTMLElement,
    childIds: BlockId[],
  ): DropTarget | null => {
    const parentKind = parentId ? getBlock(engine.doc.value, parentId)?.kind ?? null : null;
    if (drag) {
      const adapted = adapt(engine.doc.value, drag, parentKind).block;
      const allowed =
        parentId === null
          ? acceptsAtRoot(engine.doc.value, adapted.kind)
          : accepts(parentKind, adapted.kind);
      if (!allowed) return null;
    }

    const horizontal = isHorizontalContainer(containerEl);
    const candidates = childIds
      .filter((id) => id !== dragId && (!drag || !containsId(engine.doc.value, drag.id, id)))
      .map((id) => ({ id, el: blockEl(root, id) }))
      .filter((c): c is { id: BlockId; el: HTMLElement } => !!c.el);

    if (!candidates.length) {
      const r = containerEl.getBoundingClientRect();
      return {
        parentId,
        refId: null,
        before: true,
        indicator: {
          orientation: horizontal ? "vertical" : "horizontal",
          top: r.top - rootRect.top + 2,
          left: r.left - rootRect.left + 2,
          length: horizontal ? r.height - 4 : r.width - 4,
        },
      };
    }

    const last = candidates[candidates.length - 1] as { id: BlockId; el: HTMLElement };
    const coord = horizontal ? x : y;
    let chosen: { id: BlockId; el: HTMLElement } = last;
    let refRect = last.el.getBoundingClientRect();
    let after = true;
    for (let i = 0; i < candidates.length; i += 1) {
      const cand = candidates[i] as { id: BlockId; el: HTMLElement };
      const r = cand.el.getBoundingClientRect();
      const start = horizontal ? r.left : r.top;
      const end = horizontal ? r.right : r.bottom;
      if (coord < start) {
        chosen = cand;
        refRect = r;
        after = false;
        break;
      }
      if (coord <= end) {
        chosen = cand;
        refRect = r;
        after = coord >= (start + end) / 2;
        break;
      }
    }

    const refId = chosen.id;

    const line = horizontal
      ? {
          orientation: "vertical" as const,
          top: refRect.top - rootRect.top,
          left: (after ? refRect.right : refRect.left) - rootRect.left,
          length: refRect.height,
        }
      : {
          orientation: "horizontal" as const,
          top: (after ? refRect.bottom : refRect.top) - rootRect.top,
          left: refRect.left - rootRect.left,
          length: refRect.width,
        };
    return { parentId, refId, before: !after, indicator: line };
  };

  if (drag && (drag.kind === "listItem" || drag.kind === "taskItem")) {
    let topId = dragId as BlockId;
    for (let i = 0; i < 32; i += 1) {
      const l = locate(engine.doc.value, topId);
      if (!l || l.parentId === null) break;
      topId = l.parentId;
    }
    const inTree = (id: BlockId): boolean =>
      containsId(engine.doc.value, topId, id);
    for (const container of containerElsUnder(root, engine, x, y)) {
      const cblock = getBlock(engine.doc.value, container.id);
      if (!cblock || !LIST_CONTAINERS.has(cblock.kind) || !inTree(container.id)) continue;
      const result = tryContainer(container.id, container.el, childIdsOf(cblock));
      if (result) return result;
    }
    const loc = locate(engine.doc.value, dragId as BlockId);
    const parentId = loc?.parentId ?? null;
    const parentEl = parentId ? blockEl(root, parentId) : null;
    if (parentId && parentEl) {
      return tryContainer(parentId, parentEl, childIdsOf(getBlock(engine.doc.value, parentId)));
    }
    return null;
  }

  for (const container of containerElsUnder(root, engine, x, y)) {
    const block = getBlock(engine.doc.value, container.id);
    if (!block || !(COLUMN_CONTAINERS.has(block.kind) || block.kind === "section")) continue;
    const result = tryContainer(container.id, container.el, childIdsOf(block));
    if (result) return result;
  }

  return tryContainer(null, root, engine.doc.value.root);
};
