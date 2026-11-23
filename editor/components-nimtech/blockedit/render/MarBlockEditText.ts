import {
  defineComponent,
  h,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  render,
  watch,
  type PropType,
} from "vue";
import type { Delta, DeltaOp, MarBlock, MarDocument, MarkType } from "../model/types";
import type { BlockEngine } from "../engine/BlockEngine";
import type { IconType } from "@/types/icon.types";
import MarIcon from "@/components/MarIcon";
import { blockTag, blockAttrs, blockClass } from "./nodeProps";
import { serializeInline } from "../serialize/htmlSerialize";
import { inlineOf } from "../serialize/htmlParse";
import { caretAtEdge, caretOffset, textBeforeCaret } from "../selection/domMap";
import { contentOf, deleteInlineRange, insertInlineAt, mergeWithPrevious, setBlockContent, splitTextBlock } from "../ops/text";
import { deltaLength, isRefOp, isTextOp, opLength, refOp, textOp } from "../model/delta";
import { setBlockKind } from "../ops/blocks";
import { enterInList, indentList, isInList, outdentList, removeListItem } from "../ops/lists";
import { ancestorContentLocked, childBlocks, childIds, getBlock, insertBlock, isContentLocked, locate, putBlocks, removeBlock, updateBlock } from "../model/tree";
import { isTextKind, makeBlock } from "../model/schema";
import { wrapInList } from "../commands";

interface CellNav {
  tableId: string;
  rowIndex: number;
  colIndex: number;
  cols: number;
}

const tableCellNav = (doc: MarDocument, blockId: string): CellNav | null => {
  const paragraphLoc = locate(doc, blockId);
  if (!paragraphLoc?.parentId) return null;
  const cell = getBlock(doc, paragraphLoc.parentId);
  if (!cell || (cell.kind !== "tableCell" && cell.kind !== "tableHeader")) return null;
  const cellLoc = locate(doc, cell.id);
  if (!cellLoc?.parentId) return null;
  const rowLoc = locate(doc, cellLoc.parentId);
  if (!rowLoc?.parentId) return null;
  const table = getBlock(doc, rowLoc.parentId);
  if (!table) return null;
  const cols = Math.max(
    0,
    ...childBlocks(doc, table.id).map((row) => childIds(row).length),
  );
  return { tableId: table.id, rowIndex: rowLoc.index, colIndex: cellLoc.index, cols };
};

const cellEntryParagraph = (doc: MarDocument, cellId: string | undefined): string | null => {
  if (!cellId) return null;
  const kids = childBlocks(doc, cellId);
  return kids.find((c) => isTextKind(c.kind))?.id ?? kids[0]?.id ?? null;
};

const adjacentTextBlock = (doc: MarDocument, id: string, dir: -1 | 1): string | null => {
  const flat: string[] = [];
  const walk = (ids: string[]): void => {
    for (const blockId of ids) {
      const block = doc.blocks[blockId];
      if (!block) continue;
      if (isTextKind(block.kind)) flat.push(block.id);
      walk(childIds(block));
    }
  };
  walk(doc.root);
  const i = flat.indexOf(id);
  if (i < 0) return null;
  return flat[i + dir] ?? null;
};

const INLINE_RULES: { re: RegExp; mark: MarkType }[] = [
  { re: /\*\*([^*]+)\*\*$/, mark: "bold" },
  { re: /__([^_]+)__$/, mark: "bold" },
  { re: /(?<![*])\*([^*\s][^*]*)\*$/, mark: "italic" },
  { re: /(?<![_])_([^_\s][^_]*)_$/, mark: "italic" },
  { re: /~~([^~]+)~~$/, mark: "strike" },
  { re: /`([^`]+)`$/, mark: "code" },
];

const LINK_RULE = /\[([^\]]+)\]\(([^)]+)\)$/;

const DEFAULT_PLACEHOLDER = "Write something or press / for commands";

const TRAILING_FILLER = '<br data-filler="true">';

const blockDelta = (block: MarBlock): Delta =>
  Array.isArray(block.content) ? block.content : [];

const placeholderOf = (block: MarBlock, engine: BlockEngine): string | undefined => {
  if (!engine.editable.value) return undefined;
  if (blockDelta(block).length) return undefined;
  if (block.kind === "heading") return `Heading ${Number(block.options.level) || 1}`;
  if (block.kind === "titleBlock") return "Untitled";
  if (block.kind !== "paragraph") return undefined;
  return engine.config.placeholder || DEFAULT_PLACEHOLDER;
};

export const MarBlockEditText = defineComponent({
  name: "MarBlockEditText",
  props: {
    block: { type: Object as PropType<MarBlock>, required: true },
    engine: { type: Object as PropType<BlockEngine>, required: true },
    headingNumber: { type: String, default: undefined },
  },
  setup(props) {
    const el = ref<HTMLElement | null>(null);
    let local = false;
    let iconHosts: HTMLElement[] = [];

    const clearIcons = (): void => {
      for (const host of iconHosts) render(null, host);
      iconHosts = [];
    };

    const mountIcons = (): void => {
      if (!el.value) return;
      el.value.querySelectorAll<HTMLElement>(".mar-be-mention-icon").forEach((host) => {
        const mention = host.closest<HTMLElement>('[data-type="mention"]');
        const icon = (mention?.getAttribute("data-icon") || "at") as IconType;
        render(h(MarIcon, { icon }), host);
        iconHosts.push(host);
      });
    };

    const paint = (): void => {
      if (!el.value) return;
      const html = serializeInline(
        blockDelta(props.block),
        true,
        props.engine.config.mentionTypes,
      );
      const next =
        html && !html.endsWith("<br>") ? html : `${html}${TRAILING_FILLER}`;
      if (el.value.innerHTML === next) return;
      clearIcons();
      el.value.innerHTML = next;
      mountIcons();
    };

    onMounted(paint);
    onBeforeUnmount(clearIcons);
    watch(
      () => props.block.content,
      () => {
        if (!local) paint();
      },
    );
    watch(
      () => `${props.block.kind}:${String(props.block.options.level ?? "")}`,
      () => {
        void nextTick(paint);
      },
    );

    const onInput = (): void => {
      if (!el.value) return;
      local = true;
      const content = inlineOf(el.value);
      props.engine.dispatch(
        (doc) => setBlockContent(doc, props.block.id, content),
        { coalesce: true },
      );
      void nextTick(() => {
        local = false;
      });
    };

    const applyInlineRun = (start: number, end: number, op: DeltaOp): void => {
      const id = props.block.id;
      props.engine.dispatch((doc) => {
        const del = deleteInlineRange(doc, id, start, end);
        return insertInlineAt(del.doc, id, start, [op]);
      });
    };

    const insertBreak = (): void => {
      if (!el.value) return;
      const id = props.block.id;
      const off = caretOffset(el.value) ?? 0;
      props.engine.dispatch((doc) => insertInlineAt(doc, id, off, [refOp("break")]));
    };

    const tryInlineRule = (e: InputEvent): boolean => {
      if (!el.value || e.inputType !== "insertText" || !e.data) return false;
      if (!"*_~`)".includes(e.data)) return false;
      const before = textBeforeCaret(el.value) + e.data;
      const caret = caretOffset(el.value) ?? 0;
      if (e.data === ")") {
        const m = LINK_RULE.exec(before);
        if (m) {
          const start = caret - (m[0].length - 1);
          if (start < 0) return false;
          e.preventDefault();
          applyInlineRun(start, caret, textOp(m[1] ?? "", { link: { href: m[2] ?? "" } }));
          return true;
        }
        return false;
      }
      for (const rule of INLINE_RULES) {
        const m = rule.re.exec(before);
        if (m) {
          const start = caret - (m[0].length - 1);
          if (start < 0) continue;
          e.preventDefault();
          applyInlineRun(start, caret, textOp(m[1] ?? "", { [rule.mark]: true }));
          return true;
        }
      }
      return false;
    };

    const onBeforeInput = (e: InputEvent): void => {
      if (e.isComposing || !el.value) return;
      if (tryInlineRule(e)) return;
      if (e.inputType === "insertText" && e.data === " ") {
        const content = inlineOf(el.value);
        const off = caretOffset(el.value) ?? 0;
        const last = content[content.length - 1];
        if (off > 0 && off === deltaLength(content) && last && isTextOp(last) && last.marks) {
          e.preventDefault();
          const id = props.block.id;
          local = false;
          props.engine.dispatch((doc) => ({
            doc: setBlockContent(doc, id, [...content, textOp(" ")]).doc,
            selection: {
              kind: "text",
              anchor: { blockId: id, offset: off + 1 },
              head: { blockId: id, offset: off + 1 },
            },
          }));
          void nextTick(paint);
          return;
        }
      }
      if (
        e.inputType === "insertText" &&
        e.data === " " &&
        props.block.kind === "paragraph"
      ) {
        const before = textBeforeCaret(el.value);
        const id = props.block.id;
        const heading = /^(#{1,4})$/.exec(before);
        if (heading) {
          e.preventDefault();
          const level = (heading[1] ?? "#").length;
          props.engine.dispatch((doc) => {
            const r = setBlockKind(doc, id, "heading", { level });
            return {
              doc: updateBlock(r.doc, id, (b) => ({ ...b, content: [] })),
              selection: r.selection,
            };
          });
          return;
        }
        const list = /^([-*]|\d+\.|\[[ xX]?\])$/.exec(before);
        if (list) {
          const token = list[1] ?? "";
          const listType: "bulletList" | "orderedList" | "taskList" =
            /^\d+\.$/.test(token)
              ? "orderedList"
              : token.startsWith("[")
                ? "taskList"
                : "bulletList";
          e.preventDefault();
          props.engine.dispatch((doc) => ({
            doc: updateBlock(doc, id, (b) => ({ ...b, content: [] })),
          }));
          wrapInList(props.engine, id, listType);
          return;
        }
        if (before === ">") {
          e.preventDefault();
          props.engine.dispatch((doc) => {
            const loc = locate(doc, id);
            if (!loc) return { doc };
            const inner = makeBlock("paragraph", {}, []);
            const bq = makeBlock("blockquote", {}, [inner.id]);
            let d = removeBlock(doc, id);
            d = putBlocks(d, [inner]);
            d = insertBlock(d, bq, loc.parentId, loc.index);
            return {
              doc: d,
              selection: {
                kind: "text",
                anchor: { blockId: inner.id, offset: 0 },
                head: { blockId: inner.id, offset: 0 },
              },
            };
          });
          return;
        }
      }
      if (e.inputType === "insertParagraph") {
        e.preventDefault();
        const id = props.block.id;
        const off = caretOffset(el.value) ?? 0;
        if (isInList(props.engine.doc.value, id)) {
          props.engine.dispatch((doc) => enterInList(doc, id, off) ?? { doc });
        } else {
          props.engine.dispatch((doc) => splitTextBlock(doc, id, off) ?? { doc });
        }
        return;
      }
      if (e.inputType === "insertLineBreak") {
        e.preventDefault();
        insertBreak();
        return;
      }
      if (e.inputType === "deleteContentBackward") {
        const off = caretOffset(el.value) ?? 0;
        if (off > 0) {
          const content = blockDelta(props.block);
          let acc = 0;
          for (const op of content) {
            const len = opLength(op);
            if (acc + len === off && isRefOp(op) && op.insert.ref === "mention") {
              e.preventDefault();
              const id = props.block.id;
              const label = String(op.attrs?.label ?? "");
              const start = acc;
              props.engine.dispatch((doc) => {
                const del = deleteInlineRange(doc, id, start, off);
                return insertInlineAt(del.doc, id, start, [textOp(`@${label}`)]);
              });
              return;
            }
            acc += len;
            if (acc >= off) break;
          }
        }
      }
      if (
        e.inputType === "deleteContentBackward" &&
        caretOffset(el.value) === 0
      ) {
        e.preventDefault();
        const id = props.block.id;
        const empty = !blockDelta(props.block).length;
        if (empty && isInList(props.engine.doc.value, id)) {
          props.engine.dispatch((doc) => removeListItem(doc, id) ?? { doc });
        } else {
          props.engine.dispatch((doc) => mergeWithPrevious(doc, id) ?? { doc });
        }
      }
    };

    const focusAdjacent = (dir: -1 | 1, pos: "start" | "end"): boolean => {
      const target = adjacentTextBlock(props.engine.doc.value, props.block.id, dir);
      if (!target) return false;
      const offset =
        pos === "end" ? deltaLength(contentOf(props.engine.doc.value, target)) : 0;
      props.engine.setSelection({
        kind: "text",
        anchor: { blockId: target, offset },
        head: { blockId: target, offset },
      });
      return true;
    };

    const moveToCell = (
      tableId: string,
      r: number,
      c: number,
      pos: "start" | "end",
    ): boolean => {
      const doc = props.engine.doc.value;
      const row = childIds(getBlock(doc, tableId))[r];
      const cell = row ? childIds(getBlock(doc, row))[c] : undefined;
      const pid = cellEntryParagraph(doc, cell);
      if (!pid) return false;
      const offset = pos === "end" ? deltaLength(contentOf(doc, pid)) : 0;
      props.engine.setSelection({
        kind: "text",
        anchor: { blockId: pid, offset },
        head: { blockId: pid, offset },
      });
      return true;
    };

    const onKeydown = (e: KeyboardEvent): void => {
      if (!el.value) return;
      if (
        e.shiftKey &&
        (e.key === "ArrowUp" ||
          e.key === "ArrowDown" ||
          e.key === "ArrowLeft" ||
          e.key === "ArrowRight")
      ) {
        return;
      }
      if (e.key === "Enter" && e.shiftKey) {
        e.preventDefault();
        insertBreak();
        return;
      }
      const nav = tableCellNav(props.engine.doc.value, props.block.id);
      if (nav) {
        const rows = childIds(getBlock(props.engine.doc.value, nav.tableId));
        if (e.key === "Tab") {
          e.preventDefault();
          let r = nav.rowIndex;
          let c = nav.colIndex + (e.shiftKey ? -1 : 1);
          if (c >= nav.cols) {
            c = 0;
            r += 1;
          } else if (c < 0) {
            c = nav.cols - 1;
            r -= 1;
          }
          if (r < 0 || r >= rows.length) return;
          moveToCell(nav.tableId, r, c, "start");
          return;
        }
        if (e.key === "ArrowUp" || e.key === "ArrowDown") {
          const sel = window.getSelection();
          if (!sel || !sel.rangeCount || !sel.isCollapsed) return;
          const onFirstLine = caretAtEdge(el.value, -1);
          const onLastLine = caretAtEdge(el.value, 1);
          if (e.key === "ArrowUp" && onFirstLine) {
            if (nav.rowIndex > 0) {
              e.preventDefault();
              moveToCell(nav.tableId, nav.rowIndex - 1, nav.colIndex, "end");
            } else if (focusAdjacent(-1, "end")) {
              e.preventDefault();
            }
            return;
          }
          if (e.key === "ArrowDown" && onLastLine) {
            if (nav.rowIndex < rows.length - 1) {
              e.preventDefault();
              moveToCell(nav.tableId, nav.rowIndex + 1, nav.colIndex, "start");
            } else if (focusAdjacent(1, "start")) {
              e.preventDefault();
            }
            return;
          }
          return;
        }
      }
      if (e.key === "ArrowUp" || e.key === "ArrowDown") {
        const sel = window.getSelection();
        if (!sel || !sel.rangeCount || !sel.isCollapsed) return;
        if (e.key === "ArrowUp" && caretAtEdge(el.value, -1) && focusAdjacent(-1, "end")) {
          e.preventDefault();
        } else if (
          e.key === "ArrowDown" &&
          caretAtEdge(el.value, 1) &&
          focusAdjacent(1, "start")
        ) {
          e.preventDefault();
        }
        return;
      }
      if (e.key !== "Tab") return;
      const id = props.block.id;
      if (!isInList(props.engine.doc.value, id)) return;
      e.preventDefault();
      const off = caretOffset(el.value) ?? 0;
      if (e.shiftKey) {
        props.engine.dispatch((doc) => outdentList(doc, id, off) ?? { doc });
      } else {
        props.engine.dispatch((doc) => indentList(doc, id, off) ?? { doc });
      }
    };

    const onClick = (e: MouseEvent): void => {
      if (!(e.metaKey || e.ctrlKey)) return;
      const anchor = (e.target as HTMLElement | null)?.closest?.("a");
      const href = anchor?.getAttribute("href");
      if (!href) return;
      e.preventDefault();
      window.open(href, "_blank", "noopener");
    };

    return () => {
      const authoring = props.engine.doc.value.type === "template";
      const contentLocked =
        !authoring &&
        (isContentLocked(props.block) ||
          ancestorContentLocked(props.engine.doc.value, props.block.id));
      return h(blockTag(props.block), {
        ref: el,
        ...blockAttrs(props.block, blockClass(props.engine, props.block.id)),
        class: `mar-be-text ${blockClass(props.engine, props.block.id)}`,
        "data-heading-number": props.headingNumber,
        "data-placeholder": placeholderOf(props.block, props.engine),
        contenteditable: props.engine.editable.value && !contentLocked ? "true" : "false",
        spellcheck: "false",
        onBeforeinput: onBeforeInput,
        onInput,
        onKeydown,
        onClick,
      });
    };
  },
});
