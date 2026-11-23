<script setup lang="ts">
const {
  modelValue,
  label = "",
  disabled = false,
} = defineProps<{
  /** Switch state driving the knob position and track color. */
  modelValue: boolean;
  /** Text rendered after the track; clicking it toggles too. */
  label?: string;
  /** Dims the control and blocks toggling. */
  disabled?: boolean;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: boolean];
}>();

const onClick = () => !disabled && emit("update:modelValue", !modelValue);
</script>

<template>
  <label
    class="mar-switch"
    :class="{ 'mar-switch-on': modelValue, 'mar-switch-disabled': disabled }"
    role="switch"
    :aria-checked="modelValue"
    @click="onClick"
  >
    <span class="mar-switch-track">
      <span class="mar-switch-knob" />
    </span>
    <span v-if="label" class="mar-switch-label">{{ label }}</span>
  </label>
</template>

<style scoped>
.mar-switch {
  display: inline-flex;
  align-items: center;
  gap: 0.375em;
  max-inline-size: 100%;
  cursor: pointer;
  user-select: none;
  font-size: var(--mar-text-base);
  font-weight: 500;
  color: var(--mar-text-color);
}

.mar-switch-disabled {
  cursor: not-allowed;
  opacity: 0.5;
}

.mar-switch-track {
  position: relative;
  inline-size: 1.625em;
  block-size: 0.9375em;
  background: var(--mar-surface-300);
  border-radius: 9999px;
  transition: background 0.15s cubic-bezier(0.4, 0, 0.2, 1);
  flex: none;
}

.mar-switch-on .mar-switch-track {
  background: var(--mar-primary-color);
}

.mar-switch-knob {
  position: absolute;
  top: 0.0625em;
  left: 0.0625em;
  inline-size: 0.8125em;
  block-size: 0.8125em;
  background: white;
  border-radius: 9999px;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.2);
  transition: transform 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-switch-on .mar-switch-knob {
  transform: translateX(0.6875em);
}

.mar-switch-label {
  font-size: var(--mar-text-xs);
  color: inherit;
}
</style>
