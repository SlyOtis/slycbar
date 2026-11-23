<script setup lang="ts">
import { computed, useSlots } from "vue";
import MarIcon from "../MarIcon";
import { openModal, type ModalHandle } from "@/composables/useModals.ts";
import type { MarLinkTarget } from "@/types/link.types";
import { getLinkRel } from "@/utils/link";

export type MarButtonSeverity =
  | "primary"
  | "secondary"
  | "success"
  | "info"
  | "warn"
  | "danger"
  | "help"
  | "contrast";

const {
  label,
  severity = "primary",
  text = false,
  outlined = false,
  rounded = false,
  disabled = false,
  loading = false,
  type = "button",
  title,
  tooltip,
  href,
  target,
} = defineProps<{
  /** Button text, replaced by the default slot when absent. */
  label?: string;
  /** Color scheme of the button. */
  severity?: MarButtonSeverity;
  /** Borderless transparent variant. */
  text?: boolean;
  /** Transparent background with a colored border. */
  outlined?: boolean;
  /** Full pill border radius. */
  rounded?: boolean;
  /** Disables the button and dims it. */
  disabled?: boolean;
  /** Swaps the icon for a spinner and disables the button. */
  loading?: boolean;
  /** Native button type. */
  type?: "button" | "submit" | "reset";
  /** Native tooltip text. */
  title?: string;
  /** Text shown in an overlay tooltip anchored to the button on hover and focus. */
  tooltip?: string;
  /** Renders the button as an anchor with this href instead of a button element. */
  href?: string;
  /** Where the href opens, only with href; _blank opens a new tab with rel noopener noreferrer. */
  target?: MarLinkTarget;
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

const tag = computed(() => (href ? "a" : "button"));

const slots = useSlots();

const iconOnly = computed(() => !label && !slots.default && loading);

const classes = computed(() => [
  "mar-button",
  `mar-button-${severity}`,
  { "mar-button-text": text },
  { "mar-button-outlined": outlined },
  { "mar-button-rounded": rounded },
  { "mar-button-icon-only": iconOnly.value },
  { "mar-button-loading": loading },
]);
</script>

<template>
  <component
    :is="tag"
    :type="!href ? type : undefined"
    :href="href"
    :target="href ? target : undefined"
    :rel="href ? getLinkRel(target) : undefined"
    :class="classes"
    :disabled="!href ? disabled || loading : undefined"
    :title="tooltip ? undefined : title"
    @mouseenter="onEnter"
    @mouseleave="onLeave"
    @focus="onEnter"
    @blur="onLeave"
    @click="$emit('click', $event)"
  >
    <MarIcon v-if="loading" icon="refresh" class="pi-spin mar-button-icon" />
    <span v-if="label" class="mar-button-label">{{ label }}</span>
    <slot v-else />
  </component>
</template>

<style scoped>
.mar-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.5em;
  border: 1px solid transparent;
  cursor: pointer;
  font-family: inherit;
  font-weight: 500;
  font-size: var(--mar-button-font-size);
  border-radius: 0.5em;
  padding: 0.25em 0.6667em;
  transition: background 0.15s cubic-bezier(0.4, 0, 0.2, 1),
    border-color 0.15s cubic-bezier(0.4, 0, 0.2, 1),
    color 0.15s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.15s ease;
  white-space: nowrap;
  line-height: 1.4;
  text-decoration: none;
}

.mar-button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.mar-button:focus-visible {
  outline: 0.1667em solid var(--mar-primary-color);
  outline-offset: 0.0833em;
}

.mar-button-icon {
  font-size: var(--mar-text-2xs);
}

.mar-button-rounded {
  border-radius: 9999px;
}

.mar-button-icon-only {
  padding: 0.25em;
  width: 2em;
  height: 2em;
}

.mar-button-primary {
  background: var(--mar-primary-color);
  color: var(--mar-primary-contrast-color);
  border-color: var(--mar-primary-color);
}

.mar-button-primary:hover:not(:disabled) {
  background: var(--mar-primary-hover-color);
  border-color: var(--mar-primary-hover-color);
}

.mar-button-secondary {
  background: var(--mar-surface-200);
  color: var(--mar-surface-700);
  border-color: var(--mar-surface-300);
}

.mar-button-secondary:hover:not(:disabled) {
  background: var(--mar-surface-300);
  color: var(--mar-surface-800);
}

.mar-button-success {
  background: var(--mar-success-color);
  color: var(--mar-success-contrast-color);
  border-color: var(--mar-success-color);
}

.mar-button-success:hover:not(:disabled) {
  background: var(--mar-success-hover-color);
  border-color: var(--mar-success-hover-color);
}

.mar-button-info {
  background: var(--mar-info-color);
  color: var(--mar-info-contrast-color);
  border-color: var(--mar-info-color);
}

.mar-button-info:hover:not(:disabled) {
  background: var(--mar-info-hover-color);
  border-color: var(--mar-info-hover-color);
}

.mar-button-warn {
  background: var(--mar-warn-color);
  color: var(--mar-warn-contrast-color);
  border-color: var(--mar-warn-color);
}

.mar-button-warn:hover:not(:disabled) {
  background: var(--mar-warn-hover-color);
  border-color: var(--mar-warn-hover-color);
}

.mar-button-danger {
  background: var(--mar-danger-color);
  color: var(--mar-danger-contrast-color);
  border-color: var(--mar-danger-color);
}

.mar-button-danger:hover:not(:disabled) {
  background: var(--mar-danger-hover-color);
  border-color: var(--mar-danger-hover-color);
}

.mar-button-help {
  background: var(--mar-help-color);
  color: var(--mar-help-contrast-color);
  border-color: var(--mar-help-color);
}

.mar-button-help:hover:not(:disabled) {
  background: var(--mar-help-hover-color);
  border-color: var(--mar-help-hover-color);
}

.mar-button-contrast {
  background: var(--mar-surface-800);
  color: var(--mar-surface-0);
  border-color: var(--mar-surface-800);
}

.mar-button-contrast:hover:not(:disabled) {
  background: var(--mar-surface-900);
  border-color: var(--mar-surface-900);
}

.mar-button-text {
  background: transparent;
  border-color: transparent;
}

.mar-button-text.mar-button-primary {
  color: var(--mar-primary-color);
}

.mar-button-text.mar-button-primary:hover:not(:disabled) {
  background: var(--mar-highlight-background);
}

.mar-button-text.mar-button-secondary {
  color: var(--mar-surface-600);
}

.mar-button-text.mar-button-secondary:hover:not(:disabled) {
  background: var(--mar-surface-100);
}

.mar-button-text.mar-button-danger {
  color: var(--mar-danger-color);
}

.mar-button-text.mar-button-danger:hover:not(:disabled) {
  background: color-mix(in srgb, var(--mar-danger-color), transparent 92%);
}

.mar-button-outlined {
  background: transparent;
}

.mar-button-outlined.mar-button-primary {
  color: var(--mar-primary-color);
  border-color: var(--mar-primary-color);
}

.mar-button-outlined.mar-button-primary:hover:not(:disabled) {
  background: var(--mar-highlight-background);
}

.mar-button-outlined.mar-button-secondary {
  color: var(--mar-surface-600);
  border-color: var(--mar-surface-300);
}

.mar-button-outlined.mar-button-secondary:hover:not(:disabled) {
  background: var(--mar-surface-100);
}

.mar-button-outlined.mar-button-danger {
  color: var(--mar-danger-color);
  border-color: var(--mar-danger-color);
}

.mar-button-outlined.mar-button-danger:hover:not(:disabled) {
  background: color-mix(in srgb, var(--mar-danger-color), transparent 92%);
}
</style>
