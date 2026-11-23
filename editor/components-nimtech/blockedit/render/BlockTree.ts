import { defineComponent, h, provide, type Component, type PropType, type VNode } from "vue";
import type { BlockId, Delta, MarBlock } from "../model/types";
import type { BlockEngine } from "../engine/BlockEngine";
import { contentShapeOf, isTextKind } from "../model/schema";
import { childIds, updateBlock, removeBlock, locate } from "../model/tree";
import { deltaText, textOp } from "../model/delta";
import { addColumn, addRow, deleteColumn, deleteRow } from "../ops/table";
import {
  blockTag,
  blockAttrs,
  blockClass,
  headingMeta,
  isBlockSelected,
  READONLY_LINK_TYPES,
  readonlyMeta,
} from "./nodeProps";
import { resolveBlockView } from "./views/registry";
import { BLOCK_CHILDREN } from "./views/nodeViewBridge";
import { MarBlockEditText } from "./MarBlockEditText";
import MarTitleBlock from "@/components/MarTitleBlock";
import MarIcon from "@/components/MarIcon";
import MarCheckboxInput from "@/components/MarCheckboxInput";
import type { IconType } from "@/types/icon.types";
import { openModal, type ModalHandle } from "@/composables/useModals";

const tip = (text: string): Record<string, unknown> => {
  let handle: ModalHandle | null = null;
  return {
    onMouseenter: (e: MouseEvent) => {
      handle = openModal({
        kind: "tooltip",
        text,
        anchor: e.currentTarget as HTMLElement,
        placement: { side: "bottom" },
      });
    },
    onMouseleave: () => handle?.close(),
  };
};

const contentOf = (block: MarBlock): Delta =>
  Array.isArray(block.content) ? block.content : [];

const viewOptions = (
  engine: BlockEngine,
  kind: string,
): Record<string, unknown> => {
  const c = engine.config;
  switch (kind) {
    case "file":
      return { onOpen: (id: string) => c.openAsset?.(id), requestMedia: c.requestMedia };
    case "pageBlock":
      return {
        onOpen: (id: string) => c.onOpenPageBlock?.(id),
        onRename: (id: string, label: string) => c.onRenamePageBlock?.(id, label),
        searchPages: c.searchPages,
        createPageBlock: c.createPageBlock,
      };
    case "bookmark":
    case "linkPreview":
      return { resolve: c.resolveLinkPreview };
    case "meetingNotes":
      return {
        socketUrl: c.audioSocketUrl,
        createSocket: c.createAudioSocket,
        onOpenRecording: c.onOpenRecording,
      };
    case "poll":
      return {
        create: c.createPoll,
        resolve: c.resolvePoll,
        vote: c.votePoll,
        update: c.updatePoll,
      };
    case "countdown":
      return { labels: c.countdownLabels };
    case "image":
    case "video":
    case "audio":
    case "pdf":
    case "imageGrid":
      return { requestMedia: c.requestMedia };
    default:
      return {};
  }
};

const viewProps = (
  engine: BlockEngine,
  block: MarBlock,
): Record<string, unknown> => ({
  "data-block-id": block.id,
  class: blockClass(engine, block.id),
  node: {
    id: block.id,
    type: { name: block.kind },
    options: block.options,
    edit: block.edit,
    read: block.read,
    textContent: deltaText(contentOf(block)),
  },
  selected: isBlockSelected(engine, block.id),
  editable: engine.editable.value,
  engine,
  editor: { isEditable: engine.editable.value, authoring: engine.doc.value.type === "template" },
  extension: { options: viewOptions(engine, block.kind) },
  getPos: () => block.id,
  setText: (text: string) =>
    engine.dispatch((doc) => ({
      doc: updateBlock(doc, block.id, (b) => ({ ...b, content: [textOp(text)] })),
    })),
  updateAttributes: (patch: Record<string, unknown>) =>
    engine.dispatch((doc) => ({
      doc: updateBlock(doc, block.id, (b) => ({
        ...b,
        options: { ...b.options, ...patch },
      })),
    })),
  deleteNode: () =>
    engine.dispatch((doc) => ({ doc: removeBlock(doc, block.id) })),
});

const renderCodeFallback = (block: MarBlock): VNode =>
  h(
    "pre",
    { "data-block-id": block.id },
    h(
      "code",
      { class: `language-${String(block.options.language ?? "plaintext")}` },
      deltaText(contentOf(block)),
    ),
  );

const renderReadonlyBlock = (block: MarBlock): VNode => {
  const mode = String(block.options.readonlyDisplay ?? "link");
  if (mode === "hidden") {
    return h("span", { "data-block-id": block.id, style: "display:none" });
  }
  const { icon, label, href } = readonlyMeta(block);
  const plain = mode === "icon" || !href;
  const inner = [h(MarIcon, { icon: icon as IconType, style: "font-size:1.1429em" }), h("span", label)];
  const linkEl = plain
    ? h("span", { class: "mar-be-readonly-link mar-be-readonly-plain" }, inner)
    : h(
        "a",
        {
          class: "mar-be-readonly-link",
          href,
          target: "_blank",
          rel: "noopener",
        },
        inner,
      );
  return h(
    "div",
    { "data-block-id": block.id, class: "mar-be-readonly", contenteditable: "false" },
    linkEl,
  );
};

export const BlockNode: Component = defineComponent({
  name: "BlockNode",
  props: {
    block: { type: Object as PropType<MarBlock>, required: true },
    engine: { type: Object as PropType<BlockEngine>, required: true },
    headingNumber: { type: String, default: undefined },
  },
  setup(props) {
    provide(BLOCK_CHILDREN, () =>
      isTextKind(props.block.kind)
        ? h(MarBlockEditText, { block: props.block, engine: props.engine })
        : h(BlockTree, {
            ids: childIds(props.block),
            engine: props.engine,
          }),
    );
    return () => {
      const { block, engine } = props;
      const shape = contentShapeOf(block);
      const view = resolveBlockView(block.kind);

      if (shape === "none" || (shape === "delta" && !isTextKind(block.kind))) {
        if (!engine.editable.value && READONLY_LINK_TYPES.has(block.kind)) {
          return renderReadonlyBlock(block);
        }
        if (view) {
          return h(view.component, {
            key: block.id,
            contenteditable: "false",
            ...viewProps(engine, block),
          });
        }
        if (block.kind === "codeBlock") return renderCodeFallback(block);
        return h(blockTag(block), {
          ...blockAttrs(block, blockClass(engine, block.id)),
          contenteditable: "false",
        });
      }

      if (shape === "delta") {
        if (view) {
          return h(view.component, { key: block.id, ...viewProps(engine, block) });
        }
        if (block.kind === "titleBlock") {
          return h(MarTitleBlock, { key: block.id, block, engine });
        }
        if (block.kind === "heading") {
          const children: VNode[] = [
            h(MarBlockEditText, { key: block.id, block, engine, headingNumber: props.headingNumber }),
            h(
              "button",
              {
                type: "button",
                contenteditable: "false",
                class: [
                  "mar-heading-toggle",
                  block.options.collapsed ? "mar-heading-toggle-collapsed" : "",
                ],
                onMousedown: (e: MouseEvent) => e.preventDefault(),
                onClick: () =>
                  engine.dispatch((doc) => ({
                    doc: updateBlock(doc, block.id, (b) => ({
                      ...b,
                      options: { ...b.options, collapsed: !b.options.collapsed },
                    })),
                  })),
              },
              h(MarIcon, { icon: "chevron-down", size: "sm", style: "font-size:1.2em" }),
            ),
          ];
          return h("div", { class: "mar-heading-wrap" }, children);
        }
        return h(MarBlockEditText, { key: block.id, block, engine });
      }

      const childTree = h(BlockTree, { ids: childIds(block), engine });
      if (block.kind === "taskItem") {
        const checked = block.options.checked === true;
        return h(
          "li",
          {
            key: block.id,
            ...blockAttrs(block, blockClass(engine, block.id)),
            "data-checked": checked ? "true" : "false",
          },
          [
            h(MarCheckboxInput, {
              key: "check",
              modelValue: checked,
              disabled: !engine.editable.value,
              class: "mar-task-check",
              contenteditable: "false",
              "onUpdate:modelValue": (value: boolean) =>
                engine.dispatch((doc) => ({
                  doc: updateBlock(doc, block.id, (b) => ({
                    ...b,
                    options: { ...b.options, checked: value },
                  })),
                })),
            }),
            h("div", { key: "content", class: "mar-task-content" }, childTree),
          ],
        );
      }
      if (
        (block.kind === "tableHeader" || block.kind === "tableCell") &&
        engine.editable.value
      ) {
        const loc = locate(engine.doc.value, block.id);
        const colIndex = loc?.index ?? 0;
        const rowId = loc?.parentId ?? null;
        const rowLoc = rowId ? locate(engine.doc.value, rowId) : null;
        const rowIndex = rowLoc?.index ?? 0;
        const tableId = rowLoc?.parentId ?? null;
        const attrs = blockAttrs(block, blockClass(engine, block.id));
        const cellChildren: VNode[] = [childTree];
        const ctlBtn = (
          key: string,
          sym: string,
          label: string,
          onClick: () => void,
        ): VNode =>
          h(
            "button",
            {
              key,
              type: "button",
              contenteditable: "false",
              class: "mar-table-edge-btn",
              ...tip(label),
              onMousedown: (e: MouseEvent) => e.preventDefault(),
              onClick,
            },
            sym,
          );
        if (tableId) {
          cellChildren.push(
            h("div", { key: "col-edge", contenteditable: "false", class: "mar-table-col-edge" }, [
              h("div", { class: "mar-table-edge-ctl" }, [
                ctlBtn("col-add", "+", "Insert column", () =>
                  engine.dispatch((doc) => addColumn(doc, tableId, colIndex + 1))),
                ctlBtn("col-del", "−", "Delete column", () =>
                  engine.dispatch((doc) => deleteColumn(doc, tableId, colIndex))),
              ]),
            ]),
          );
          if (colIndex === 0) {
            cellChildren.push(
              h("div", { key: "row-edge", contenteditable: "false", class: "mar-table-row-edge" }, [
                h("div", { class: "mar-table-edge-ctl" }, [
                  ctlBtn("row-add", "+", "Insert row", () =>
                    engine.dispatch((doc) => addRow(doc, tableId, rowIndex + 1))),
                  ctlBtn("row-del", "−", "Delete row", () =>
                    engine.dispatch((doc) => deleteRow(doc, tableId, rowIndex))),
                ]),
              ]),
            );
          }
        }
        return h(
          blockTag(block),
          { ...attrs, class: `${attrs.class} mar-table-cell` },
          cellChildren,
        );
      }
      if (block.kind === "table" && engine.editable.value) {
        return h("div", { class: "mar-table-wrap" }, [
          h(blockTag(block), blockAttrs(block, blockClass(engine, block.id)), childTree),
        ]);
      }
      if (view) {
        return h(view.component, { key: block.id, ...viewProps(engine, block) });
      }
      return h(blockTag(block), blockAttrs(block, blockClass(engine, block.id)), childTree);
    };
  },
});

export const BlockTree: Component = defineComponent({
  name: "BlockTree",
  props: {
    ids: { type: Array as PropType<BlockId[]>, default: () => [] },
    engine: { type: Object as PropType<BlockEngine>, required: true },
  },
  setup(props) {
    return () => {
      const blocks = props.ids
        .map((id) => props.engine.doc.value.blocks[id])
        .filter((block): block is MarBlock => block !== undefined);
      const { hidden, numbers } = headingMeta(props.engine.numbering.value, blocks);
      return blocks
        .filter((block) => !hidden.has(block.id))
        .map((block) =>
          h(BlockNode, {
            key: block.id,
            block,
            engine: props.engine,
            headingNumber: numbers.get(block.id),
          }),
        );
    };
  },
});
