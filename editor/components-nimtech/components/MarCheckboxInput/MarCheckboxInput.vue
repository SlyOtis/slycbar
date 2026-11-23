<script setup lang="ts">
import { computed } from "vue";
import MarIcon from "../MarIcon";

const {
  modelValue = false,
  label,
  disabled = false,
  indeterminate = false,
} = defineProps<{
  /** Checked state bound with v-model. */
  modelValue?: boolean;
  /** Text rendered beside the box that also toggles on click. */
  label?: string;
  /** Disables the input and dims the control. */
  disabled?: boolean;
  /** Renders a minus glyph and a filled box as a mixed state. */
  indeterminate?: boolean;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: boolean];
}>();

const classes = computed(() => [
  "mar-checkbox",
  { "mar-checkbox-checked": modelValue },
  { "mar-checkbox-disabled": disabled },
  { "mar-checkbox-indeterminate": indeterminate },
]);

const toggle = () => {
  if (disabled) return;
  emit("update:modelValue", !modelValue);
};
</script>

<template>
  <label :class="classes">
    <input
      type="checkbox"
      class="mar-checkbox-input"
      :checked="modelValue"
      :disabled="disabled"
      @change="toggle"
    />
    <span class="mar-checkbox-box">
      <MarIcon v-if="indeterminate" icon="minus" class="mar-checkbox-icon" />
      <MarIcon v-else-if="modelValue" icon="check" class="mar-checkbox-icon" />
    </span>
    <span v-if="label" class="mar-checkbox-label">{{ label }}</span>
  </label>
</template>

<style scoped>
.mar-checkbox {
  display: inline-flex;
  align-items: center;
  gap: 0.4615em;
  cursor: pointer;
  user-select: none;
  font-size: var(--mar-text-sm);
  color: var(--mar-text-color);
}

.mar-checkbox-disabled {
  cursor: not-allowed;
  opacity: 0.5;
}

.mar-checkbox-input {
  position: absolute;
  opacity: 0;
  pointer-events: none;
  width: 0;
  height: 0;
}

.mar-checkbox-box {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 1.0769em;
  height: 1.0769em;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 3px;
  background: var(--mar-surface-0);
  transition: background 0.15s cubic-bezier(0.4, 0, 0.2, 1),
    border-color 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-checkbox:hover:not(.mar-checkbox-disabled) .mar-checkbox-box {
  border-color: var(--mar-primary-color);
}

.mar-checkbox-checked .mar-checkbox-box,
.mar-checkbox-indeterminate .mar-checkbox-box {
  background: var(--mar-primary-color);
  border-color: var(--mar-primary-color);
}

.mar-checkbox-icon {
  color: var(--mar-primary-contrast-color);
  font-size: var(--mar-text-base);
  font-weight: 700;
}

.mar-checkbox-input:focus-visible + .mar-checkbox-box {
  outline: 0.1538em solid var(--mar-primary-color);
  outline-offset: 0.1538em;
}

.mar-checkbox-label {
  line-height: 1.3;
}
</style>
