<script setup lang="ts">
import { computed, inject, useId } from "vue";
import MarIcon from "../MarIcon";
import { MAR_INLINE_INPUT_FIELD } from "../MarInlineInput";

const {
  modelValue = null,
  min,
  max,
  step = 1,
  label = "",
  placeholder,
  disabled = false,
  invalid = false,
  required = false,
  error = "",
  showButtons = false,
  suffix,
  prefix,
  inline = false,
} = defineProps<{
  /** Current numeric value, null renders an empty field. */
  modelValue?: number | null;
  /** Lower clamp for typed values and stepping, forwarded to the native min attribute. */
  min?: number;
  /** Upper clamp for typed values and stepping, forwarded to the native max attribute. */
  max?: number;
  /** Increment used by the stepper buttons and the native step attribute. */
  step?: number;
  /** Label rendered above the field in the form style; ignored in the inline style, where the row is the label. */
  label?: string;
  /** Native placeholder text, a hint about the value and never a stand in for the label. */
  placeholder?: string;
  /** Disables the field and the stepper buttons. */
  disabled?: boolean;
  /** Paints the border red. */
  invalid?: boolean;
  /** Appends a red asterisk to the label. */
  required?: boolean;
  /** Error text under the field, painting the border red. */
  error?: string;
  /** Renders the chevron stepper column on the right. */
  showButtons?: boolean;
  /** Static text after the field for units. */
  suffix?: string;
  /** Static text before the field for currency marks and similar. */
  prefix?: string;
  /** Inline style: the number renders exactly like the read value it replaces, with no box, border, padding or height change, and the steppers sit inside that footprint. Always on inside a MarInlineInput row. */
  inline?: boolean;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: number | null];
}>();


const field = inject(MAR_INLINE_INPUT_FIELD, null);

const isInline = computed(() => inline || !!field);

const labeled = computed(() => !isInline.value && !!label);

const classes = computed(() => [
  "mar-input-number",
  { "mar-input-number-invalid": invalid || !!error },
  { "mar-input-number-with-buttons": showButtons },
  { "mar-input-number-inline": isInline.value },
]);

const clamp = (n: number): number => {
  let v = n;
  if (typeof min === "number" && v < min) v = min;
  if (typeof max === "number" && v > max) v = max;
  return v;
};

const onInput = (e: Event) => {
  const v = (e.target as HTMLInputElement).value;
  if (v === "") {
    emit("update:modelValue", null);
    return;
  }
  const n = Number(v);
  if (Number.isNaN(n)) return;
  emit("update:modelValue", clamp(n));
};

const inc = () => {
  if (disabled) return;
  const current = modelValue ?? 0;
  emit("update:modelValue", clamp(current + step));
};

const dec = () => {
  if (disabled) return;
  const current = modelValue ?? 0;
  emit("update:modelValue", clamp(current - step));
};

const labelId = useId();
const labelledBy = computed(() => (labeled.value ? labelId : field?.labelId));
</script>

<template>
  <div v-if="labeled" class="mar-ifta-label">
    <div :class="classes">
      <span v-if="prefix" class="mar-input-number-prefix">{{ prefix }}</span>
      <input
        class="mar-input-number-field"
        :aria-labelledby="labelledBy"
        type="number"
        inputmode="numeric"
        :value="modelValue ?? ''"
        :min="min"
        :max="max"
        :step="step"
        :placeholder="placeholder"
        :disabled="disabled"
        @input="onInput"
      />
      <span v-if="suffix" class="mar-input-number-suffix">{{ suffix }}</span>
      <div v-if="showButtons" class="mar-input-number-buttons">
        <button
          type="button"
          class="mar-input-number-btn"
          :disabled="disabled"
          aria-label="increment"
          @click="inc"
        >
          <MarIcon icon="chevron-up" />
        </button>
        <button
          type="button"
          class="mar-input-number-btn"
          :disabled="disabled"
          aria-label="decrement"
          @click="dec"
        >
          <MarIcon icon="chevron-down" />
        </button>
      </div>
    </div>
    <label :id="labelId" class="mar-ifta-label-text">
      {{ label }}
      <span v-if="required" class="mar-ifta-label-required">*</span>
    </label>
    <small v-if="error" class="mar-ifta-label-error-text">{{ error }}</small>
  </div>
  <div v-else :class="classes">
    <span v-if="prefix" class="mar-input-number-prefix">{{ prefix }}</span>
    <input
      class="mar-input-number-field"
      :aria-labelledby="labelledBy"
      type="number"
      inputmode="numeric"
      :value="modelValue ?? ''"
      :min="min"
      :max="max"
      :step="step"
      :placeholder="placeholder"
      :disabled="disabled"
      @input="onInput"
    />
    <span v-if="suffix" class="mar-input-number-suffix">{{ suffix }}</span>
    <div v-if="showButtons" class="mar-input-number-buttons">
      <button
        type="button"
        class="mar-input-number-btn"
        :disabled="disabled"
        aria-label="increment"
        @click="inc"
      >
        <MarIcon icon="chevron-up" />
      </button>
      <button
        type="button"
        class="mar-input-number-btn"
        :disabled="disabled"
        aria-label="decrement"
        @click="dec"
      >
        <MarIcon icon="chevron-down" />
      </button>
    </div>
  </div>
</template>

<style scoped>
.mar-input-number {
  display: inline-flex;
  align-items: stretch;
  width: 100%;
  min-height: var(--mar-field-min-height);
  background: color-mix(in oklab, var(--mar-surface-0), transparent 30%);
  border: 1px solid var(--glass-border-strong);
  border-radius: calc(var(--mar-field-radius) * 0.9375);
  box-shadow: inset 0 1px 1px color-mix(in oklab, var(--mar-surface-950), transparent 94%);
  transition:
    border-color 0.2s cubic-bezier(0.32, 0.72, 0, 1),
    box-shadow 0.2s cubic-bezier(0.32, 0.72, 0, 1),
    background-color 0.2s cubic-bezier(0.32, 0.72, 0, 1);
  overflow: hidden;
}

.mar-input-number:hover:not(:focus-within) {
  background: color-mix(in oklab, var(--mar-surface-0), transparent 15%);
  border-color: color-mix(in oklab, var(--mar-surface-900), transparent 72%);
}

.mar-input-number:focus-within {
  background: color-mix(in oklab, var(--mar-surface-0), transparent 5%);
  border-color: color-mix(in oklab, var(--mar-primary-color), transparent 30%);
  box-shadow:
    0 0 0 0.25em color-mix(in oklab, var(--mar-primary-color), transparent 82%),
    0 0.375em 1.25em -0.75em color-mix(in oklab, var(--mar-primary-color), transparent 50%);
}

.mar-input-number-invalid,
.mar-input-number-invalid:hover:not(:focus-within) {
  border-color: color-mix(in oklab, var(--mar-danger-color), transparent 25%);
}

.mar-input-number-invalid:focus-within {
  border-color: var(--mar-danger-color);
  box-shadow: 0 0 0 0.25em color-mix(in oklab, var(--mar-danger-color), transparent 82%);
}

.mar-input-number-prefix,
.mar-input-number-suffix {
  display: flex;
  align-items: center;
  padding: 0 0.6154em;
  color: var(--mar-surface-500);
  font-size: var(--mar-text-sm);
}

.mar-input-number-field {
  flex: 1;
  min-width: 0;
  padding: var(--mar-field-pad-y) var(--mar-field-pad-x);
  background: transparent;
  border: none;
  outline: none;
  color: var(--mar-text-color);
  font-size: var(--mar-field-font-size);
  line-height: 1.4;
  font-family: inherit;
}

.mar-input-number-field::-webkit-outer-spin-button,
.mar-input-number-field::-webkit-inner-spin-button {
  appearance: none;
  margin: 0;
}

.mar-input-number-field {
  appearance: textfield;
}

.mar-input-number-buttons {
  display: flex;
  flex-direction: column;
  border-inline-start: 1px solid var(--glass-border-strong);
}

.mar-input-number-btn {
  flex: 1;
  width: 2.8em;
  background: color-mix(in oklab, var(--mar-surface-50), transparent 40%);
  border: none;
  color: var(--mar-surface-600);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: var(--mar-text-3xs);
  transition:
    background-color 0.2s ease,
    color 0.2s ease;
}

.mar-input-number-btn .mar-icon {
  font-size: var(--mar-text-base);
}

.mar-input-number-btn:hover:not(:disabled) {
  background: var(--mar-surface-200);
  color: var(--mar-surface-800);
}

.mar-input-number-btn + .mar-input-number-btn {
  border-top: 1px solid var(--glass-border-strong);
}

.mar-input-number-field:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.mar-input-number.mar-input-number-inline,
.mar-input-number.mar-input-number-inline:hover:not(:focus-within),
.mar-input-number.mar-input-number-inline:focus-within {
  width: auto;
  min-height: 0;
  background: none;
  border: 0;
  border-radius: 0;
  box-shadow: none;
  overflow: visible;
  align-items: center;
}

.mar-input-number-inline .mar-input-number-field {
  field-sizing: content;
  min-inline-size: 1ch;
  flex: none;
  padding: 0;
  font-size: var(--mar-field-font-size);
  font-weight: 400;
  line-height: 1.4;
}

.mar-input-number-inline .mar-input-number-prefix,
.mar-input-number-inline .mar-input-number-suffix {
  padding: 0 0.25em;
  font-size: var(--mar-field-font-size);
  line-height: 1.4;
}

.mar-input-number-inline .mar-input-number-buttons {
  align-self: center;
  border: 0;
  margin-inline-start: 0.25em;
}

.mar-input-number-inline .mar-input-number-btn,
.mar-input-number-inline .mar-input-number-btn + .mar-input-number-btn {
  width: 1em;
  height: 0.7em;
  border: 0;
  background: transparent;
}

.mar-input-number-inline .mar-input-number-btn .mar-icon {
  font-size: var(--mar-text-3xs);
}

@supports not (field-sizing: content) {
  .mar-input-number-inline .mar-input-number-field {
    inline-size: 2.25em;
  }
}

@media (prefers-reduced-motion: reduce) {
  .mar-input-number,
  .mar-input-number-btn {
    transition: none;
  }
}
</style>
