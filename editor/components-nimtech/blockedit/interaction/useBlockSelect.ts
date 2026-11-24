import { nextTick, onBeforeUnmount, watch, type Ref } from "vue";
import type { BlockEngine } from "../engine/BlockEngine";
import type { BlockId, MarDocument, Selection } from "../model/types";
import {
  adjacentBlockId,
  blockRange,
  childIds,
  getBlock,
  insertBlock,
  locate,
  removeBlock,
} from "../model/tree";
import { accepts, contentShapeOf, makeBlock } from "../model/schema";
import { blockEl, blockIdOf, deepestBlockIdAt } from "./dom";
import {
  caretAtEdge,
  caretOffset,
  clearNativeSelection,
  offsetAtNode,
  setCaret,
  setRange,
} from "../selection/domMap";
import { blockTextLength } from "../selection/outwards";

const TEXT_HOST = ".mar-be-text";

const sameIds = (selection: Selection | null, ids: BlockId[]): boolean =>
  selection?.kind === "blocks" &&
  selection.ids.length === ids.length &&
  selection.ids.every((id, index) => ids[index] === id);

export const useBlockSelect = (
  engine: BlockEngine,
  rootRef: Ref<HTMLElement | null>,
) => {
  let anchorId: BlockId | null = null;
  let pressing = false;
  let written: Selection | null = null;

  const hostOf = (node: Node | null, root: HTMLElement): HTMLElement | null => {
    if (!node) return null;
    const el = node instanceof Element ? node : node.parentElement;
    const host = el?.closest<HTMLElement>(TEXT_HOST) ?? null;
    return host && root.contains(host) ? host : null;
  };

  const caretHost = (): HTMLElement | null => {
    const root = rootRef.value;
    if (!root) return null;
    const sel = window.getSelection();
    if (!sel) return null;
    const host = hostOf(sel.anchorNode, root);
    return host && hostOf(sel.focusNode, root) === host ? host : null;
  };

  const write = (selection: Selection | null): void => {
    written = selection;
    engine.setSelection(selection);
  };

  const selectBlocks = (ids: BlockId[]): void => {
    clearNativeSelection();
    if (sameIds(engine.selection.value, ids)) return;
    write({ kind: "blocks", ids });
  };

  const onSelectionChange = (): void => {
    if (!engine.editable.value) return;
    if (engine.selection.value?.kind === "blocks") {
      if (window.getSelection()?.rangeCount) clearNativeSelection();
      return;
    }
    const host = caretHost();
    const id = host ? blockIdOf(host) : null;
    if (!host || !id) return;
    const sel = window.getSelection();
    if (!sel || !sel.anchorNode || !sel.focusNode) return;
    write({
      kind: "text",
      anchor: { blockId: id, offset: offsetAtNode(host, sel.anchorNode, sel.anchorOffset) },
      head: { blockId: id, offset: offsetAtNode(host, sel.focusNode, sel.focusOffset) },
    });
  };

  const onPointerDown = (e: PointerEvent): void => {
    const root = rootRef.value;
    if (e.button !== 0 || !root) return;
    pressing = true;
    anchorId = deepestBlockIdAt(root, e.clientX, e.clientY);
    if (!anchorId) return;
    const block = getBlock(engine.doc.value, anchorId);
    if (block && contentShapeOf(block) === "none") {
      selectBlocks([anchorId]);
      return;
    }
    if (engine.selection.value?.kind === "blocks") write(null);
  };

  const onPointerMove = (e: PointerEvent): void => {
    if (!pressing || !anchorId) return;
    if ((e.buttons & 1) === 0) {
      pressing = false;
      return;
    }
    const root = rootRef.value;
    if (!root) return;
    const over = deepestBlockIdAt(root, e.clientX, e.clientY);
    if (!over) return;
    if (over === anchorId) {
      if (engine.selection.value?.kind === "blocks") write(null);
      return;
    }
    const ids = blockRange(engine.doc.value, anchorId, over);
    if (ids.length) selectBlocks(ids);
  };

  const onPointerUp = (): void => {
    pressing = false;
  };

  const extend = (dir: -1 | 1): boolean => {
    const doc = engine.doc.value;
    const selection = engine.selection.value;
    if (selection?.kind === "blocks" && selection.ids.length) {
      const head = dir === 1 ? selection.ids[selection.ids.length - 1] : selection.ids[0];
      const tail = dir === 1 ? selection.ids[0] : selection.ids[selection.ids.length - 1];
      const next = head ? adjacentBlockId(doc, head, dir) : null;
      if (!next || !tail) return false;
      const from = anchorId && selection.ids.includes(anchorId) ? anchorId : tail;
      const ids = blockRange(doc, from, next);
      if (!ids.length) return false;
      selectBlocks(ids);
      return true;
    }
    const from =
      selection?.kind === "text"
        ? selection.anchor.blockId
        : selection?.kind === "node"
          ? selection.blockId
          : engine.currentBlockId();
    if (!from) return false;
    const next = adjacentBlockId(doc, from, dir);
    if (!next) return false;
    const ids = blockRange(doc, from, next);
    if (!ids.length) return false;
    anchorId = from;
    selectBlocks(ids);
    return true;
  };

  const extendVertically = (dir: -1 | 1): boolean => {
    if (engine.selection.value?.kind === "blocks") return extend(dir);
    const host = caretHost();
    if (!host || !caretAtEdge(host, dir)) return false;
    return extend(dir);
  };

  const extendHorizontally = (dir: -1 | 1): boolean => {
    if (engine.selection.value?.kind === "blocks") return extend(dir);
    const host = caretHost();
    const id = host ? blockIdOf(host) : null;
    if (!host || !id) return false;
    const offset = caretOffset(host);
    const block = getBlock(engine.doc.value, id);
    if (offset === null || !block) return false;
    if (dir === -1 ? offset !== 0 : offset !== blockTextLength(block)) return false;
    return extend(dir);
  };

  const textEdge = (
    doc: MarDocument,
    id: BlockId,
    dir: -1 | 1,
  ): { blockId: BlockId; offset: number } | null => {
    const block = getBlock(doc, id);
    if (!block) return null;
    if (Array.isArray(block.content)) {
      return { blockId: id, offset: dir === -1 ? 0 : blockTextLength(block) };
    }
    const children = childIds(block);
    for (const child of dir === -1 ? children : [...children].reverse()) {
      const found = textEdge(doc, child, dir);
      if (found) return found;
    }
    return null;
  };

  const collapse = (dir: -1 | 1): boolean => {
    const selection = engine.selection.value;
    if (selection?.kind !== "blocks" || !selection.ids.length) return false;
    const edgeId = dir === -1 ? selection.ids[0] : selection.ids[selection.ids.length - 1];
    if (!edgeId) return false;
    anchorId = null;
    const at = textEdge(engine.doc.value, edgeId, dir);
    if (!at) {
      if (selection.ids.length === 1) return false;
      selectBlocks([edgeId]);
      return true;
    }
    engine.setSelection({ kind: "text", anchor: at, head: at });
    return true;
  };

  const deleteSelected = (): boolean => {
    const selection = engine.selection.value;
    if (selection?.kind !== "blocks" || !selection.ids.length) return false;
    const ids = [...selection.ids];
    engine.dispatch((doc) => {
      const at = locate(doc, ids[0] as BlockId);
      const parentKind = at?.parentId ? getBlock(doc, at.parentId)?.kind ?? null : null;
      let next = doc;
      for (const id of ids) next = removeBlock(next, id);
      if (!accepts(parentKind, "paragraph")) return { doc: next, selection: null };
      const paragraph = makeBlock("paragraph");
      next = insertBlock(next, paragraph, at?.parentId ?? null, at?.index ?? 0);
      return {
        doc: next,
        selection: {
          kind: "text",
          anchor: { blockId: paragraph.id, offset: 0 },
          head: { blockId: paragraph.id, offset: 0 },
        },
      };
    });
    return true;
  };

  watch(
    () => engine.selection.value,
    (selection) => {
      if (selection === written) return;
      if (!rootRef.value) return;
      if (!selection || selection.kind !== "text") {
        clearNativeSelection();
        return;
      }
      void nextTick(() => {
        const root = rootRef.value;
        if (!root) return;
        const target = blockEl(root, selection.head.blockId);
        if (!target) return;
        target.focus();
        if (
          selection.anchor.blockId === selection.head.blockId &&
          selection.anchor.offset !== selection.head.offset
        ) {
          setRange(target, selection.anchor.offset, selection.head.offset);
        } else {
          setCaret(target, selection.head.offset);
        }
      });
    },
  );

  const bind = (): void => {
    const root = rootRef.value;
    if (!root) return;
    root.addEventListener("pointerdown", onPointerDown);
    root.addEventListener("pointermove", onPointerMove);
    document.addEventListener("pointerup", onPointerUp);
    document.addEventListener("selectionchange", onSelectionChange);
  };

  onBeforeUnmount(() => {
    const root = rootRef.value;
    root?.removeEventListener("pointerdown", onPointerDown);
    root?.removeEventListener("pointermove", onPointerMove);
    document.removeEventListener("pointerup", onPointerUp);
    document.removeEventListener("selectionchange", onSelectionChange);
  });

  return { bind, extendVertically, extendHorizontally, collapse, deleteSelected };
};
