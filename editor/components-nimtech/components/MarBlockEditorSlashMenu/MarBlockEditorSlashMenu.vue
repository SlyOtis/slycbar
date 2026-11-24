<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import MarIcon from "../MarIcon";
import { marBlockEditorDefaultCommands } from "@/blockedit/commands/slashCommands";
import type { IconType } from "@/types/icon.types";

export interface MarBlockEditorSlashItem {
  /** Command title shown on the row. */
  title: string;
  /** Glyph rendered before the title. */
  icon: string;
  /** Secondary line rendered under the title. */
  description?: string;
  /** Extra terms the caller can match when filtering. */
  keywords?: string[];
  /** Group heading rendered when it differs from the previous item. */
  group?: string;
}

export interface MarBlockEditorSlashMenuState {
  /** Commands to render in order, presorted by group; a string entry names an available block command resolved internally. */
  items: Array<string | MarBlockEditorSlashItem>;
  /**
   * Index of the active row.
   * @minimum 0
   */
  selectedIndex?: number;
  /** Swaps the list for placeholder rows while the search resolves. */
  loading?: boolean;
}

const { state = { items: [], selectedIndex: 0 } } = defineProps<{
  /** Controlled menu state holding the items, the active row, and the loading flag; empty renders nothing. */
  state?: MarBlockEditorSlashMenuState;
}>();

const emit = defineEmits<{
  select: [index: number];
  "update:selectedIndex": [index: number];
}>();

const listEl = ref<HTMLElement | null>(null);

const commandByTitle = new Map(
  marBlockEditorDefaultCommands.map((c) => [c.title, c]),
);

const resolvedItems = computed<MarBlockEditorSlashItem[]>(() =>
  (state.items ?? [])
    .map((item) => {
      if (typeof item !== "string") return item;
      const cmd = commandByTitle.get(item);
      if (!cmd) return null;
      return {
        title: cmd.title,
        icon: cmd.icon ?? "",
        description: cmd.description,
      };
    })
    .filter((item): item is MarBlockEditorSlashItem => Boolean(item)),
);

const activeIndex = computed(() => state.selectedIndex ?? 0);

const onSelect = (i: number) => emit("select", i);
const onHover = (i: number) => emit("update:selectedIndex", i);

const scrollActiveIntoView = () => {
  const list = listEl.value;
  if (!list) return;
  const active = list.querySelector<HTMLElement>(
    ".mar-block-editor-slash-item-active",
  );
  if (!active) return;
  const margin = 4;
  const listRect = list.getBoundingClientRect();
  const activeRect = active.getBoundingClientRect();
  const topOverflow = activeRect.top - listRect.top - margin;
  const bottomOverflow = activeRect.bottom - listRect.bottom + margin;
  let delta = 0;
  if (topOverflow < 0) delta = topOverflow;
  else if (bottomOverflow > 0) delta = bottomOverflow;
  if (delta === 0) return;
  list.scrollTop += delta;
};

watch(
  () => state.selectedIndex,
  () => {
    void nextTick(() => scrollActiveIntoView());
  },
);

watch(
  () => resolvedItems.value.length,
  () => {
    void nextTick(() => scrollActiveIntoView());
  },
);
</script>

<template>
  <div
    v-if="resolvedItems.length || state.loading"
    class="mar-block-editor-slash-menu"
  >
    <div
      v-if="state.loading"
      class="mar-block-editor-slash-list"
      aria-hidden="true"
    >
      <div
        v-for="n in 5"
        :key="`skeleton-${n}`"
        class="mar-block-editor-slash-item mar-block-editor-slash-skeleton"
      >
        <div class="mar-skeleton mar-block-editor-slash-skeleton-icon" />
        <span class="mar-block-editor-slash-text">
          <span class="mar-skeleton mar-block-editor-slash-skeleton-title" />
          <span class="mar-skeleton mar-block-editor-slash-skeleton-desc" />
        </span>
      </div>
    </div>
    <div
      v-else
      ref="listEl"
      class="mar-block-editor-slash-list"
      role="listbox"
    >
      <template v-for="(item, i) in resolvedItems" :key="`${i}-${item.title}`">
        <div
          v-if="item.group && item.group !== resolvedItems[i - 1]?.group"
          class="mar-block-editor-slash-group"
        >
          {{ item.group }}
        </div>
        <button
          type="button"
          role="option"
          :aria-selected="i === activeIndex"
          :class="[
            'mar-block-editor-slash-item',
            { 'mar-block-editor-slash-item-active': i === activeIndex },
          ]"
          @click="onSelect(i)"
          @pointermove="onHover(i)"
        >
          <MarIcon :icon="(item.icon as IconType)" class="mar-block-editor-slash-icon" />
          <span class="mar-block-editor-slash-text">
            <span class="mar-block-editor-slash-title">{{ item.title }}</span>
            <span v-if="item.description" class="mar-block-editor-slash-desc">{{
              item.description
            }}</span>
          </span>
        </button>
      </template>
    </div>
  </div>
</template>

<style scoped>
.mar-block-editor-slash-menu {
  background: var(--mar-surface-0);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 12px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.12);
  min-width: 18em;
  max-height: 22em;
  overflow: hidden;
  font-family: inherit;
  display: flex;
  flex-direction: column;
}

.mar-block-editor-slash-list {
  padding: 0;
  overflow-y: auto;
  flex: 1 1 auto;
  min-height: 0;
  scrollbar-width: thin;
  scrollbar-color: var(--mar-surface-300) transparent;
}

.mar-block-editor-slash-list::-webkit-scrollbar {
  width: 4px;
}

.mar-block-editor-slash-list::-webkit-scrollbar-track {
  background: transparent;
}

.mar-block-editor-slash-list::-webkit-scrollbar-thumb {
  background: var(--mar-surface-300);
  border-radius: 4px;
}

.mar-block-editor-slash-list::-webkit-scrollbar-thumb:hover {
  background: var(--mar-surface-400);
}

.mar-block-editor-slash-group {
  padding: 0.7em 1em 0.3em;
  font-size: 0.625em;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--mar-surface-500);
}

.mar-block-editor-slash-skeleton {
  cursor: default;
  pointer-events: none;
}

.mar-block-editor-slash-skeleton-icon {
  width: 1.1667em;
  height: 1.1667em;
  flex: none;
}

.mar-block-editor-slash-skeleton-title {
  display: block;
  height: 0.8333em;
  width: 42%;
}

.mar-block-editor-slash-skeleton-desc {
  display: block;
  height: 0.6667em;
  width: 70%;
  margin-top: 0.3333em;
}

.mar-block-editor-slash-skeleton:nth-child(even) .mar-block-editor-slash-skeleton-title {
  width: 30%;
}

.mar-block-editor-slash-item {
  display: flex;
  align-items: center;
  gap: 0.6667em;
  width: 100%;
  padding: 0.5833em 0.8333em;
  border: none;
  background: transparent;
  cursor: pointer;
  font-size: 0.75em;
  color: var(--mar-surface-700);
  border-radius: 0;
  text-align: left;
  font-family: inherit;
  transition: background 0.1s ease, color 0.1s ease;
}

.mar-block-editor-slash-item:hover {
  background: var(--mar-surface-100);
  color: var(--mar-text-color);
}

.mar-block-editor-slash-item-active {
  background: var(--mar-highlight-background);
  color: var(--mar-highlight-color);
}

.mar-block-editor-slash-item-active .mar-block-editor-slash-icon,
.mar-block-editor-slash-item-active .mar-block-editor-slash-desc {
  color: inherit;
  opacity: 0.85;
}

.mar-block-editor-slash-icon {
  font-size: 1.3333em;
  color: var(--mar-surface-500);
  width: 1em;
  text-align: center;
  flex-shrink: 0;
}

.mar-block-editor-slash-text {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.mar-block-editor-slash-title {
  font-weight: 500;
}

.mar-block-editor-slash-desc {
  font-size: 0.8333em;
  color: var(--mar-surface-500);
  margin-top: 0.1em;
}
</style>
