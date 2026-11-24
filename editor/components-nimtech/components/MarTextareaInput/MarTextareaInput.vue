<script setup lang="ts">
import { computed, inject, nextTick, onMounted, ref, useId, watch } from "vue";
import { MAR_INLINE_INPUT_FIELD } from "../MarInlineInput";

const {
  modelValue = "",
  rows = 5,
  autoResize = true,
  placeholder,
  label,
  disabled = false,
  invalid = false,
  required = false,
  error = "",
  inline = false,
  autofocus = false,
  fluid = true,
} = defineProps<{
  /** Textarea content. */
  modelValue?: string;
  /** Native rows attribute acting as the starting height; the inline style starts at one row. */
  rows?: number;
  /** Grows the element to fit its content on every change and disables manual resizing. */
  autoResize?: boolean;
  /** Native placeholder text, a hint about the value and never a stand in for the label. */
  placeholder?: string;
  /** Label rendered above the field in the form style; ignored in the inline style, where the row is the label. */
  label?: string;
  /** Dims the field and blocks input. */
  disabled?: boolean;
  /** Paints the border red. */
  invalid?: boolean;
  /** Appends a red asterisk to the label. */
  required?: boolean;
  /** Error text under the field, painting the border red. */
  error?: string;
  /** Inline style: the field renders exactly like the read value it replaces, with no box, border, padding or height change. Always on inside a MarInlineInput row. */
  inline?: boolean;
  /** Focuses the textarea on mount. */
  autofocus?: boolean;
  /** Makes the wrapper a full width flex column. */
  fluid?: boolean;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string];
  keydown: [event: KeyboardEvent];
  focus: [event: FocusEvent];
  blur: [event: FocusEvent];
}>();

const el = ref<HTMLTextAreaElement | null>(null);

const labelId = useId();
const field = inject(MAR_INLINE_INPUT_FIELD, null);

const isInline = computed(() => inline || !!field);

const labeled = computed(() => !isInline.value && !!label);

const labelledBy = computed(() => (labeled.value ? labelId : field?.labelId));

const rootClasses = computed(() => [
  "mar-field",
  { "mar-field-fluid": fluid },
  { "mar-ifta-label": labeled.value },
]);

const classes = computed(() => [
  "mar-textarea",
  autoResize ? "mar-textarea-auto-resize" : "mar-textarea-fixed",
  { "mar-textarea-inline": isInline.value },
  { "mar-textarea-invalid": invalid || !!error },
]);

const resize = () => {
  if (!autoResize || !el.value) return;
  el.value.style.height = "auto";
  el.value.style.height = el.value.scrollHeight + "px";
};

const onInput = (e: Event) => {
  const t = e.target as HTMLTextAreaElement;
  emit("update:modelValue", t.value);
};

watch(
  () => modelValue,
  () => nextTick(resize),
);

onMounted(() => {
  nextTick(resize);
  if (autofocus) el.value?.focus();
});

defineExpose({ el });
</script>

<template>
  <div :class="rootClasses">
    <textarea
      ref="el"
      :aria-labelledby="labelledBy"
      :class="classes"
      :rows="isInline ? 1 : rows"
      :value="modelValue"
      :placeholder="placeholder"
      :disabled="disabled"
      @input="onInput"
      @keydown="$emit('keydown', $event)"
      @focus="$emit('focus', $event)"
      @blur="$emit('blur', $event)"
    ></textarea>
    <label v-if="labeled" :id="labelId" class="mar-ifta-label-text">
      {{ label }}
      <span v-if="required" class="mar-ifta-label-required">*</span>
    </label>
    <small v-if="!isInline && error" class="mar-ifta-label-error-text">{{ error }}</small>
  </div>
</template>

<style scoped>
.mar-field {
  display: inline-flex;
  flex-direction: column;
  gap: 0.375em;
}

.mar-field-fluid {
  display: flex;
  width: 100%;
}

.mar-field:not(.mar-field-fluid) {
  width: auto;
}

.mar-textarea {
  width: 100%;
  padding: var(--mar-field-pad-y) var(--mar-field-pad-x);
  background: color-mix(in oklab, var(--mar-surface-0), transparent 30%);
  color: var(--mar-text-color);
  border: 1px solid var(--glass-border-strong);
  border-radius: var(--mar-field-radius);
  box-shadow: inset 0 1px 1px color-mix(in oklab, var(--mar-surface-950), transparent 94%);
  font-family: inherit;
  font-size: var(--mar-field-font-size);
  line-height: 1.5;
  outline: none;
  box-sizing: border-box;
  overflow: hidden;
  scrollbar-width: none;
  transition:
    border-color 0.2s cubic-bezier(0.32, 0.72, 0, 1),
    box-shadow 0.2s cubic-bezier(0.32, 0.72, 0, 1),
    background-color 0.2s cubic-bezier(0.32, 0.72, 0, 1);
}

.mar-textarea::-webkit-scrollbar {
  display: none;
}

.mar-textarea-auto-resize {
  resize: none;
  min-height: 5.1em;
}

.mar-textarea-fixed {
  resize: vertical;
}

.mar-textarea:hover:not(:disabled):not(:focus) {
  background: color-mix(in oklab, var(--mar-surface-0), transparent 15%);
  border-color: color-mix(in oklab, var(--mar-surface-900), transparent 72%);
}

.mar-textarea:focus {
  background: color-mix(in oklab, var(--mar-surface-0), transparent 5%);
  border-color: color-mix(in oklab, var(--mar-primary-color), transparent 30%);
  box-shadow:
    0 0 0 0.2667em color-mix(in oklab, var(--mar-primary-color), transparent 82%),
    0 0.4em 1.3333em -0.8em color-mix(in oklab, var(--mar-primary-color), transparent 50%);
}

.mar-textarea::placeholder {
  color: var(--mar-surface-500);
}

.mar-textarea-invalid,
.mar-textarea-invalid:hover:not(:disabled):not(:focus) {
  border-color: color-mix(in oklab, var(--mar-danger-color), transparent 25%);
}

.mar-textarea-invalid:focus {
  border-color: var(--mar-danger-color);
  box-shadow: 0 0 0 0.2667em color-mix(in oklab, var(--mar-danger-color), transparent 82%);
}

.mar-textarea:disabled {
  opacity: 0.55;
  background: color-mix(in oklab, var(--mar-surface-100), transparent 50%);
  box-shadow: none;
  cursor: not-allowed;
}

.mar-textarea.mar-textarea-inline,
.mar-textarea.mar-textarea-inline:hover:not(:disabled):not(:focus),
.mar-textarea.mar-textarea-inline:focus,
.mar-textarea.mar-textarea-inline:disabled {
  min-height: 0;
  padding: 0;
  border: 0;
  border-radius: 0;
  background: transparent;
  box-shadow: none;
  resize: none;
  font-size: var(--mar-field-font-size);
  font-weight: 400;
  line-height: 1.4;
  color: var(--mar-text-color);
}

@media (prefers-reduced-motion: reduce) {
  .mar-textarea {
    transition: none;
  }
}
</style>
