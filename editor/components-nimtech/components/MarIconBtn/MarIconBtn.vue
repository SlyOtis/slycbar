<script setup lang="ts">
import MarIcon from "../MarIcon";
import type { IconType } from "@/types/icon.types";
import { openModal, type ModalHandle } from "@/composables/useModals.ts";

const {
  icon = "",
  disabled = false,
  severity = "subtle",
  scale = false,
  fill = false,
  title = undefined,
  tooltip = undefined,
  active = false,
  overlay = false,
  badge = undefined,
} = defineProps<{
  /** Glyph rendered through MarIcon when the default slot is empty. */
  icon?: string;
  /** Disables the native button and dims the icon. */
  disabled?: boolean;
  /** Visual intent carried by the icon color, subtle walks muted to text on hover, primary holds the primary color, danger turns red on hover. */
  severity?: "subtle" | "primary" | "danger";
  /** Drops the default box so the button fills the element containing it. */
  scale?: boolean;
  /** Drops the default box for a square edged half that takes the height of the row containing it and sizes its width to the glyph, for a button sitting flush inside a grouped control. */
  fill?: boolean;
  /** Native title attribute, suppressed while a tooltip is set. */
  title?: string;
  /** Text shown in an overlay tooltip anchored to the button on hover and focus. */
  tooltip?: string;
  /** Pressed state that colors the icon with the primary color. */
  active?: boolean;
  /** Paints a translucent backdrop behind the button and lifts the glyph to the overlay color, for a button sitting on a banner image. */
  overlay?: boolean;
  /** Small pill rendered at the top right corner of the button, mirrors MarSidebarItem's badge. */
  badge?: string | number;
}>();

defineEmits<{ click: [event: MouseEvent] }>();

let tip: ModalHandle | null = null;

const onEnter = (e: MouseEvent | FocusEvent): void => {
  if (!tooltip) return;
  tip = openModal({
    kind: "tooltip",
    text: tooltip,
    anchor: e.currentTarget as HTMLElement,
    placement: { side: "top" },
  });
};
const onLeave = (): void => {
  tip?.close();
};
</script>

<template>
  <button
    type="button"
    class="mar-icon-btn"
    :data-severity="severity"
    :data-scale="scale ? '1' : '0'"
    :data-fill="fill ? '1' : '0'"
    :data-active="active ? '1' : '0'"
    :data-overlay="overlay ? '1' : '0'"
    :disabled="disabled"
    :title="tooltip ? undefined : title"
    :aria-label="tooltip ?? title"
    @click="$emit('click', $event)"
    @mouseenter="onEnter"
    @mouseleave="onLeave"
    @focus="onEnter"
    @blur="onLeave"
  >
    <slot>
      <MarIcon :icon="(icon as IconType)" />
    </slot>
    <span v-if="badge != null" class="mar-icon-btn-badge">{{ badge }}</span>
  </button>
</template>

<style scoped>
.mar-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  position: relative;
  width: 1.75em;
  height: 1.75em;
  padding: 0.3em;
  font-size: var(--mar-text-base);
  border: none;
  outline: none;
  border-radius: 50%;
  background: transparent;
  color: var(--mar-text-muted-color);
  cursor: pointer;
  flex-shrink: 0;
  user-select: none;
  -webkit-user-select: none;
  transition:
    background 0.15s cubic-bezier(0.4, 0, 0.2, 1),
    color 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-icon-btn[data-scale="1"] {
  width: 100%;
  height: 100%;
  padding: 17%;
}

.mar-icon-btn[data-fill="1"] {
  width: auto;
  height: auto;
  align-self: stretch;
  padding: 0.1875em 0.375em;
  border-radius: 0;
}

.mar-icon-btn[data-fill="1"] :deep(svg),
.mar-icon-btn[data-fill="1"] :deep(.mar-icon-text) {
  width: 0.875em;
  height: 0.875em;
}

.mar-icon-btn-badge {
  position: absolute;
  inset-block-end: 83%;
  inset-inline-end: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 1.8em;
  height: 1.8em;
  padding: 0 0.6em;
  border-radius: 9999px;
  background: var(--mar-primary-color);
  color: var(--mar-primary-contrast-color);
  font-size: var(--mar-text-3xs);
  font-weight: 700;
  line-height: 1;
}

.mar-icon-btn :deep(svg),
.mar-icon-btn :deep(.mar-icon-text) {
  width: 100%;
  height: 100%;
  color: inherit;
  transition: color 0.15s ease;
}

.mar-icon-btn:hover:not(:disabled) {
  background: var(--mar-surface-200);
  color: var(--mar-text-color);
}

.mar-icon-btn:active:not(:disabled) {
  background: var(--mar-surface-300);
}

.mar-icon-btn:focus-visible {
  outline: 0.125em solid var(--mar-primary-color);
  outline-offset: 0.0625em;
  color: var(--mar-text-color);
}

.mar-icon-btn[data-active="1"] {
  color: var(--mar-primary-color);
}

.mar-icon-btn[data-active="1"]:hover:not(:disabled) {
  color: var(--mar-primary-hover-color);
}

.mar-icon-btn[data-severity="primary"] {
  color: var(--mar-primary-color);
}

.mar-icon-btn[data-severity="primary"]:hover:not(:disabled) {
  color: var(--mar-primary-hover-color);
}

.mar-icon-btn[data-severity="danger"]:hover:not(:disabled),
.mar-icon-btn[data-severity="danger"]:focus-visible {
  color: var(--mar-danger-color);
}

.mar-icon-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.mar-icon-btn[data-overlay="1"] {
  background: var(--mar-overlay-backdrop);
  color: var(--mar-overlay-muted-color);
}

.mar-icon-btn[data-overlay="1"]:hover:not(:disabled) {
  background: color-mix(in srgb, var(--mar-overlay-color), transparent 78%);
  color: var(--mar-overlay-color);
}

.mar-icon-btn[data-overlay="1"][data-active="1"] {
  color: var(--mar-overlay-color);
}
</style>
