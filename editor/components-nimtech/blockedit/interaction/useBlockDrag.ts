import { onBeforeUnmount, ref, shallowRef, type Ref } from "vue";
import type { BlockEngine } from "../engine/BlockEngine";
import type { BlockId } from "../model/types";
import { makeBlock } from "../model/schema";
import { insertBlock, locate } from "../model/tree";
import { blockEl } from "./dom";
import { computeDropTarget, type DropTarget } from "./dropTarget";
import { dropBlock } from "../ops/blocks";

const THRESHOLD = 4;
const ACTIVE_CLASS = "mar-block-drop-active";
const BEFORE_CLASS = "mar-block-drop-before";
const AFTER_CLASS = "mar-block-drop-after";

export interface ExternalDrag {
  label: string;
  insert: (engine: BlockEngine) => void;
}

export const useBlockDrag = (
  engine: BlockEngine,
  rootRef: Ref<HTMLElement | null>,
  frameRef: Ref<HTMLElement | null>,
) => {
  const dragging = ref(false);
  const dropTarget = shallowRef<DropTarget | null>(null);
  const ghostHtml = ref("");
  const ghostChip = ref(false);
  const ghostX = ref(0);
  const ghostY = ref(0);
  let dragId: BlockId | null = null;
  let external: ExternalDrag | null = null;
  let startX = 0;
  let startY = 0;
  let activeEl: HTMLElement | null = null;

  const setActive = (target: DropTarget | null): void => {
    const root = rootRef.value;
    const id = target?.refId ?? target?.parentId ?? null;
    const next = id && root ? blockEl(root, id) : null;
    if (next !== activeEl) {
      activeEl?.classList.remove(ACTIVE_CLASS, BEFORE_CLASS, AFTER_CLASS);
      activeEl = next;
    }
    if (!next || !target) return;
    next.classList.add(ACTIVE_CLASS);
    next.classList.toggle(BEFORE_CLASS, !!target.refId && target.before);
    next.classList.toggle(AFTER_CLASS, !!target.refId && !target.before);
  };

  const begin = (): void => {
    dragging.value = true;
    if (external) {
      ghostChip.value = true;
      ghostHtml.value = `<span class="mar-block-drag-ghost-inner">${external.label}</span>`;
    } else if (dragId && rootRef.value) {
      ghostChip.value = false;
      ghostHtml.value = blockEl(rootRef.value, dragId)?.outerHTML ?? "";
    }
  };

  const onMove = (e: PointerEvent): void => {
    if (!dragId && !external) return;
    if (!dragging.value) {
      if (Math.hypot(e.clientX - startX, e.clientY - startY) < THRESHOLD) return;
      begin();
    }
    ghostX.value = e.clientX;
    ghostY.value = e.clientY;
    const root = rootRef.value;
    const frame = frameRef.value;
    if (root && frame) {
      const target = computeDropTarget(engine, root, frame, e.clientX, e.clientY, dragId);
      dropTarget.value = target;
      setActive(target);
    }
  };

  let captureEl: Element | null = null;
  let capturedPointer: number | null = null;

  const cleanup = (): void => {
    document.removeEventListener("pointermove", onMove);
    document.removeEventListener("pointerup", onUp);
    document.removeEventListener("pointercancel", onCancel);
    window.removeEventListener("blur", onCancel);
    if (captureEl && capturedPointer !== null && captureEl.hasPointerCapture(capturedPointer)) {
      captureEl.releasePointerCapture(capturedPointer);
    }
    captureEl = null;
    capturedPointer = null;
    setActive(null);
    dragId = null;
    external = null;
    dragging.value = false;
    dropTarget.value = null;
    ghostHtml.value = "";
    ghostChip.value = false;
  };

  const onUp = (): void => {
    const target = dropTarget.value;
    const id = dragId;
    const ext = external;
    if (dragging.value && target) {
      if (ext) {
        engine.dispatch((doc) => {
          const paragraph = makeBlock("paragraph");
          let next;
          if (target.refId) {
            const loc = locate(doc, target.refId);
            next = loc
              ? insertBlock(doc, paragraph, loc.parentId, loc.index + (target.before ? 0 : 1))
              : insertBlock(doc, paragraph, target.parentId, 0);
          } else {
            next = insertBlock(doc, paragraph, target.parentId, 0);
          }
          return {
            doc: next,
            selection: {
              kind: "text",
              anchor: { blockId: paragraph.id, offset: 0 },
              head: { blockId: paragraph.id, offset: 0 },
            },
          };
        });
        ext.insert(engine);
      } else if (id) {
        engine.dispatch((doc) =>
          dropBlock(doc, id, target.parentId, target.refId, target.before),
        );
      }
    }
    cleanup();
  };

  const onCancel = (): void => cleanup();

  const addListeners = (e: PointerEvent): void => {
    document.addEventListener("pointermove", onMove);
    document.addEventListener("pointerup", onUp);
    document.addEventListener("pointercancel", onCancel);
    window.addEventListener("blur", onCancel);
    const target = e.target as Element | null;
    if (target && typeof target.setPointerCapture === "function") {
      try {
        target.setPointerCapture(e.pointerId);
        captureEl = target;
        capturedPointer = e.pointerId;
      } catch {
        captureEl = null;
        capturedPointer = null;
      }
    }
  };

  const start = (e: PointerEvent, id: BlockId): void => {
    if (e.button !== 0) return;
    e.preventDefault();
    dragId = id;
    external = null;
    startX = e.clientX;
    startY = e.clientY;
    addListeners(e);
  };

  const startExternal = (e: PointerEvent, payload: ExternalDrag): void => {
    e.preventDefault();
    external = payload;
    dragId = null;
    startX = e.clientX;
    startY = e.clientY;
    addListeners(e);
  };

  onBeforeUnmount(cleanup);

  return {
    dragging,
    dropTarget,
    ghostHtml,
    ghostChip,
    ghostX,
    ghostY,
    start,
    startExternal,
  };
};
