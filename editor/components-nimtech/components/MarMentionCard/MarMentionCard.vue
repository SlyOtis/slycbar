<script setup lang="ts">
import MarIcon from "../MarIcon";
import MarImage from "../MarImage";
import type { IconType } from "@/types/icon.types";

const props = defineProps<{
  /** Url for the media area at the top of the card. */
  image?: string;
  /** Single line title shown in the head row. */
  title: string;
  /** Body paragraph rendered under the head. */
  description?: string;
  /** Category text rendered uppercase under the title. */
  type?: string;
  /** Icon name shown before the title, falling back to at. */
  icon?: string;
  /** Enables the pointer cursor, the open glyph, and the click to navigate path. */
  clickable?: boolean;
  /** Callback fired on mouse enter so the opener can cancel its scheduled close. */
  onEnter: () => void;
  /** Callback fired on mouse leave so the opener can schedule the close. */
  onLeave: () => void;
  /** Callback fired when the card body is clicked while clickable is set. */
  onNavigate: () => void;
  /** Renders a more button in the bottom strip and receives it as the anchor for a follow up menu. */
  onMore?: (anchor: HTMLElement) => void;
  /** Renders a grip handle in the bottom strip and receives its pointerdown event. */
  onDragStart?: (e: PointerEvent) => void;
}>();

const onClick = () => {
  if (props.clickable) props.onNavigate();
};

const onMoreClick = (e: MouseEvent) => {
  e.stopPropagation();
  props.onMore?.(e.currentTarget as HTMLElement);
};

const onHandleDown = (e: PointerEvent) => {
  e.stopPropagation();
  props.onDragStart?.(e);
};
</script>

<template>
  <div
    class="mar-mention-card"
    :class="{ 'mar-mention-card-clickable': clickable }"
    @mouseenter="onEnter"
    @mouseleave="onLeave"
    @click="onClick"
  >
    <div v-if="image" class="mar-mention-card-media">
      <MarImage :src="image" />
    </div>
    <div class="mar-mention-card-body">
      <div class="mar-mention-card-head">
        <MarIcon
          :icon="(icon as IconType) || 'at'"
          class="mar-mention-card-icon"
        />
        <span class="mar-mention-card-title">{{ title }}</span>
        <MarIcon
          v-if="clickable"
          icon="open-in-new"
          class="mar-mention-card-go"
        />
      </div>
      <span v-if="type" class="mar-mention-card-type">{{ type }}</span>
      <p v-if="description" class="mar-mention-card-desc">{{ description }}</p>
    </div>
    <div v-if="onMore || onDragStart" class="mar-mention-card-strip">
      <button
        v-if="onDragStart"
        type="button"
        class="mar-mention-card-strip-btn mar-mention-card-drag"
        title="Drag"
        @pointerdown="onHandleDown"
        @click.stop
      >
        <MarIcon icon="grip-vertical" class="mar-mention-card-strip-icon" />
      </button>
      <button
        v-if="onMore"
        type="button"
        class="mar-mention-card-strip-btn"
        title="More"
        @click="onMoreClick"
      >
        <MarIcon icon="more-vert" class="mar-mention-card-strip-icon" />
      </button>
    </div>
  </div>
</template>

<style scoped>
.mar-mention-card {
  width: 16em;
  max-width: 90vw;
  display: flex;
  flex-direction: column;
  background: var(--mar-surface-0);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 10px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.15);
  overflow: hidden;
  font-family: inherit;
}

.mar-mention-card-clickable {
  cursor: pointer;
}

.mar-mention-card-clickable:hover {
  border-color: var(--mar-surface-400);
}

.mar-mention-card-media {
  width: 100%;
  aspect-ratio: 16 / 9;
  background: var(--mar-surface-100);
}

.mar-mention-card-media > * {
  width: 100%;
  height: 100%;
  display: block;
}

.mar-mention-card-body {
  padding: 0.625em 0.75em;
  display: flex;
  flex-direction: column;
  gap: 0.25em;
}

.mar-mention-card-head {
  display: flex;
  align-items: center;
  gap: 0.375em;
}

.mar-mention-card-icon {
  color: var(--mar-primary-color);
  flex-shrink: 0;
}

.mar-mention-card-title {
  flex: 1;
  min-width: 0;
  font-size: 0.8125em;
  font-weight: 600;
  color: var(--mar-text-color);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mar-mention-card-go {
  color: var(--mar-surface-400);
  flex-shrink: 0;
}

.mar-mention-card-type {
  font-size: 0.625em;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--mar-surface-500);
}

.mar-mention-card-desc {
  margin: 0;
  font-size: 0.75em;
  line-height: 1.4;
  color: var(--mar-surface-600);
}

.mar-mention-card-strip {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.0625em 0.25em;
  border-top: 1px solid var(--mar-content-border-color);
  background: var(--mar-surface-50);
}

.mar-mention-card-strip-btn {
  width: 1.7em;
  height: 1.7em;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  border: none;
  border-radius: 3px;
  background: transparent;
  color: var(--mar-surface-500);
  font-size: 0.625em;
  cursor: pointer;
  transition: background 0.12s ease, color 0.12s ease;
}

.mar-mention-card-strip-icon {
  font-size: 1.6em;
}

.mar-mention-card-strip-btn:hover {
  background: var(--mar-surface-200);
  color: var(--mar-text-color);
}

.mar-mention-card-drag {
  cursor: grab;
}

.mar-mention-card-drag:active {
  cursor: grabbing;
}
</style>
