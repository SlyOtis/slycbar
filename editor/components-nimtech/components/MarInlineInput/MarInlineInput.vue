<script lang="ts">
import { type InjectionKey } from "vue";

export interface MarInlineInputField {
  labelId: string;
}

export const MAR_INLINE_INPUT_FIELD: InjectionKey<MarInlineInputField> =
  Symbol("marInlineInputField");
</script>

<script setup lang="ts">
import { inject, onBeforeUnmount, onMounted, provide, ref, useId, watch, type Ref } from "vue";
import MarIcon from "../MarIcon";
import MarIconBtn from "../MarIconBtn";
import { useViewport } from "@/composables/useViewport";
import type { IconType } from "@/types/icon.types";

const {
  icon,
  label,
  description,
  value = "",
  editing = false,
  open = false,
  stacked = false,
  disabled = false,
  invalid = false,
  error,
  width,
} = defineProps<{
  /** Icon name rendered through MarIcon in the first grid column. */
  icon: string;
  /** Property name shown beside the icon. */
  label: string;
  /** What the field means, one line under the label. */
  description?: string;
  /** Display text shown while not editing, also the text the copy button writes to the clipboard. */
  value?: string;
  /** Seeds and syncs the internal editing flag. */
  editing?: boolean;
  /** Permanently shows the slotted field and drops the edit button. */
  open?: boolean;
  /** Below the mobile breakpoint, moves the field cell to a full width line under the label; above it every row stacks the same way, whatever this prop says, while its own width is under 25em, where the label column reaches its minimum. */
  stacked?: boolean;
  /** Blocks editing and replaces the pencil with a copy to clipboard button. */
  disabled?: boolean;
  /** Colors the icon and label red. */
  invalid?: boolean;
  /** Error line rendered under the value or field. */
  error?: string;
  /** CSS length feeding the row grid width variable. */
  width?: string;
}>();

const emit = defineEmits<{
  edit: [];
  save: [];
}>();

const field: MarInlineInputField = { labelId: useId() };
provide(MAR_INLINE_INPUT_FIELD, field);

const pageEditing = inject<Ref<boolean>>("marPageEditing", ref(false));

const isEditing = ref(editing);

watch(
  () => editing,
  (v) => {
    isEditing.value = v;
  },
);

const handleEdit = () => {
  isEditing.value = true;
  emit("edit");
};

const handleSave = () => {
  if (pageEditing.value) return;
  if (!editing) isEditing.value = false;
  emit("save");
};

const copied = ref(false);

const copyValue = () => {
  navigator.clipboard.writeText(value);
  copied.value = true;
  setTimeout(() => {
    copied.value = false;
  }, 1500);
};

const { mobile } = useViewport();

const root = ref<HTMLElement | null>(null);
const narrow = ref(false);
let observer: ResizeObserver | null = null;

const measure = () => {
  const el = root.value;
  if (!el) return;
  const style = getComputedStyle(el);
  const basis = style.gridTemplateColumns.startsWith("subgrid")
    ? el.offsetWidth
    : el.clientWidth - (parseFloat(style.paddingLeft) || 0) - (parseFloat(style.paddingRight) || 0);
  narrow.value = basis < 25 * parseFloat(style.fontSize);
};

onMounted(() => {
  if (typeof ResizeObserver === "undefined" || !root.value) return;
  observer = new ResizeObserver(measure);
  observer.observe(root.value);
});

onBeforeUnmount(() => {
  observer?.disconnect();
});
</script>

<template>
  <div
    ref="root"
    class="mar-inline-input"
    :class="{
      editing: isEditing || open,
      open,
      stacked: mobile ? stacked : narrow,
      disabled,
      invalid,
      'has-actions': !!$slots.actions,
      'mar-inline-input-mobile': mobile,
    }"
    :style="{
      '--mar-inline-input-width': width,
    }"
  >
    <MarIcon :icon="(icon as IconType)" class="mar-inline-input-icon" />
    <span :id="field.labelId" class="mar-inline-input-label" :title="label">
      {{ label }}
      <small v-if="description" class="mar-inline-input-description" :title="description">{{ description }}</small>
    </span>
    <div class="mar-inline-input-cell">
      <div
        v-if="(isEditing || open) && !disabled"
        class="mar-inline-input-field"
        @click.stop
        @keydown.enter="handleSave"
      >
        <slot />
      </div>
      <span v-else class="mar-inline-input-value">{{ value }}</span>
      <small v-if="error" class="mar-inline-input-error">{{ error }}</small>
    </div>
    <div v-if="!open || $slots.actions" class="mar-inline-input-action">
      <template v-if="!open">
        <template v-if="!disabled">
          <span v-if="isEditing && !pageEditing" class="mar-inline-input-save">
            <MarIconBtn icon="check" severity="primary" scale tooltip="Save" @click="handleSave" />
          </span>
          <span v-else-if="!isEditing" class="mar-inline-input-edit">
            <MarIconBtn icon="pencil" scale tooltip="Edit" @click="handleEdit" />
          </span>
        </template>
        <span v-else class="mar-inline-input-copy">
          <MarIconBtn
            :icon="copied ? 'check' : 'copy'"
            scale
            :tooltip="copied ? 'Copied' : 'Copy to clipboard'"
            @click="copyValue"
          />
        </span>
      </template>
      <slot name="actions" />
    </div>
  </div>
</template>

<style scoped>
.mar-inline-input {
  align-items: start;
  display: grid;
  width: var(--mar-inline-input-width, auto);
  grid-template-columns:
    1.25em var(--mar-field-label-width)
    minmax(0, 1fr) minmax(2em, max-content);
  gap: 0.75em var(--mar-field-label-gap);
  padding: 0.5em 0.5em;
  border-radius: calc(var(--mar-field-radius) * 0.9375);
}

.mar-inline-input + .mar-inline-input {
  border-top: 1px solid transparent;
  background-image: linear-gradient(
    90deg,
    transparent,
    var(--mar-content-border-color),
    transparent
  );
  background-size: 100% 1px;
  background-repeat: no-repeat;
  background-position: top;
}

.mar-inline-input-icon {
  align-self: start;
  margin-block-start: calc((var(--mar-field-min-height) - 1em) / 2);
  font-size: 0.875em;
  color: var(--mar-text-muted-color);
  text-align: center;
}

.mar-inline-input-label {
  line-height: var(--mar-field-min-height);
  font-size: var(--mar-text-sm);
  font-weight: 400;
  color: var(--mar-text-color);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.mar-inline-input-description {
  display: block;
  margin-block-start: -0.5em;
  font-size: var(--mar-text-2xs);
  line-height: 1.3;
  color: var(--mar-text-muted-color);
  white-space: normal;
}

.mar-inline-input-cell {
  min-height: var(--mar-field-min-height);
  display: flex;
  flex-direction: column;
  justify-content: center;
}

.mar-inline-input-field {
  width: 100%;
  display: grid;
  grid-template-rows: minmax(var(--mar-field-min-height), auto);
  align-items: center;
  justify-items: start;
}

.mar-inline-input-field :deep(input),
.mar-inline-input-field :deep(textarea),
.mar-inline-input-field :deep(.mar-field),
.mar-inline-input-field :deep(.mar-text-input),
.mar-inline-input-field :deep(.mar-dropdown),
.mar-inline-input-field :deep(.mar-multi-select),
.mar-inline-input-field :deep(.mar-date-dropdown) {
  width: 100%;
}

.mar-inline-input-value {
  font-size: var(--mar-field-font-size);
  font-weight: 400;
  line-height: 1.4;
  color: var(--mar-text-color);
  overflow-wrap: anywhere;
}

.mar-inline-input-action {
  align-self: start;
  min-height: var(--mar-field-min-height);
  display: flex;
  align-items: center;
  justify-content: center;
}

.mar-inline-input-edit,
.mar-inline-input-copy,
.mar-inline-input-save {
  display: flex;
  flex-shrink: 0;
  width: 1.625em;
  height: 1.625em;
}

.mar-inline-input-save {
  width: 1.75em;
  height: 1.75em;
}

.mar-inline-input-edit,
.mar-inline-input-copy {
  opacity: 0;
  transition: opacity 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-inline-input:hover .mar-inline-input-edit,
.mar-inline-input:hover .mar-inline-input-copy {
  opacity: 1;
}

.mar-inline-input.invalid .mar-inline-input-label,
.mar-inline-input.invalid .mar-inline-input-icon {
  color: var(--mar-red-500);
}

.mar-inline-input-field > :deep(small),
.mar-inline-input-error {
  display: block;
  font-size: var(--mar-text-xs);
  line-height: 1.4;
  color: var(--mar-text-muted-color);
  margin-top: 0.3333em;
}

.mar-inline-input-error {
  color: var(--mar-red-500);
}

.mar-inline-input.open:not(.has-actions) {
  grid-template-columns: 1.25em var(--mar-field-label-width) minmax(0, 1fr);
}

.mar-inline-input.stacked:not(.mar-inline-input-mobile) > .mar-inline-input-label {
  grid-row: 1;
  grid-column: 2 / 4;
}

.mar-inline-input.stacked:not(.mar-inline-input-mobile) > .mar-inline-input-action {
  grid-row: 1;
  grid-column: -2;
}

.mar-inline-input.stacked:not(.mar-inline-input-mobile) > .mar-inline-input-cell {
  grid-row: 2;
  grid-column: 1 / -1;
}

.mar-inline-input.mar-inline-input-mobile {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  column-gap: 0.625em;
  row-gap: 0.375em;
}

.mar-inline-input-mobile .mar-inline-input-icon {
  align-self: center;
  margin-block-start: 0;
  flex: none;
  order: 1;
}

.mar-inline-input-mobile .mar-inline-input-label {
  flex: 1 0 auto;
  order: 2;
  max-width: 100%;
}

.mar-inline-input-mobile .mar-inline-input-cell,
.mar-inline-input-mobile .mar-inline-input-field {
  display: contents;
}

.mar-inline-input-mobile .mar-inline-input-field > :deep(*) {
  order: 3;
  flex: 0 1 auto;
  margin-inline-start: auto;
  width: auto;
  min-width: 0;
  max-width: 100%;
}

.mar-inline-input-mobile .mar-inline-input-field > :deep(.mar-field) {
  flex: 1 1 0;
}

.mar-inline-input-mobile .mar-inline-input-field :deep(:is(.mar-text-input-inline, .mar-textarea-inline, .mar-input-number-field)) {
  text-align: end;
}

.mar-inline-input-mobile .mar-inline-input-value {
  order: 3;
  flex: 0 1 auto;
  margin-inline-start: auto;
  min-width: 0;
  text-align: end;
}

.mar-inline-input-mobile .mar-inline-input-action {
  align-self: center;
  order: 4;
  flex: none;
}

.mar-inline-input-mobile .mar-inline-input-field > :deep(:is(.mar-code-block, .mar-multi-select, textarea)),
.mar-inline-input-mobile.stacked .mar-inline-input-field > :deep(*) {
  order: 5;
  flex: 1 1 100%;
  width: 100%;
}

.mar-inline-input.mar-inline-input-mobile .mar-inline-input-field > :deep(small),
.mar-inline-input.mar-inline-input-mobile .mar-inline-input-error {
  order: 6;
  flex: 1 1 100%;
  margin-top: 0;
}
</style>
