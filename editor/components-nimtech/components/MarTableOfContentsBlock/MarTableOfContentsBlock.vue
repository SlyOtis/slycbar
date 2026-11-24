<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import type { BlockEngine, BlockId, MarBlock, MarDocument } from "@/blockedit/index.ts";
import { deltaText } from "@/blockedit/model/delta.ts";
import { childIds } from "@/blockedit/model/tree.ts";
import MarIcon from "../MarIcon";

interface TocEntry {
  id: string;
  level: number;
  text: string;
  number: string;
}

const props = defineProps<{
  /** Block editor engine whose document tree is scanned for heading blocks. */
  engine: BlockEngine;
  /** Block node whose options control title visibility, bare styling, auto width, font scale, and placement inline or on a side of the page. */
  node: {
    options: {
      showTitle?: boolean;
      bare?: boolean;
      autoWidth?: boolean;
      fontScale?: number;
      placement?: "inline" | "left" | "right";
    };
  };
}>();

const showTitle = computed(() => props.node.options.showTitle !== false);
const bare = computed(() => !!props.node.options.bare);
const autoWidth = computed(() => !!props.node.options.autoWidth);
const fontScale = computed(() => Number(props.node.options.fontScale) || 1);
const placement = computed(() => props.node.options.placement ?? "inline");
const side = computed(() => placement.value !== "inline");
const wrapperRef = ref<{ $el: HTMLElement } | null>(null);
const frame = ref<HTMLElement | null>(null);

const COMPACT_BELOW_REM = 52;
const compact = ref(false);
const frameObserver =
  typeof ResizeObserver === "undefined"
    ? null
    : new ResizeObserver(([entry]) => {
        const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
        compact.value = (entry?.contentRect.width ?? 0) < COMPACT_BELOW_REM * rem;
      });

onMounted(() => {
  frame.value = wrapperRef.value?.$el.closest<HTMLElement>(".mar-block-editor") ?? null;
  if (frame.value) frameObserver?.observe(frame.value);
});

onBeforeUnmount(() => frameObserver?.disconnect());

const headingText = (block: MarBlock): string =>
  (Array.isArray(block.content) ? deltaText(block.content) : "") || "Untitled";

const collect = (
  doc: MarDocument,
  ids: BlockId[],
  out: { id: string; level: number; text: string }[],
): void => {
  for (const id of ids) {
    const block = doc.blocks[id];
    if (!block) continue;
    if (block.kind === "heading") {
      out.push({
        id: block.id,
        level: Number(block.options.level) || 1,
        text: headingText(block),
      });
    }
    collect(doc, childIds(block), out);
  }
};

const entries = computed<TocEntry[]>(() => {
  const found: { id: string; level: number; text: string }[] = [];
  collect(props.engine.doc.value, props.engine.doc.value.root, found);
  const start = found.length ? Math.min(...found.map((f) => f.level)) : 1;
  const counters = [0, 0, 0, 0, 0, 0, 0];
  return found.map((f) => {
    counters[f.level] = (counters[f.level] ?? 0) + 1;
    for (let l = f.level + 1; l <= 6; l += 1) counters[l] = 0;
    const parts: number[] = [];
    for (let l = start; l <= f.level; l += 1) parts.push(counters[l] ?? 0);
    return { ...f, number: parts.join(".") };
  });
});

const minLevel = computed(() =>
  entries.value.length ? Math.min(...entries.value.map((e) => e.level)) : 1,
);

const goTo = (entry: TocEntry): void => {
  const el = document.querySelector(`[data-block-id="${entry.id}"]`);
  el?.scrollIntoView({ behavior: "smooth", block: "start" });
};
</script>

<template>
  <NodeViewWrapper
    ref="wrapperRef"
    :class="{ 'mar-toc-anchor': side }"
    contenteditable="false"
  >
    <div v-if="side && engine.editable.value" class="mar-toc-marker">
      <MarIcon icon="sidebar" />
      <span>Legend, {{ placement }} side</span>
    </div>
    <Teleport :to="frame ?? 'body'" :disabled="!side || !frame">
      <div
        :class="side ? ['mar-toc-side', `mar-toc-side-${placement}`, { 'mar-toc-side-compact': compact }] : 'mar-toc-flow'"
        contenteditable="false"
      >
        <nav
          class="mar-toc"
          :class="{ 'mar-toc-bare': bare, 'mar-toc-auto': autoWidth && !side }"
          :style="{ '--mar-toc-scale': fontScale }"
        >
          <div v-if="showTitle" class="mar-toc-title">Table of contents</div>
          <div v-if="!entries.length" class="mar-toc-empty">No headings yet</div>
          <button
            v-for="entry in entries"
            :key="entry.id"
            type="button"
            class="mar-toc-item"
            :title="entry.text"
            :style="{ '--mar-toc-depth': entry.level - minLevel }"
            @click="goTo(entry)"
          >
            <span class="mar-toc-mark" />
            <span class="mar-toc-number">{{ entry.number }}</span>
            <span class="mar-toc-text">{{ entry.text }}</span>
          </button>
        </nav>
      </div>
    </Teleport>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-toc {
  margin: 0.6154em 0;
  padding: 0.7692em 0.9231em;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
  background: var(--mar-surface-50);
  font-size: calc(0.8125em * var(--mar-toc-scale));
}

.mar-toc-bare {
  padding: 0;
  border: none;
  background: transparent;
}

.mar-toc-auto {
  display: inline-block;
  width: fit-content;
}

.mar-toc-title {
  font-size: 0.846em;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--mar-surface-500);
  margin-bottom: 0.5456em;
}

.mar-toc-empty {
  font-size: 1em;
  color: var(--mar-surface-400);
}

.mar-toc-item {
  display: flex;
  align-items: baseline;
  gap: 0.6154em;
  width: 100%;
  padding: 0.2308em 0.3077em;
  border: none;
  background: transparent;
  border-radius: 4px;
  cursor: pointer;
  font-family: inherit;
  font-size: 1em;
  color: var(--mar-text-color);
  padding-left: calc(var(--mar-toc-depth, 0) * 1.0769em);
  text-align: left;
  transition: background 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-toc-item:hover {
  background: var(--mar-surface-100);
}

.mar-toc-number {
  flex-shrink: 0;
  color: var(--mar-surface-400);
  font-weight: 600;
}

.mar-toc-text {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.mar-toc-mark {
  display: none;
  flex-shrink: 0;
  block-size: 0.2308em;
  inline-size: calc(1.5385em - var(--mar-toc-depth, 0) * 0.3846em);
  min-inline-size: 0.6154em;
  border-radius: 999px;
  background: var(--mar-surface-300);
}

.mar-toc-marker {
  display: inline-flex;
  align-items: center;
  gap: 0.5em;
  margin: 0.3333em 0;
  padding: 0.1667em 0.6667em;
  border: 1px dashed var(--mar-content-border-color);
  border-radius: 999px;
  font-size: 0.75em;
  color: var(--mar-surface-500);
}

.mar-toc-marker .mar-icon {
  font-size: 1.5238em;
}

.mar-toc-side {
  position: absolute;
  inset-block: 0;
  inline-size: var(--mar-toc-side-width);
  display: flex;
  flex-direction: column;
  padding-block: 0.75em;
  box-sizing: border-box;
  pointer-events: none;
  z-index: 1;
}

.mar-toc-side-right {
  inset-inline-end: 0;
  padding-inline-end: 0.75em;
  align-items: flex-end;
}

.mar-toc-side-left {
  inset-inline-start: 0;
  padding-inline-start: 0.75em;
  align-items: flex-start;
}

.mar-toc-side .mar-toc {
  position: sticky;
  inset-block-start: 0.9231em;
  box-sizing: border-box;
  inline-size: 100%;
  max-block-size: calc(100vh - 1.8462em);
  margin: 0;
  overflow-y: auto;
  pointer-events: auto;
}

.mar-toc-side-compact .mar-toc:not(:hover, :focus-within) {
  inline-size: auto;
  padding: 0.4615em 0.3077em;
  border-color: transparent;
  background: transparent;
}

.mar-toc-side-compact .mar-toc:not(:hover, :focus-within) :is(.mar-toc-title, .mar-toc-empty, .mar-toc-number, .mar-toc-text) {
  display: none;
}

.mar-toc-side-compact .mar-toc:not(:hover, :focus-within) .mar-toc-item {
  padding-block: 0.3077em;
  padding-inline: 0;
}

.mar-toc-side-compact .mar-toc:not(:hover, :focus-within) .mar-toc-mark {
  display: block;
}

.mar-toc-side-compact.mar-toc-side-right .mar-toc:not(:hover, :focus-within) .mar-toc-item {
  justify-content: flex-end;
}

.mar-toc-side-compact .mar-toc:is(:hover, :focus-within) {
  inline-size: max-content;
  max-inline-size: 18em;
  border-color: var(--mar-content-border-color);
  background: var(--mar-surface-50);
  box-shadow: 0 0.3077em 1.2308em color-mix(in srgb, var(--mar-surface-900) 12%, transparent);
}
</style>
