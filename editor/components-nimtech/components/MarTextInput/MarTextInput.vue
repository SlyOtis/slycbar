<script setup lang="ts">
import { computed, inject, onMounted, ref, useId } from "vue";
import { MAR_INLINE_INPUT_FIELD } from "../MarInlineInput";

const {
  modelValue = "",
  type = "text",
  placeholder,
  label,
  disabled = false,
  invalid = false,
  required = false,
  error = "",
  inline = false,
  autocomplete,
  min,
  max,
  step,
  tabindex,
  autofocus = false,
  fluid = true,
} = defineProps<{
  /** Input value; updates flow back as strings. */
  modelValue?: string | number;
  /** Native input type attribute. */
  type?: string;
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
  /** Forwarded to the native autocomplete attribute. */
  autocomplete?: string;
  /** Native min constraint for number, date, and time types. */
  min?: string | number;
  /** Native max constraint for number, date, and time types. */
  max?: string | number;
  /** Native step granularity for number, date, and time types. */
  step?: string | number;
  /** Native tabindex forwarded to the input. */
  tabindex?: string | number;
  /** Focuses the input on mount. */
  autofocus?: boolean;
  /** Makes the wrapper a full width flex column. */
  fluid?: boolean;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string];
  change: [event: Event];
  input: [event: Event];
  keydown: [event: KeyboardEvent];
  focus: [event: FocusEvent];
  blur: [event: FocusEvent];
}>();

const el = ref<HTMLInputElement | null>(null);

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
  "mar-text-input",
  { "mar-text-input-inline": isInline.value },
  { "mar-text-input-invalid": invalid || !!error },
]);

const onInput = (e: Event) => {
  const t = e.target as HTMLInputElement;
  emit("update:modelValue", t.value);
  emit("input", e);
};

onMounted(() => {
  if (autofocus) el.value?.focus();
});

defineExpose({ el });
</script>

<template>
  <div :class="rootClasses">
    <input
      ref="el"
      :aria-labelledby="labelledBy"
      :class="classes"
      :type="type"
      :value="modelValue"
      :placeholder="placeholder"
      :disabled="disabled"
      :autocomplete="autocomplete"
      :min="min"
      :max="max"
      :step="step"
      :tabindex="tabindex"
      @input="onInput"
      @change="$emit('change', $event)"
      @keydown="$emit('keydown', $event)"
      @focus="$emit('focus', $event)"
      @blur="$emit('blur', $event)"
    />
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

.mar-text-input {
  width: 100%;
  min-height: var(--mar-field-min-height);
  padding: var(--mar-field-pad-y) var(--mar-field-pad-x);
  background: color-mix(in oklab, var(--mar-surface-0), transparent 30%);
  color: var(--mar-text-color);
  border: 1px solid var(--glass-border-strong);
  border-radius: var(--mar-field-radius);
  box-shadow: inset 0 1px 1px color-mix(in oklab, var(--mar-surface-950), transparent 94%);
  font-size: var(--mar-field-font-size);
  line-height: 1.4;
  font-family: inherit;
  outline: none;
  box-sizing: border-box;
  transition:
    border-color 0.2s cubic-bezier(0.32, 0.72, 0, 1),
    box-shadow 0.2s cubic-bezier(0.32, 0.72, 0, 1),
    background-color 0.2s cubic-bezier(0.32, 0.72, 0, 1);
}

.mar-text-input:hover:not(:disabled):not(:focus) {
  background: color-mix(in oklab, var(--mar-surface-0), transparent 15%);
  border-color: color-mix(in oklab, var(--mar-surface-900), transparent 72%);
}

.mar-text-input:focus {
  background: color-mix(in oklab, var(--mar-surface-0), transparent 5%);
  border-color: color-mix(in oklab, var(--mar-primary-color), transparent 30%);
  box-shadow:
    0 0 0 0.2667em color-mix(in oklab, var(--mar-primary-color), transparent 82%),
    0 0.4em 1.3333em -0.8em color-mix(in oklab, var(--mar-primary-color), transparent 50%);
}

.mar-text-input::placeholder {
  color: var(--mar-surface-500);
}

.mar-text-input-invalid,
.mar-text-input-invalid:hover:not(:disabled):not(:focus) {
  border-color: color-mix(in oklab, var(--mar-danger-color), transparent 25%);
}

.mar-text-input-invalid:focus {
  border-color: var(--mar-danger-color);
  box-shadow: 0 0 0 0.2667em color-mix(in oklab, var(--mar-danger-color), transparent 82%);
}

.mar-text-input:disabled {
  opacity: 0.55;
  background: color-mix(in oklab, var(--mar-surface-100), transparent 50%);
  box-shadow: none;
  cursor: not-allowed;
}

.mar-text-input.mar-text-input-inline,
.mar-text-input.mar-text-input-inline:hover:not(:disabled):not(:focus),
.mar-text-input.mar-text-input-inline:focus,
.mar-text-input.mar-text-input-inline:disabled {
  min-height: 0;
  padding: 0;
  border: 0;
  border-radius: 0;
  background: transparent;
  box-shadow: none;
  font-size: var(--mar-field-font-size);
  font-weight: 400;
  line-height: 1.4;
  color: var(--mar-text-color);
}

@media (prefers-reduced-motion: reduce) {
  .mar-text-input {
    transition: none;
  }
}
</style>
