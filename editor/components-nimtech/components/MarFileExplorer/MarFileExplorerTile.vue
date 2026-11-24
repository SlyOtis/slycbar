<script setup lang="ts">
import { nextTick, ref, watch } from "vue";
import MarIcon from "../MarIcon";
import MarIconBtn from "../MarIconBtn";
import MarAvatar from "../MarAvatar";
import MarImage from "../MarImage";
import MarTag from "../MarTag";
import type { MarPresenceUser } from "../MarPresence";
import type { IconType } from "@/types/icon.types";
import type { MarFileItem } from "./marFileExplorer.types";

const {
  item,
  icon,
  selected = false,
  selectable = false,
  touch = false,
  showTags = false,
  presence = [],
  renaming = false,
  dragging = false,
  dropTarget = false,
  thumbSrc = "",
  thumbLoaded = false,
  thumbFailed = false,
} = defineProps<{
  item: MarFileItem;
  icon: IconType;
  selected?: boolean;
  selectable?: boolean;
  touch?: boolean;
  showTags?: boolean;
  presence?: MarPresenceUser[];
  renaming?: boolean;
  dragging?: boolean;
  dropTarget?: boolean;
  thumbSrc?: string;
  thumbLoaded?: boolean;
  thumbFailed?: boolean;
}>();

const emit = defineEmits<{
  open: [MouseEvent];
  pick: [MouseEvent];
  more: [MouseEvent];
  enter: [MouseEvent];
  leave: [];
  dragstart: [DragEvent];
  dragover: [DragEvent];
  dragleave: [];
  drop: [DragEvent];
  dragend: [];
  thumbload: [];
  thumberror: [];
  rename: [string];
  renamecancel: [];
}>();

const draft = ref("");
const field = ref<HTMLInputElement | null>(null);

watch(
  () => renaming,
  (on) => {
    if (!on) return;
    draft.value = item.name;
    void nextTick(() => {
      field.value?.focus();
      field.value?.select();
    });
  },
  { immediate: true },
);

const commit = () => {
  const name = draft.value.trim();
  if (name && name !== item.name) emit("rename", name);
  else emit("renamecancel");
};

const HOLD_MS = 500;

let holding: ReturnType<typeof setTimeout> | null = null;
let held = false;

const clearHold = () => {
  if (!holding) return;
  clearTimeout(holding);
  holding = null;
};

const onPointerDown = (event: PointerEvent) => {
  if (event.pointerType === "mouse") return;
  clearHold();
  held = false;
  holding = setTimeout(() => {
    holding = null;
    held = true;
    emit("more", event as unknown as MouseEvent);
  }, HOLD_MS);
};

const onClick = (event: MouseEvent) => {
  clearHold();
  if (renaming) return;
  if (held) {
    held = false;
    return;
  }
  emit("open", event);
};

const tagOverflow = (count: number): string => `+${count - 3}`;
</script>

<template>
  <div
    :class="[
      'mar-file-explorer-item',
      {
        'mar-file-explorer-item-selected': selected,
        'mar-file-explorer-item-folder': item.kind === 'folder',
        'mar-file-explorer-item-dragging': dragging,
        'mar-file-explorer-item-drop-target': dropTarget,
      },
    ]"
    :draggable="!renaming && !item.root"
    @click="onClick"
    @pointerdown="onPointerDown"
    @pointerup="clearHold"
    @pointercancel="clearHold"
    @pointermove="clearHold"
    @contextmenu.prevent="emit('more', $event)"
    @mouseenter="emit('enter', $event)"
    @mouseleave="emit('leave')"
    @dragstart="emit('dragstart', $event)"
    @dragover="emit('dragover', $event)"
    @dragleave="emit('dragleave')"
    @drop="emit('drop', $event)"
    @dragend="emit('dragend')"
  >
    <MarIconBtn
      class="mar-file-explorer-more"
      title="More"
      @click.stop="emit('more', $event)"
    >
      <MarIcon icon="more-vert" class="mar-file-explorer-more-icon" />
    </MarIconBtn>
    <MarIcon
      v-if="thumbFailed"
      icon="triangle-alert"
      class="mar-file-explorer-thumb-alert"
    />
    <MarIcon
      v-if="item.reserved"
      icon="lock"
      title="Reserved"
      :class="[
        'mar-file-explorer-reserved',
        { 'mar-file-explorer-reserved-shifted': thumbFailed },
      ]"
    />
    <div class="mar-file-explorer-icon-area">
      <MarIcon
        v-if="item.index"
        icon="sitemap"
        title="Index"
        class="mar-file-explorer-index"
      />
      <button
        v-if="selectable && !touch"
        type="button"
        class="mar-file-explorer-tick"
        :class="{ 'mar-file-explorer-tick-on': selected }"
        :aria-pressed="selected"
        title="Select"
        @click.stop="emit('pick', $event)"
      >
        <MarIcon icon="check" class="mar-file-explorer-tick-icon" />
      </button>
      <MarImage
        v-if="item.thumbnailUrl && !thumbFailed"
        :src="thumbSrc"
        :alt="item.name"
        class="mar-file-explorer-thumb-img"
        lazy
        @load="emit('thumbload')"
        @error="emit('thumberror')"
      />
      <MarIcon
        v-if="!item.thumbnailUrl || !thumbLoaded"
        :icon="icon"
        class="mar-file-explorer-icon"
      />
      <div v-if="presence.length" class="mar-file-explorer-presence">
        <span
          v-for="u in presence.slice(0, 3)"
          :key="u.id"
          class="mar-file-explorer-presence-item"
        >
          <MarAvatar
            :src="u.imageUrl ?? null"
            :label="u.name"
            class="mar-file-explorer-presence-avatar"
          />
        </span>
        <span v-if="presence.length > 3" class="mar-file-explorer-presence-more"
          >+{{ presence.length - 3 }}</span
        >
      </div>
    </div>
    <input
      v-if="renaming"
      ref="field"
      v-model="draft"
      class="mar-file-explorer-rename"
      @click.stop
      @keydown.enter.prevent="commit"
      @keydown.esc.prevent="emit('renamecancel')"
      @blur="commit"
    />
    <span v-else class="mar-file-explorer-name">{{ item.name }}</span>
    <div v-if="showTags && item.tags && item.tags.length" class="mar-file-explorer-tags">
      <MarTag
        v-for="tag in item.tags.slice(0, 3)"
        :key="tag"
        rounded
        severity="secondary"
        class="mar-file-explorer-tag"
        :label="tag"
      />
      <MarTag
        v-if="item.tags.length > 3"
        rounded
        severity="primary"
        class="mar-file-explorer-tag"
        :label="tagOverflow(item.tags.length)"
      />
    </div>
  </div>
</template>

<style scoped>
.mar-file-explorer-item {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5em;
  border-radius: var(--mar-content-border-radius);
  padding: 1em 0.6667em;
  border: 2px solid transparent;
  cursor: pointer;
  user-select: none;
  background: transparent;
}

.mar-file-explorer-more {
  position: absolute;
  top: 0.3333em;
  right: 0.3333em;
  opacity: 0;
  transition: opacity 0.1s ease;
}

.mar-file-explorer-item:hover .mar-file-explorer-more,
.mar-file-explorer-more:focus-visible {
  opacity: 1;
}

.mar-file-explorer-item-selected {
  background: transparent;
  border-color: transparent;
}

.mar-file-explorer-item-dragging {
  opacity: 0.4;
}

.mar-file-explorer-item-drop-target {
  background: color-mix(in srgb, var(--mar-primary-color), transparent 88%);
  border-color: var(--mar-primary-color);
}

.mar-file-explorer-tick {
  position: absolute;
  top: -0.5em;
  left: -0.5em;
  z-index: 1;
  box-sizing: border-box;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.5em;
  height: 1.5em;
  padding: 0;
  border: 2px solid var(--mar-surface-300);
  border-radius: 50%;
  background: var(--mar-surface-0);
  color: transparent;
  cursor: pointer;
  opacity: 0;
  transition:
    opacity 0.1s ease,
    border-color 0.1s ease,
    background 0.1s ease;
}

.mar-file-explorer-item:hover .mar-file-explorer-tick,
.mar-file-explorer-tick:focus-visible {
  opacity: 1;
}

.mar-file-explorer-tick:hover {
  border-color: var(--mar-primary-color);
  color: var(--mar-surface-400);
}

.mar-file-explorer-tick-on {
  border-color: var(--mar-primary-color);
  background: var(--mar-primary-color);
  color: var(--mar-primary-contrast-color);
  opacity: 1;
}

.mar-file-explorer-tick-on:hover {
  color: var(--mar-primary-contrast-color);
}

.mar-file-explorer-tick-icon {
  width: 70%;
  height: 70%;
}

.mar-file-explorer-item:hover .mar-file-explorer-icon,
.mar-file-explorer-item-selected .mar-file-explorer-icon {
  outline: 2px solid var(--mar-primary-color);
  outline-offset: 0.4167em;
  border-radius: 0.8333em;
}

.mar-file-explorer-item:hover .mar-file-explorer-thumb-img,
.mar-file-explorer-item-selected .mar-file-explorer-thumb-img {
  outline: 2px solid var(--mar-primary-color);
  outline-offset: 0.1667em;
  box-shadow: 0 0 0 0.3333em color-mix(in srgb, var(--mar-primary-color), transparent 75%);
}

.mar-file-explorer-icon-area {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: calc(var(--mar-file-cell-size) * 8 / 15);
  height: calc(var(--mar-file-cell-size) * 8 / 15);
  color: var(--mar-primary-color);
}

.mar-file-explorer-icon {
  width: 68.75%;
  height: 68.75%;
}

.mar-file-explorer-item-folder .mar-file-explorer-icon {
  width: 75%;
  height: 75%;
}

.mar-file-explorer-thumb-img {
  position: absolute;
  inset: 0;
  z-index: 0;
  width: 100%;
  height: 100%;
  border-radius: 0.3333em;
  background: transparent;
  pointer-events: none;
}

.mar-file-explorer-reserved {
  position: absolute;
  top: 0.3333em;
  left: 0.3333em;
  width: 1.3333em;
  height: 1.3333em;
  color: var(--mar-surface-500);
}

.mar-file-explorer-reserved-shifted {
  left: 2em;
}

.mar-file-explorer-index {
  position: absolute;
  top: -0.5em;
  right: -0.5em;
  z-index: 1;
  box-sizing: border-box;
  width: 1.5em;
  height: 1.5em;
  padding: 0.25em;
  border-radius: 50%;
  background: var(--mar-surface-0);
  color: var(--mar-primary-color);
}

.mar-file-explorer-thumb-alert {
  position: absolute;
  top: 0.3333em;
  left: 0.3333em;
  width: 1.3333em;
  height: 1.3333em;
  color: var(--mar-danger-color);
}

.mar-file-explorer-name {
  color: var(--mar-surface-800);
  font-weight: 500;
  text-align: center;
  word-break: break-word;
  max-width: 100%;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  line-height: 1.3;
}

.mar-file-explorer-rename {
  width: 100%;
  box-sizing: border-box;
  padding: 0.1667em 0.3333em;
  border: 1px solid var(--mar-primary-color);
  border-radius: 0.3333em;
  background: var(--mar-surface-0);
  color: var(--mar-surface-800);
  font-family: inherit;
  font-size: 1em;
  font-weight: 500;
  line-height: 1.3;
  text-align: center;
  outline: none;
  user-select: text;
}

.mar-file-explorer-tags {
  display: flex;
  flex-wrap: nowrap;
  align-items: center;
  justify-content: center;
  gap: 0.3333em;
  max-width: 100%;
  overflow: hidden;
  opacity: 0;
  transition: opacity 0.1s ease;
}

.mar-file-explorer-item:hover .mar-file-explorer-tags,
.mar-file-explorer-item-selected .mar-file-explorer-tags {
  opacity: 1;
}

.mar-file-explorer-tag {
  flex: 0 1 auto;
  min-width: 0;
  max-width: 7.2em;
  font-size: 0.8333em;
}

.mar-file-explorer-tag :deep(.mar-tag-label) {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mar-file-explorer-presence {
  position: absolute;
  bottom: -0.3333em;
  right: -0.3333em;
  display: inline-flex;
  align-items: center;
}

.mar-file-explorer-presence-item {
  display: inline-flex;
  font-size: 1.0256em;
  border: 2px solid var(--mar-surface-0);
  border-radius: 50%;
}

.mar-file-explorer-presence-item:not(:first-child) {
  margin-left: -0.4875em;
}

.mar-file-explorer-presence-more {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  margin-left: -0.6667em;
  min-width: 2.2222em;
  height: 2.2222em;
  padding: 0 0.4444em;
  border-radius: 9999px;
  background: var(--mar-surface-300);
  color: var(--mar-surface-700);
  font-size: 0.75em;
  font-weight: 700;
  border: 2px solid var(--mar-surface-0);
}
</style>
