<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import MarIcon from "../MarIcon";
import type { IconType } from "@/types/icon.types";

export type MarTagSeverity =
  | "primary"
  | "secondary"
  | "success"
  | "info"
  | "warn"
  | "danger"
  | "contrast";

const {
  label,
  icon,
  severity = "secondary",
  rounded = false,
  editable = false,
  editing = false,
} = defineProps<{
  /** Chip text rendered as the default slot fallback. */
  label?: string;
  /** MarIcon name rendered before the label. */
  icon?: string;
  /** Background and text color pair the chip uses. */
  severity?: MarTagSeverity;
  /** Switches the small corner radius to a full pill. */
  rounded?: boolean;
  /** Shows a pencil over the end of the tag on hover and focus that emits `edit`; the tag keeps its size. */
  editable?: boolean;
  /** Replaces the pencil with save and cancel buttons, Enter saving and Escape cancelling; the host slots the editing control. */
  editing?: boolean;
}>();

const emit = defineEmits<{
  edit: [];
  save: [];
  cancel: [];
}>();

const labelEl = ref<HTMLElement | null>(null);

watch(
  () => editing,
  (value) => {
    if (!value) return;
    void nextTick(() => labelEl.value?.querySelector<HTMLElement>("input, textarea, button, [contenteditable], [tabindex]")?.focus());
  },
);

const onKeydown = (event: KeyboardEvent) => {
  if (!editing) return;
  if (event.key === "Enter") {
    event.preventDefault();
    emit("save");
  } else if (event.key === "Escape") {
    event.preventDefault();
    emit("cancel");
  }
};

const classes = computed(() => [
  "mar-tag",
  `mar-tag-${severity}`,
  { "mar-tag-rounded": rounded, "mar-tag-editable": editable, "mar-tag-editing": editing },
]);
</script>

<template>
  <span :class="classes" @keydown.capture="onKeydown">
    <MarIcon v-if="icon" :icon="(icon as IconType)" class="mar-tag-icon" />
    <span ref="labelEl" class="mar-tag-label">
      <slot>{{ label }}</slot>
    </span>
    <template v-if="editable">
      <template v-if="editing">
        <button type="button" class="mar-tag-save" aria-label="Save" @mousedown.prevent @click="emit('save')">
          <MarIcon icon="check" />
        </button>
        <button type="button" class="mar-tag-cancel" aria-label="Cancel" @mousedown.prevent @click="emit('cancel')">
          <MarIcon icon="cross" />
        </button>
      </template>
      <button v-else type="button" class="mar-tag-edit" aria-label="Edit" @click="emit('edit')">
        <MarIcon icon="pencil" />
      </button>
    </template>
  </span>
</template>

<style scoped>
.mar-tag {
  display: inline-flex;
  align-items: center;
  gap: 0.2727em;
  padding: 0.0909em 0.5455em;
  background: var(--mar-tag-background, transparent);
  border-radius: 3px;
  font-size: 0.6875em;
  font-weight: 600;
  line-height: 1.4;
  white-space: nowrap;
}

.mar-tag-rounded {
  border-radius: 9999px;
}

.mar-tag-editable {
  position: relative;
}

.mar-tag-edit,
.mar-tag-save,
.mar-tag-cancel {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  border: none;
  border-radius: inherit;
  background: transparent;
  color: inherit;
  font: inherit;
  cursor: pointer;
}

.mar-tag-edit {
  position: absolute;
  inset-block: 0;
  inset-inline-end: 0;
  padding-inline: 0.5455em;
  padding-inline-start: 1.2em;
  background:
    linear-gradient(to right, transparent, var(--mar-tag-background, transparent) 45%),
    linear-gradient(to right, transparent, var(--mar-surface-0) 45%);
  opacity: 0;
  transition: opacity 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-tag-editable:hover .mar-tag-edit,
.mar-tag-editable:focus-within .mar-tag-edit {
  opacity: 1;
}

.mar-tag-edit:hover,
.mar-tag-save:hover,
.mar-tag-cancel:hover {
  color: var(--mar-primary-color);
}

.mar-tag-edit > *,
.mar-tag-save > *,
.mar-tag-cancel > * {
  font-size: 1.4545em;
}

.mar-tag-primary {
  --mar-tag-background: var(--mar-highlight-background);
  color: var(--mar-highlight-color);
}

.mar-tag-secondary {
  --mar-tag-background: var(--mar-surface-200);
  color: var(--mar-surface-700);
}

.mar-tag-success {
  --mar-tag-background: color-mix(in srgb, var(--mar-success-color), transparent 85%);
  color: var(--mar-success-hover-color);
}

.mar-tag-info {
  --mar-tag-background: color-mix(in srgb, var(--mar-info-color), transparent 85%);
  color: var(--mar-info-hover-color);
}

.mar-tag-warn {
  --mar-tag-background: color-mix(in srgb, var(--mar-warn-color), transparent 85%);
  color: var(--mar-warn-hover-color);
}

.mar-tag-danger {
  --mar-tag-background: color-mix(in srgb, var(--mar-danger-color), transparent 85%);
  color: var(--mar-danger-hover-color);
}

.mar-tag-contrast {
  --mar-tag-background: var(--mar-surface-800);
  color: var(--mar-surface-0);
}
</style>
