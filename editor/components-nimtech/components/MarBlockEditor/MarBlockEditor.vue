<script lang="ts">
import type { SlashCommand } from "@/blockedit/index.ts";

export type MarBlockEditorSlashCommand = SlashCommand;

export { marBlockEditorDefaultCommands, marBlockEditorDefaultGroups } from "@/blockedit/index.ts";
</script>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import {
  contentString,
  createBlockEditor,
  type BlockEngine,
  type EditorConfig,
} from "@/blockedit/index.ts";
import type {
  MarContentType,
  MarDocument,
  MarDocumentMode,
  MarDocumentType,
  MarkType,
} from "@/blockedit/model/types.ts";
import { BlockTree } from "@/blockedit/render/BlockTree.ts";
import { mentionDeclared } from "@/blockedit/serialize/htmlSerialize.ts";
import type * as Y from "yjs";
import { createYBinding, type YBinding } from "@/blockedit/collab/yBinding.ts";
import type { CollabProvider } from "@/blockedit/collab/provider.ts";
import RemoteCursors from "@/blockedit/render/RemoteCursors.vue";
import { useBlockHover } from "@/blockedit/interaction/useBlockHover.ts";
import { useBlockDrag } from "@/blockedit/interaction/useBlockDrag.ts";
import { useSuggest } from "@/blockedit/interaction/useSuggest.ts";
import { useMention } from "@/blockedit/interaction/useMention.ts";
import { openBlockMenu } from "@/blockedit/interaction/useBlockMore.ts";
import { useBlockSelect } from "@/blockedit/interaction/useBlockSelect.ts";
import { blockEl, blockIdOf } from "@/blockedit/interaction/dom.ts";
import { selectionRange } from "@/blockedit/selection/domMap.ts";
import { blockTextLength, selectOutwards } from "@/blockedit/selection/outwards.ts";
import { toggleMark } from "@/blockedit/ops/marks.ts";
import { acceptsAtRoot } from "@/blockedit/ops/blocks.ts";
import {
  marBlocksFromMarkdown,
  marDocumentToMarkdown,
  marBlockRangeToMarkdown,
} from "@/blockedit/serialize/markdown.ts";
import { ancestorContentLocked, childIds, getBlock, insertBlock, isBlockLocked, locate, moveBlock, putBlocks, removeBlock } from "@/blockedit/model/tree.ts";
import { isTextKind } from "@/blockedit/model/schema.ts";
import MarIcon from "../MarIcon";
import MarIconBtn from "../MarIconBtn";
import MarBlockReader from "../MarBlockReader";
import type {
  MarBlockAssetRef,
  MarBlockLinkPreview,
  MarBlockMention,
  MarBlockHeadingNumbering,
  MarPageBlockRef,
  MarPollData,
  MarPollRef,
  MarCountdownLabels,
} from "./marBlockEditor.types";
import type { MarMediaAsset, MarMediaKind } from "@/types/media.types";

const {
  modelValue = "",
  mode = "edit",
  contentType = "json",
  type,
  placeholder,
  slashCommands,
  ydoc,
  provider,
  collabField,
  user,
  createPageBlock,
  requestMedia,
  uploadFile,
  openAsset,
  searchPages,
  resolveLinkPreview,
  searchMentions,
  mentionTypes,
  audioSocketUrl,
  createAudioSocket,
  headingNumbering,
  createPoll,
  resolvePoll,
  votePoll,
  updatePoll,
  countdownLabels,
} = defineProps<{
  /**
   * Document content as a json MarDocument, or as a string read per contentType.
   * @mock mockParagraph
   */
  modelValue?: MarDocument | string;
  /** Whether the document is authored or read, switched live. */
  mode?: MarDocumentMode;
  /** How a string modelValue is read and emitted. */
  contentType?: MarContentType;
  /** Document type; a template sets the edit modes and a document enforces them. */
  type?: MarDocumentType;
  /** Hint text shown on an empty paragraph. */
  placeholder?: string;
  /** Replaces the default slash menu command set. */
  slashCommands?: MarBlockEditorSlashCommand[];
  /** Yjs document that switches the editor into collaborative mode. */
  ydoc?: Y.Doc;
  /** Awareness and sync provider for the collaboration binding. */
  provider?: CollabProvider | null;
  /** Yjs field the collaboration binding attaches to. */
  collabField?: string;
  /** Local identity shown on remote cursors. */
  user?: { name: string; color: string };
  /** Creates a subpage when the user inserts a page block and returns its reference. */
  createPageBlock?: (name: string) =>
    | Promise<MarPageBlockRef | null>
    | MarPageBlockRef
    | null;
  /** Asks the host for an asset, picked or uploaded, when a media block needs a source; null when the person cancels. */
  requestMedia?: (
    kind: MarMediaKind,
    current?: string,
  ) => Promise<MarMediaAsset | null>;
  /** Handles file drops and uploads and returns the stored asset reference. */
  uploadFile?: (file: File, documentId?: string) => Promise<MarBlockAssetRef>;
  /** Opens an asset when a block requests it. */
  openAsset?: (assetId: string) => void;
  /** Lists the assets attached to a document. */
  listDocAssets?: (documentId: string) => Promise<MarBlockAssetRef[]>;
  /** Supplies page suggestions for page blocks. */
  searchPages?: (query: string) => Promise<MarPageBlockRef[]>;
  /** Resolves rich metadata for bookmark and embed blocks. */
  resolveLinkPreview?: (url: string) => Promise<MarBlockLinkPreview>;
  /** Supplies mention suggestions for the mention popup. */
  searchMentions?: (query: string) => Promise<MarBlockMention[]>;
  /**
   * Reference kinds the host resolves, such as employee, project, asset and article.
   * A suggestion carrying any other type is dropped from the popup and a mention
   * already carrying one never opens. Left empty, every type is accepted.
   */
  mentionTypes?: string[];
  /** WebSocket endpoint for the recorder block. */
  audioSocketUrl?: string;
  /** Factory alternative to audioSocketUrl for the recorder socket. */
  createAudioSocket?: () => WebSocket;
  /** Controls automatic heading numbering, echoed back on change. */
  headingNumbering?: MarBlockHeadingNumbering;
  /** Creates the backing poll when the user inserts a poll block and returns its reference. */
  createPoll?: (
    question: string,
    options: string[],
  ) => Promise<MarPollRef | null>;
  /** Resolves the live question, options, and vote tallies for a poll block. */
  resolvePoll?: (pollId: string) => Promise<MarPollData>;
  /** Casts a vote on a poll block and returns the refreshed tallies. */
  votePoll?: (pollId: string, optionIndex: number) => Promise<MarPollData>;
  /** Persists question and option edits made while authoring a poll block. */
  updatePoll?: (
    pollId: string,
    patch: { question?: string; options?: string[] },
  ) => Promise<void>;
  /** Translated day, hour, minute, and second labels for countdown blocks. */
  countdownLabels?: MarCountdownLabels;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string];
  change: [value: string];
  "section-change": [state: { index: number; count: number }];
  "char-diff": [diff: number];
  "open-page-block": [assetId: string];
  "create-page-block": [assetId: string];
  "rename-page-block": [payload: { assetId: string; label: string }];
  "open-mention": [mention: { id: string; type: string; href: string }];
  "open-recording": [recId: string];
  "update:headingNumbering": [value: MarBlockHeadingNumbering];
}>();

const engine = createBlockEditor({
  content: modelValue,
  editable: mode === "edit",
  contentType,
  type,
  placeholder,
  slashCommands,
  searchMentions: searchMentions
    ? (async (query: string) =>
        (await searchMentions(query)).filter((m) =>
          mentionDeclared(m.type, mentionTypes),
        )) as EditorConfig["searchMentions"]
    : undefined,
  mentionTypes,
  searchPages: searchPages as EditorConfig["searchPages"],
  createPageBlock: createPageBlock as EditorConfig["createPageBlock"],
  requestMedia: requestMedia as EditorConfig["requestMedia"],
  uploadFile: uploadFile as EditorConfig["uploadFile"],
  openAsset,
  resolveLinkPreview: resolveLinkPreview as EditorConfig["resolveLinkPreview"],
  audioSocketUrl,
  createAudioSocket,
  createPoll: createPoll as EditorConfig["createPoll"],
  resolvePoll: resolvePoll as EditorConfig["resolvePoll"],
  votePoll: votePoll as EditorConfig["votePoll"],
  updatePoll: updatePoll as EditorConfig["updatePoll"],
  countdownLabels,
  onUpdate: (value) => {
    emit("update:modelValue", value);
    emit("change", value);
  },
  onCharDiff: (delta) => emit("char-diff", delta),
  onOpenRecording: (recId) => emit("open-recording", recId),
  onOpenMention: (mention) => {
    if (!mentionDeclared(mention.type, mentionTypes)) return;
    emit("open-mention", mention);
  },
  onOpenPageBlock: (assetId) => emit("open-page-block", assetId),
  onRenamePageBlock: (assetId, label) =>
    emit("rename-page-block", { assetId, label }),
  onCreatePageBlock: (assetId) => emit("create-page-block", assetId),
});

let binding: YBinding | null = null;
if (ydoc) {
  binding = createYBinding(engine, {
    ydoc,
    field: collabField ?? "default",
    provider: provider ?? null,
    user,
  });
}
const remotePeersRef = binding ? binding.peers : ref([]);

onBeforeUnmount(() => {
  binding?.destroy();
  binding = null;
});

watch(
  () => modelValue,
  (value) => {
    if (binding) return;
    if (contentString(value) !== engine.getValue()) engine.setContent(value ?? "");
  },
);

watch(
  () => mode,
  (value) => engine.setEditable(value !== "read"),
);

watch(
  () => headingNumbering,
  (value) => {
    if (!value) return;
    if (
      value.enabled !== engine.numbering.value.enabled ||
      value.startLevel !== engine.numbering.value.startLevel
    ) {
      engine.setNumbering(value.enabled, value.startLevel);
    }
  },
  { immediate: true },
);

watch(
  () => engine.numbering.value,
  (value) =>
    emit("update:headingNumbering", {
      enabled: value.enabled,
      startLevel: value.startLevel,
    }),
);

const surfaceEl = ref<HTMLElement | null>(null);
const frameEl = ref<HTMLElement | null>(null);

const surfaceEmpty = computed(() =>
  engine.doc.value.root.every((id) => {
    const block = engine.doc.value.blocks[id];
    return !!block && isTextKind(block.kind) && !(Array.isArray(block.content) && block.content.length);
  }),
);

const documentWidth = computed(() => engine.doc.value.width || undefined);
const numbering = computed(() => engine.doc.value.page?.numbering ?? null);
const pageCount = computed(
  () =>
    engine.doc.value.root.filter(
      (id) => engine.doc.value.blocks[id]?.kind === "break",
    ).length + 1,
);

const drag = useBlockDrag(engine, surfaceEl, frameEl);
const {
  hoveredId,
  top: handleTop,
  left: handleLeft,
  overHandle,
  menuOpen,
  visible: handleVisible,
  bind: bindHover,
} = useBlockHover(engine, surfaceEl, frameEl, drag.dragging);
const authoring = computed(() => engine.doc.value.type === "template");
const hoveredLocked = computed(() => {
  if (authoring.value) return false;
  const id = hoveredId.value;
  if (!id) return false;
  const block = getBlock(engine.doc.value, id);
  return !!block && (isBlockLocked(block) || ancestorContentLocked(engine.doc.value, id));
});
const { bind: bindSuggest } = useSuggest(engine, surfaceEl);
const { bind: bindMention } = useMention(engine, surfaceEl);
const select = useBlockSelect(engine, surfaceEl);

watch(
  surfaceEl,
  (el) => {
    if (!el) return;
    bindHover();
    bindSuggest();
    bindMention();
    select.bind();
  },
  { flush: "post" },
);

const markKeys: Record<string, MarkType> = { b: "bold", i: "italic", e: "code" };
const ARROWS = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"];

let moveTimer: number | undefined;
let movingEl: HTMLElement | null = null;
const flashMove = (primaryId: string, fallbackId: string): void => {
  void nextTick(() => {
    if (moveTimer !== undefined) {
      window.clearTimeout(moveTimer);
      movingEl?.classList.remove("mar-block-moving");
    }
    const target =
      (surfaceEl.value?.querySelector(`[data-block-id="${primaryId}"]`) ??
        surfaceEl.value?.querySelector(`[data-block-id="${fallbackId}"]`)) as
        | HTMLElement
        | null;
    if (!target) return;
    movingEl = target;
    target.classList.add("mar-block-moving");
    moveTimer = window.setTimeout(() => {
      target.classList.remove("mar-block-moving");
      movingEl = null;
      moveTimer = undefined;
    }, 700);
  });
};

const onKeydown = (e: KeyboardEvent): void => {
  const mod = e.metaKey || e.ctrlKey;
  if (e.shiftKey && !mod && (e.key === "ArrowUp" || e.key === "ArrowDown")) {
    if (select.extendVertically(e.key === "ArrowUp" ? -1 : 1)) e.preventDefault();
    return;
  }
  if (e.shiftKey && !mod && (e.key === "ArrowLeft" || e.key === "ArrowRight")) {
    if (select.extendHorizontally(e.key === "ArrowLeft" ? -1 : 1)) e.preventDefault();
    return;
  }
  if (!mod && !e.shiftKey && !e.altKey && ARROWS.includes(e.key)) {
    if (select.collapse(e.key === "ArrowUp" || e.key === "ArrowLeft" ? -1 : 1)) {
      e.preventDefault();
    }
    return;
  }
  if (!mod && (e.key === "Backspace" || e.key === "Delete")) {
    if (select.deleteSelected()) e.preventDefault();
    return;
  }
  if (!mod) return;
  const key = e.key.toLowerCase();
  if (key === "a" && !e.shiftKey && !e.altKey) {
    e.preventDefault();
    const next = selectOutwards(engine.doc.value, engine.selection.value, engine.currentBlockId());
    if (next) engine.setSelection(next);
    return;
  }
  if (key === "z" && !e.shiftKey) {
    e.preventDefault();
    engine.undo();
    return;
  }
  if ((key === "z" && e.shiftKey) || key === "y") {
    e.preventDefault();
    engine.redo();
    return;
  }
  if (e.shiftKey && (e.key === "ArrowUp" || e.key === "ArrowDown")) {
    e.preventDefault();
    e.stopPropagation();
    const anchor = window.getSelection()?.anchorNode ?? null;
    const host = anchor instanceof Element ? anchor : anchor?.parentElement;
    const el = host?.closest("[data-block-id]") as HTMLElement | null;
    const sel = engine.selection.value;
    const fromSel =
      sel?.kind === "text"
        ? sel.anchor.blockId
        : sel?.kind === "node"
          ? sel.blockId
          : sel?.kind === "blocks"
            ? sel.ids[0] ?? null
            : null;
    const id = (el ? blockIdOf(el) : null) ?? fromSel;
    if (!id) return;
    const doc0 = engine.doc.value;
    let movableId = id;
    const inner = locate(doc0, id);
    if (inner?.parentId) {
      const parent = getBlock(doc0, inner.parentId);
      if (parent && (parent.kind === "listItem" || parent.kind === "taskItem")) {
        movableId = parent.id;
      }
    }
    const loc = locate(doc0, movableId);
    if (!loc) return;
    const movable = getBlock(doc0, movableId);
    if (!authoring.value && movable && (isBlockLocked(movable) || ancestorContentLocked(doc0, movableId))) return;
    const dir = e.key === "ArrowUp" ? -1 : 1;
    const target = loc.index + dir;
    if (target < 0 || target >= loc.siblings.length) return;
    const parentId = loc.parentId;
    engine.dispatch((doc) => ({
      doc: moveBlock(doc, movableId, parentId, target),
      selection: engine.selection.value,
    }));
    flashMove(movableId, id);
    return;
  }
  const markType = key === "s" && e.shiftKey ? "strike" : markKeys[key];
  if (!markType) return;
  const anchor = window.getSelection()?.anchorNode ?? null;
  const host = anchor instanceof Element ? anchor : anchor?.parentElement;
  const el = host?.closest("[data-block-id]") as HTMLElement | null;
  if (!el) return;
  const range = selectionRange(el);
  const id = blockIdOf(el);
  if (!range || !id) return;
  e.preventDefault();
  engine.dispatch((doc) => toggleMark(doc, id, range.from, range.to, markType));
};

const onCopy = (e: ClipboardEvent): void => {
  const surface = surfaceEl.value;
  if (!surface) return;
  const model = engine.selection.value;
  let ids: string[];
  if (model?.kind === "blocks") {
    ids = model.ids;
  } else {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || sel.rangeCount === 0) return;
    const range = sel.getRangeAt(0);
    ids = engine.doc.value.root.filter((id) => {
      const el = blockEl(surface, id);
      return el ? range.intersectsNode(el) : false;
    });
  }
  if (!ids.length) return;
  let md = marDocumentToMarkdown({ ...engine.doc.value, root: ids });
  if (ids.length === 1) {
    const only = getBlock(engine.doc.value, ids[0] as string);
    const el = only ? blockEl(surface, only.id) : null;
    const within = el ? selectionRange(el) : null;
    const whole = only ? blockTextLength(only) : 0;
    if (only && within && !(within.from === 0 && within.to === whole)) {
      const partial = marBlockRangeToMarkdown(only, within.from, within.to);
      if (partial) md = partial;
    }
  }
  if (!md) return;
  e.clipboardData?.setData("text/plain", md);
  e.preventDefault();
};

const looksLikeMarkdownDoc = (text: string): boolean => {
  const t = text.trim();
  if (!t) return false;
  if (t.includes("\n")) return true;
  return /^(#{1,6}\s|[-*]\s|\d+\.\s|>\s|`{3}|\||!\[)/.test(t);
};

const onPaste = (e: ClipboardEvent): void => {
  if (!engine.editable.value) return;
  const text = e.clipboardData?.getData("text/plain") ?? "";
  if (!looksLikeMarkdownDoc(text)) return;
  const anchor = window.getSelection()?.anchorNode ?? null;
  const host = anchor instanceof Element ? anchor : anchor?.parentElement;
  const el = host?.closest("[data-block-id]") as HTMLElement | null;
  const id = el ? blockIdOf(el) : null;
  const containerId = id ? locate(engine.doc.value, id)?.parentId ?? null : null;
  const container = containerId ? getBlock(engine.doc.value, containerId) : null;
  const parsed = marBlocksFromMarkdown(text, container?.kind);
  if (!parsed.root.length) return;
  e.preventDefault();
  engine.dispatch((doc) => {
    const seeded = putBlocks(doc, Object.values(parsed.blocks));
    const place = (parentId: string | null, from: number): MarDocument => {
      let d = seeded;
      let idx = from;
      for (const pastedId of parsed.root) {
        const block = parsed.blocks[pastedId];
        if (!block) continue;
        d = insertBlock(d, block, parentId, idx);
        idx += 1;
      }
      return d;
    };
    if (!id) {
      const refused = parsed.root.some((pastedId) => {
        const block = parsed.blocks[pastedId];
        return !!block && !acceptsAtRoot(seeded, block.kind);
      });
      if (!refused) return { doc: place(null, seeded.root.length), selection: null };
      const lastRootId = [...seeded.root]
        .reverse()
        .find((rootId) => acceptsAtRoot(seeded, seeded.blocks[rootId]?.kind ?? ""));
      if (!lastRootId) return { doc };
      return {
        doc: place(lastRootId, childIds(getBlock(seeded, lastRootId)).length),
        selection: null,
      };
    }
    const loc = locate(seeded, id);
    if (!loc) return { doc };
    const cur = getBlock(seeded, id);
    const isEmpty =
      cur?.kind === "paragraph" && !(Array.isArray(cur.content) && cur.content.length);
    let d = place(loc.parentId, isEmpty ? loc.index : loc.index + 1);
    if (isEmpty) d = removeBlock(d, id);
    return { doc: d, selection: null };
  });
};

let handleMoved = false;

watch(drag.dragging, (on) => {
  if (on) handleMoved = true;
});

const onDragStart = (e: PointerEvent): void => {
  handleMoved = false;
  if (hoveredLocked.value || menuOpen.value) return;
  if (hoveredId.value) drag.start(e, hoveredId.value);
};

const onMore = (e: MouseEvent): void => {
  if (handleMoved) return;
  const id = hoveredId.value;
  if (!id) return;
  menuOpen.value = true;
  const selected = engine.selection.value;
  const ids =
    selected?.kind === "blocks" && selected.ids.includes(id) ? selected.ids : [id];
  openBlockMenu(engine, ids, e.currentTarget as HTMLElement, () => {
    menuOpen.value = false;
  });
};


const editor = shallowRef<BlockEngine>(engine);

const readerRef = ref<InstanceType<typeof MarBlockReader> | null>(null);

defineExpose({
  engine,
  editor,
  sectionIndex: computed(() => readerRef.value?.sectionIndex ?? 0),
  sectionCount: computed(() => readerRef.value?.sectionCount ?? 0),
  goToSection: (index: number): void => readerRef.value?.goToSection(index),
  nextSection: (): void => readerRef.value?.nextSection(),
  previousSection: (): void => readerRef.value?.previousSection(),
  getMarkdown: (): string => engine.getMarkdown(),
  getHTML: (): string => engine.getHTML(),
  startExternalDrag: (
    e: PointerEvent,
    opts: { label: string; icon?: string; insert: (ctx: { engine: BlockEngine }) => void },
  ): void =>
    drag.startExternal(e, {
      label: opts.label,
      insert: (eng) => opts.insert({ engine: eng }),
    }),
});
</script>

<template>
  <MarBlockReader
    v-if="!engine.editable.value"
    ref="readerRef"
    :engine="engine"
    @section-change="emit('section-change', $event)"
  />

  <div v-else ref="frameEl" class="mar-block-editor" style="position: relative">
    <div
      class="mar-block-editor-content"
      :style="{ '--mar-block-width': documentWidth }"
    >
      <div
        ref="surfaceEl"
        class="mar-block-surface"
        :class="{ 'mar-block-surface-empty': surfaceEmpty }"
        @keydown="onKeydown"
        @copy="onCopy"
        @paste="onPaste"
      >
        <BlockTree :ids="engine.doc.value.root" :engine="engine" />
        <RemoteCursors v-if="binding" :peers="remotePeersRef" :host="surfaceEl" />
      </div>
      <div
        v-if="numbering && !(numbering.skipFirst && pageCount === 1)"
        class="mar-block-page-number"
        :data-format="numbering.format"
        :data-position="numbering.position"
        :style="{
          '--mar-page-from': numbering.from,
          '--mar-page-count': pageCount,
        }"
      />
    </div>

    <div
      v-if="handleVisible && hoveredId && !hoveredLocked"
      class="mar-block-handle-group"
      contenteditable="false"
      :style="{
        position: 'absolute',
        top: `${handleTop}px`,
        left: `${handleLeft}px`,
        transform: 'translate(-100%, -50%)',
      }"
      @pointerenter="overHandle = true"
      @pointerleave="overHandle = false"
    >
      <MarIconBtn
        :title="hoveredLocked ? 'Options' : 'Options, drag to move'"
        class="mar-block-handle-more"
        @pointerdown="onDragStart"
        @click="onMore"
      >
        <MarIcon icon="more-vert" />
      </MarIconBtn>
    </div>

    <Teleport to="body">
      <div
        v-if="drag.dragging.value && drag.ghostHtml.value"
        class="mar-block-drag-ghost"
        :class="{ 'mar-block-drag-ghost-chip': drag.ghostChip.value }"
        :style="{
          top: `${drag.ghostY.value + 6}px`,
          left: `${drag.ghostX.value + 6}px`,
          width: 'max-content',
          maxWidth: '36.5714em',
        }"
        v-html="drag.ghostHtml.value"
      />
    </Teleport>
  </div>
</template>
