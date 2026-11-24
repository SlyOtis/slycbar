import { computed, onBeforeUnmount, ref, type Ref } from "vue";
import type { BlockEngine } from "../engine/BlockEngine";
import type { BlockId } from "../model/types";
import { getBlock, locate } from "../model/tree";
import { blockEl, deepestBlockIdAt, rectInRoot } from "./dom";

const LIST_TYPES = new Set(["bulletList", "orderedList", "taskList"]);

const handleTargetId = (engine: BlockEngine, id: BlockId): BlockId => {
  let current = id;
  for (let i = 0; i < 32; i += 1) {
    const loc = locate(engine.doc.value, current);
    if (!loc) return current;
    const parentKind = loc.parentId
      ? getBlock(engine.doc.value, loc.parentId)?.kind ?? null
      : null;
    if (
      loc.parentId === null ||
      parentKind === "column" ||
      parentKind === "section" ||
      LIST_TYPES.has(parentKind ?? "")
    )
      return current;
    current = loc.parentId;
  }
  return current;
};

const topLevelId = (engine: BlockEngine, id: BlockId): BlockId => {
  let current = id;
  for (let i = 0; i < 32; i += 1) {
    const loc = locate(engine.doc.value, current);
    if (!loc || loc.parentId === null) return current;
    current = loc.parentId;
  }
  return current;
};

const resolveTarget = (
  engine: BlockEngine,
  root: HTMLElement,
  x: number,
  y: number,
  currentId: BlockId | null,
): BlockId | null => {
  if (currentId) {
    const cur = getBlock(engine.doc.value, currentId);
    if (cur && (cur.kind === "listItem" || cur.kind === "taskItem")) {
      const curEl = blockEl(root, currentId);
      if (curEl) {
        const r = curEl.getBoundingClientRect();
        if (y >= r.top && y <= r.bottom) return currentId;
      }
    }
  }
  const deepest = deepestBlockIdAt(root, x, y);
  if (!deepest) return null;
  const target = handleTargetId(engine, deepest);
  const block = getBlock(engine.doc.value, target);
  if (block && LIST_TYPES.has(block.kind)) {
    const loc = locate(engine.doc.value, target);
    const parentKind = loc?.parentId
      ? getBlock(engine.doc.value, loc.parentId)?.kind ?? null
      : null;
    if (parentKind === "section") return null;
  }
  if (block && (block.kind === "listItem" || block.kind === "taskItem")) {
    const itemEl = blockEl(root, target);
    if (itemEl && x < itemEl.getBoundingClientRect().left) {
      return topLevelId(engine, target);
    }
  }
  return target;
};

export const useBlockHover = (
  engine: BlockEngine,
  rootRef: Ref<HTMLElement | null>,
  frameRef: Ref<HTMLElement | null>,
  isDragging: Ref<boolean>,
) => {
  const hoveredId = ref<BlockId | null>(null);
  const top = ref(0);
  const left = ref(0);
  const overHandle = ref(false);
  const menuOpen = ref(false);
  let raf = 0;

  const position = (): void => {
    const root = rootRef.value;
    const frame = frameRef.value;
    if (!hoveredId.value || !root || !frame) return;
    const el = blockEl(root, hoveredId.value);
    if (!el) return;
    const r = rectInRoot(el, frame);
    const cs = getComputedStyle(el);
    const padTop = parseFloat(cs.paddingTop) || 0;
    const padBottom = parseFloat(cs.paddingBottom) || 0;
    const fontSize = parseFloat(cs.fontSize) || 16;
    let lineH = parseFloat(cs.lineHeight);
    if (!Number.isFinite(lineH)) lineH = fontSize * 1.4;
    const contentH = r.height - padTop - padBottom;
    const center =
      contentH <= lineH * 1.4
        ? r.top + r.height / 2
        : r.top + padTop + lineH / 2;
    top.value = center + frame.scrollTop - frame.clientTop;
    let anchorLeft = r.left;
    let cur = locate(engine.doc.value, hoveredId.value);
    while (cur?.parentId) {
      const parent = getBlock(engine.doc.value, cur.parentId);
      if (parent?.kind === "section") {
        const sectionEl = blockEl(root, cur.parentId);
        if (sectionEl) anchorLeft = rectInRoot(sectionEl, frame).left;
        break;
      }
      cur = locate(engine.doc.value, cur.parentId);
    }
    left.value = anchorLeft + frame.scrollLeft - frame.clientLeft;
  };

  const onPointerMove = (e: PointerEvent): void => {
    if (menuOpen.value || isDragging.value) return;
    overHandle.value = false;
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(() => {
      const root = rootRef.value;
      if (!root) return;
      const id = resolveTarget(engine, root, e.clientX, e.clientY, hoveredId.value);
      if (id !== hoveredId.value) {
        hoveredId.value = id;
        position();
      }
    });
  };

  const onPointerLeave = (e: PointerEvent): void => {
    const to = e.relatedTarget as HTMLElement | null;
    if (to?.closest(".mar-block-handle-group")) {
      overHandle.value = true;
      return;
    }
    if (menuOpen.value) return;
    hoveredId.value = null;
  };

  const bind = (): void => {
    const root = rootRef.value;
    if (!root) return;
    root.addEventListener("pointermove", onPointerMove);
    root.addEventListener("pointerleave", onPointerLeave);
  };

  onBeforeUnmount(() => {
    const root = rootRef.value;
    root?.removeEventListener("pointermove", onPointerMove);
    root?.removeEventListener("pointerleave", onPointerLeave);
    cancelAnimationFrame(raf);
  });

  return {
    hoveredId,
    top,
    left,
    overHandle,
    menuOpen,
    visible: computed(() => !!hoveredId.value && !isDragging.value),
    bind,
    reposition: position,
  };
};
