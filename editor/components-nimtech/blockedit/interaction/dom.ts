import type { BlockId } from "../model/types";

export const GUTTER_REACH = 32;

export const blockIdOf = (el: Element | null): BlockId | null => {
  const block = el?.closest("[data-block-id]") as HTMLElement | null;
  return block?.getAttribute("data-block-id") ?? null;
};

export const blockEl = (root: HTMLElement, id: BlockId): HTMLElement | null =>
  root.querySelector<HTMLElement>(`[data-block-id="${id}"]`);

const ancestorBlockDepth = (el: HTMLElement, root: HTMLElement): number => {
  let depth = 0;
  let node = el.parentElement;
  while (node && node !== root) {
    if (node.hasAttribute("data-block-id")) depth += 1;
    node = node.parentElement;
  }
  return depth;
};

export const deepestBlockIdAt = (
  root: HTMLElement,
  x: number,
  y: number,
): BlockId | null => {
  const hit = document.elementFromPoint(x, y);
  if (hit && root.contains(hit)) {
    const id = blockIdOf(hit);
    if (id) return id;
  }

  const blocks = Array.from(
    root.querySelectorAll<HTMLElement>("[data-block-id]"),
  );
  let best: HTMLElement | null = null;
  let bestDepth = -1;
  let nearest: HTMLElement | null = null;
  let nearestDist = Infinity;

  for (const el of blocks) {
    const r = el.getBoundingClientRect();
    if (x > r.right + 1) continue;
    if (x < r.left - GUTTER_REACH) continue;
    const dist = y < r.top ? r.top - y : y > r.bottom ? y - r.bottom : 0;
    if (dist < nearestDist) {
      nearestDist = dist;
      nearest = el;
    }
    if (y >= r.top && y <= r.bottom) {
      const depth = ancestorBlockDepth(el, root);
      if (depth > bestDepth) {
        bestDepth = depth;
        best = el;
      }
    }
  }
  return (best ?? nearest)?.getAttribute("data-block-id") ?? null;
};

export const rectInRoot = (
  el: HTMLElement,
  root: HTMLElement,
): { top: number; left: number; width: number; height: number } => {
  const r = el.getBoundingClientRect();
  const rootRect = root.getBoundingClientRect();
  return {
    top: r.top - rootRect.top,
    left: r.left - rootRect.left,
    width: r.width,
    height: r.height,
  };
};

export const isHorizontalContainer = (el: HTMLElement): boolean => {
  const type = el.getAttribute("data-type");
  return type === "column-list" || el.tagName.toLowerCase() === "tr";
};
