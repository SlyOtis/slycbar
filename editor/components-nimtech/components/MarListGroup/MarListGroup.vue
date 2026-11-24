<script setup lang="ts">
import { computed, inject, onBeforeUnmount, onMounted, provide, ref, watch } from "vue";
import MarIcon from "../MarIcon";
import { MAR_SIDEBAR_SPLIT, type MarSidebarSplitRow } from "../MarSidebar";
import { MAR_SIDEBAR_EDIT } from "../MarSidebarEdit";
import type { IconType } from "@/types/icon.types";

const { id, label, icon, defaultExpanded = true, expanded: expandedModel = undefined, storageKey, share } = defineProps<{
  /** Identity within a surrounding MarSidebarEdit; required for dragging and dropping. */
  id?: string;
  /** Heading text rendered tiny and uppercase, replaceable through the label slot. */
  label: string;
  /** Glyph rendered at small size before the label. */
  icon?: IconType;
  /** Initial open state of the group. */
  defaultExpanded?: boolean;
  /** Open state bound with `v-model:expanded`, so the app can remember which groups are open; overrides `defaultExpanded` and `storageKey` when given. */
  expanded?: boolean;
  /** localStorage key suffix under which the open state persists when `expanded` is not bound, so the group reopens as it was left. */
  storageKey?: string;
  /**
   * Share of the nav height the group holds as a row of a MarSidebar split nav, bound with `v-model:share` and set by dragging the seam above or below it; unset, the row takes the height its content needs.
   * @minimum 0
   * @maximum 1
   */
  share?: number;
}>();

const emit = defineEmits<{ "update:expanded": [value: boolean]; "update:share": [value: number | undefined] }>();

const edit = inject(MAR_SIDEBAR_EDIT, null);
const draggable = computed(() => !!(edit && id));
const dropOver = computed(() =>
  edit && id && edit.dropTargetId.value === id ? edit.dropPosition.value : null,
);

const headerEl = ref<HTMLElement | null>(null);

const onDragStart = (e: DragEvent) => {
  if (!edit || !id) return;
  e.stopPropagation();
  edit.start(id);
};

const onDragOver = (e: DragEvent) => {
  if (!edit || !id) return;
  e.stopPropagation();
  edit.over(id, e, edit.nest.value ? headerEl.value : null);
};

const onDrop = (e: DragEvent) => {
  if (!edit || !id) return;
  e.stopPropagation();
  edit.drop(id);
};

const onDragEnd = (e: DragEvent) => {
  if (!edit) return;
  e.stopPropagation();
  edit.end();
};

const STORAGE_PREFIX = "mar-list-group:";

const getStored = (): boolean | undefined => {
  if (!storageKey || typeof localStorage === "undefined") return undefined;
  const raw = localStorage.getItem(STORAGE_PREFIX + storageKey);
  return raw === null ? undefined : raw === "1";
};

const putStored = (value: boolean) => {
  if (!storageKey || expandedModel !== undefined || typeof localStorage === "undefined") return;
  localStorage.setItem(STORAGE_PREFIX + storageKey, value ? "1" : "0");
};

const open = ref(expandedModel ?? getStored() ?? defaultExpanded);

watch(
  () => expandedModel,
  (value) => {
    if (value !== undefined) open.value = value;
  },
);

const rootEl = ref<HTMLElement | null>(null);

const row: MarSidebarSplitRow = {
  el: () => rootEl.value,
  header: () => headerEl.value,
  expanded: () => expandedModel,
  share: () => share,
  putExpanded: (value) => {
    open.value = value;
    emit("update:expanded", value);
  },
  putShare: (value) => emit("update:share", value),
};

const split = inject(MAR_SIDEBAR_SPLIT, null);
provide(MAR_SIDEBAR_SPLIT, null);
const pane = split ? split.postRow(row) : null;

const expanded = computed(() => (pane ? !pane.collapsed() : open.value));

onMounted(() => pane?.place());

onBeforeUnmount(() => split?.deleteRow(row));

const toggle = () => {
  if (pane) pane.toggle();
  else {
    open.value = !open.value;
    putStored(open.value);
    emit("update:expanded", open.value);
  }
};

const onKeydown = (e: KeyboardEvent) => {
  if (e.key === "Enter" || e.key === " ") {
    e.preventDefault();
    toggle();
  }
};
</script>

<template>
  <div
    :class="['mar-list-group', {
      'mar-list-group-collapsed': !expanded,
      'mar-list-group-split': !!pane,
      'mar-list-group-draggable': draggable,
      'mar-sidebar-drag-over-before': dropOver === 'before',
      'mar-sidebar-drag-over-after': dropOver === 'after',
      'mar-sidebar-drag-over-inside': dropOver === 'inside',
    }]"
    ref="rootEl"
    :style="pane ? { gridRow: pane.row() } : undefined"
    :draggable="draggable"
    @dragstart="onDragStart"
    @dragover="onDragOver"
    @drop="onDrop"
    @dragend="onDragEnd"
  >
    <div
      ref="headerEl"
      class="mar-list-group-header"
      role="button"
      tabindex="0"
      :aria-expanded="expanded"
      @click="toggle"
      @keydown="onKeydown"
    >
      <span class="mar-list-group-heading">
        <slot name="label">
          <MarIcon v-if="icon" :icon="icon" class="mar-list-group-icon" />
          <span class="mar-list-group-label">{{ label }}</span>
        </slot>
      </span>
      <span v-if="$slots.actions" class="mar-list-group-actions">
        <slot name="actions" />
      </span>
      <MarIcon icon="chevron-down" class="mar-list-group-chevron" />
    </div>
    <div
      class="mar-list-group-body"
    >
      <div class="mar-list-group-inner">
        <slot />
      </div>
    </div>
  </div>
</template>

<style scoped>
.mar-list-group {
  display: flex;
  flex-direction: column;
  position: relative;
  font-size: var(--mar-text-base);
}

.mar-list-group-split {
  grid-column: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  scrollbar-width: thin;
  scrollbar-color: var(--mar-surface-400) transparent;
}

.mar-list-group-split::-webkit-scrollbar {
  width: 0.375em;
}

.mar-list-group-split::-webkit-scrollbar-track {
  background: transparent;
}

.mar-list-group-split::-webkit-scrollbar-thumb {
  background: var(--mar-surface-400);
  border-radius: 9999px;
}

.mar-list-group-split:hover::-webkit-scrollbar-thumb {
  background: var(--mar-surface-500);
}

.mar-list-group-split.mar-list-group-collapsed > .mar-list-group-header {
  padding-block-end: 0.25em;
}

.mar-list-group-draggable > .mar-list-group-header {
  cursor: grab;
}

.mar-list-group-draggable:active > .mar-list-group-header {
  cursor: grabbing;
}

.mar-list-group-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.25em;
  width: 100%;
  min-height: 2em;
  padding: 0.25em 0.875em 0.25em 1em;
  box-sizing: border-box;
  border: none;
  background: transparent;
  cursor: pointer;
  font-family: inherit;
  text-align: left;
  user-select: none;
}

.mar-list-group-heading {
  display: flex;
  align-items: center;
  gap: 0.25em;
  min-width: 0;
  flex: 1 1 auto;
}

.mar-list-group-icon {
  flex-shrink: 0;
  color: var(--mar-text-muted-color);
}

.mar-list-group-actions {
  display: flex;
  align-items: center;
  gap: 0.125em;
  flex: 0 0 auto;
  visibility: hidden;
  opacity: 0;
  transition: opacity 0.15s ease, visibility 0.15s ease;
}

.mar-list-group-header:hover > .mar-list-group-actions,
.mar-list-group-header:focus-within > .mar-list-group-actions {
  visibility: visible;
  opacity: 1;
}

@media (hover: none) {
  .mar-list-group-actions {
    visibility: visible;
    opacity: 1;
  }
}

.mar-list-group-actions :deep(.mar-icon-btn) {
  width: 1.5385em;
  height: 1.5385em;
  font-size: var(--mar-text-sm);
}

.mar-list-group-chevron {
  display: block;
  flex-shrink: 0;
  font-size: var(--mar-text-base);
  color: var(--mar-text-muted-color);
  transition: transform 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-list-group-collapsed .mar-list-group-chevron {
  transform: rotate(-90deg);
}

.mar-list-group-label {
  font-size: var(--mar-text-xs);
  font-weight: 500;
  color: var(--mar-text-muted-color);
}

.mar-list-group-body {
  display: grid;
  grid-template-rows: 1fr;
  transition: grid-template-rows var(--mar-collapse-duration) var(--mar-collapse-ease);
}

.mar-list-group-collapsed > .mar-list-group-body {
  grid-template-rows: 0fr;
}

.mar-list-group-inner {
  min-height: 0;
  overflow: clip;
}

.mar-list-group .mar-list-group > .mar-list-group-header {
  min-height: 2em;
  padding: 0 0.875em 0 0.75em;
}

.mar-list-group .mar-list-group > .mar-list-group-header > .mar-list-group-heading {
  display: grid;
  grid-template-columns: 2.25em minmax(0, 1fr);
  gap: 0;
}

.mar-list-group .mar-list-group > .mar-list-group-header .mar-list-group-icon {
  justify-self: center;
  font-size: var(--mar-text-lg);
}

.mar-list-group .mar-list-group > .mar-list-group-header .mar-list-group-label {
  grid-column: 2;
}

.mar-list-group .mar-list-group > .mar-list-group-body > .mar-list-group-inner {
  padding-inline-start: 1.25em;
}

.mar-list-group-split > .mar-list-group-header {
  position: sticky;
  top: 0;
  z-index: 2;
  min-height: 2.25em;
  background: var(--mar-sidebar-bg);
  animation: mar-list-group-stuck linear both;
  animation-timeline: scroll(nearest);
  animation-range: 0 1em;
}

.mar-list-group-split .mar-list-group > .mar-list-group-header {
  position: sticky;
  top: 2.25em;
  z-index: 1;
  background: var(--mar-sidebar-bg);
}

@keyframes mar-list-group-stuck {
  from {
    box-shadow: 0 1px 0 transparent;
  }
  to {
    box-shadow: 0 1px 0 var(--mar-content-border-color);
  }
}
</style>
