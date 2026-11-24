<script lang="ts">
import { type InjectionKey, type Ref } from "vue";

export type MarSidebarDropPosition = "before" | "after" | "inside";

export interface MarSidebarReorder {
  draggedId: string;
  targetId: string;
  position: MarSidebarDropPosition;
}

export interface MarSidebarEditContext {
  editing: Ref<boolean>;
  nest: Ref<boolean>;
  draggingId: Ref<string | null>;
  dropTargetId: Ref<string | null>;
  dropPosition: Ref<MarSidebarDropPosition>;
  start: (id: string) => void;
  over: (id: string, event: DragEvent, row?: HTMLElement | null) => void;
  drop: (id: string) => void;
  end: () => void;
}

export const MAR_SIDEBAR_EDIT: InjectionKey<MarSidebarEditContext> =
  Symbol("marSidebarEdit");
</script>

<script setup lang="ts">
import { provide, ref, toRef, type VNode } from "vue";

const { editing = false, nest = false } = defineProps<{
  /** Paints the wiggling edit mode; entries with an id are draggable either way. */
  editing?: boolean;
  /** Lets a drop on the middle third of an entry land inside it as the position `inside`. */
  nest?: boolean;
}>();

const emit = defineEmits<{
  "update:editing": [value: boolean];
  reorder: [move: MarSidebarReorder];
}>();

defineSlots<{ default?: () => VNode[] }>();

const editingRef = toRef(() => editing);
const nestRef = toRef(() => nest);
const draggingId = ref<string | null>(null);
const dropTargetId = ref<string | null>(null);
const dropPosition = ref<MarSidebarDropPosition>("before");

const reset = () => {
  draggingId.value = null;
  dropTargetId.value = null;
};

const start = (id: string) => {
  draggingId.value = id;
};

const over = (id: string, event: DragEvent, row?: HTMLElement | null) => {
  if (!draggingId.value || id === draggingId.value) return;
  event.preventDefault();
  const el = row ?? (event.currentTarget as HTMLElement);
  const rect = el.getBoundingClientRect();
  const share = rect.height > 0 ? (event.clientY - rect.top) / rect.height : 0;
  if (nest) dropPosition.value = share < 1 / 3 ? "before" : share > 2 / 3 ? "after" : "inside";
  else dropPosition.value = share < 0.5 ? "before" : "after";
  dropTargetId.value = id;
};

const drop = (id: string) => {
  const dragged = draggingId.value;
  if (!dragged || dragged === id) return reset();
  emit("reorder", { draggedId: dragged, targetId: id, position: dropPosition.value });
  reset();
};

const end = () => reset();

provide(MAR_SIDEBAR_EDIT, {
  editing: editingRef,
  nest: nestRef,
  draggingId,
  dropTargetId,
  dropPosition,
  start,
  over,
  drop,
  end,
});
</script>

<template>
  <div :class="['mar-sidebar-edit', { 'mar-sidebar-edit-active': editing }]">
    <slot />
  </div>
</template>

<style scoped>
.mar-sidebar-edit {
  display: flex;
  flex-direction: column;
}

.mar-sidebar-edit-active :deep(.mar-sidebar-item),
.mar-sidebar-edit-active :deep(.mar-list-group) {
  animation: mar-sidebar-wiggle 1.3s ease-in-out infinite;
}

.mar-sidebar-edit-active :deep(.mar-sidebar-item:nth-child(even)),
.mar-sidebar-edit-active :deep(.mar-list-group:nth-child(even)) {
  animation-delay: 0.13s;
}

.mar-sidebar-edit-active :deep(.mar-sidebar-item-trigger) {
  pointer-events: none;
}

@keyframes mar-sidebar-wiggle {
  0%, 100% { transform: rotate(0deg); }
  30% { transform: rotate(-0.35deg); }
  70% { transform: rotate(0.35deg); }
}

.mar-sidebar-edit :deep(.mar-sidebar-drag-over-before)::before,
.mar-sidebar-edit :deep(.mar-sidebar-drag-over-after)::after {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  height: 2px;
  background: var(--mar-primary-color);
  pointer-events: none;
  z-index: 1;
}

.mar-sidebar-edit :deep(.mar-sidebar-drag-over-before)::before {
  top: 0;
}

.mar-sidebar-edit :deep(.mar-sidebar-drag-over-after)::after {
  bottom: 0;
}

.mar-sidebar-edit :deep(.mar-sidebar-drag-over-inside > .mar-sidebar-item-trigger),
.mar-sidebar-edit :deep(.mar-sidebar-drag-over-inside > .mar-list-group-header) {
  background: var(--mar-highlight-background);
  outline: 1px solid var(--mar-primary-color);
  outline-offset: -1px;
  border-radius: 0.5em;
}

.mar-sidebar-edit :deep(.mar-sidebar-drag-over-inside > .mar-sidebar-item-trigger) {
  border-radius: 0.5714em;
}
</style>
