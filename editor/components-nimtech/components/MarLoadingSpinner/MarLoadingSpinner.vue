<script setup lang="ts">
import { computed } from "vue";

const {
  label = "loading",
  mode = "overlay",
} = defineProps<{
  /** Text next to the ring, an empty string hides the label element. */
  label?: string;
  /** Overlay blankets the positioned parent, inline is a compact row, page covers the viewport with the logo slot above the ring, and assemble blankets the parent in blurred glass with a small grid of cells breathing into place, for a first paint that should hold its layout. */
  mode?: "overlay" | "inline" | "page" | "assemble";
}>();

const classes = computed(() => [
  "mar-loading-spinner",
  `mar-loading-spinner-${mode}`,
]);
</script>

<template>
  <div :class="classes" role="status" aria-live="polite">
    <slot v-if="mode === 'page'" name="logo" />
    <div v-if="mode === 'assemble'" class="mar-loading-spinner-cells" :aria-label="label">
      <span v-for="cell in 4" :key="cell" class="mar-loading-spinner-cell" aria-hidden="true"></span>
    </div>
    <div v-else class="mar-loading-spinner-core">
      <span class="mar-loading-spinner-ring" aria-hidden="true"></span>
      <span v-if="label" class="mar-loading-spinner-label">{{ label }}</span>
    </div>
  </div>
</template>

<style scoped>
.mar-loading-spinner {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--mar-surface-700);
}

.mar-loading-spinner-core {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.4375em;
}

.mar-loading-spinner-overlay {
  position: absolute;
  inset: 0;
  z-index: 50;
  background: color-mix(in srgb, var(--mar-surface-0), transparent 30%);
  -webkit-backdrop-filter: blur(0.375em);
  backdrop-filter: blur(0.375em);
  pointer-events: auto;
}

.mar-loading-spinner-overlay .mar-loading-spinner-core {
  flex-direction: column;
}

.mar-loading-spinner-assemble {
  position: absolute;
  inset: 0;
  z-index: 50;
  background: color-mix(in oklab, var(--glass-surface), transparent 20%);
  -webkit-backdrop-filter: blur(var(--glass-blur-strong)) saturate(var(--glass-saturate));
  backdrop-filter: blur(var(--glass-blur-strong)) saturate(var(--glass-saturate));
  pointer-events: auto;
  transition: opacity 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-loading-spinner-cells {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  grid-template-rows: 1fr 1fr;
  gap: 0.25em;
  inline-size: 3.5em;
  block-size: 2.25em;
}

.mar-loading-spinner-cell {
  border-radius: 0.25em;
  background: var(--mar-primary-color);
  opacity: 0.18;
  transform: scale(0.6);
  animation: mar-loading-spinner-assemble 1.6s cubic-bezier(0.4, 0, 0.2, 1) infinite;
}

.mar-loading-spinner-cell:nth-child(1) {
  grid-column: 1 / span 2;
}

.mar-loading-spinner-cell:nth-child(2) {
  background: var(--mar-info-color);
  animation-delay: 0.15s;
}

.mar-loading-spinner-cell:nth-child(3) {
  background: var(--mar-success-color);
  animation-delay: 0.3s;
}

.mar-loading-spinner-cell:nth-child(4) {
  grid-column: 2 / span 2;
  animation-delay: 0.45s;
}

@keyframes mar-loading-spinner-assemble {
  0%,
  100% {
    opacity: 0.18;
    transform: scale(0.6);
  }

  50% {
    opacity: 0.85;
    transform: scale(1);
  }
}

@media (prefers-reduced-motion: reduce) {
  .mar-loading-spinner-cell {
    animation: none;
    opacity: 0.5;
    transform: none;
  }
}

.mar-loading-spinner-inline {
  padding: 0.375em;
}

.mar-loading-spinner-page {
  position: fixed;
  inset: 0;
  z-index: 10;
  flex-direction: column;
  gap: 0.75em;
  background: var(--mar-surface-100);
}

.mar-loading-spinner-ring {
  width: 1.125em;
  height: 1.125em;
  border-radius: 50%;
  border: 0.125em solid color-mix(in srgb, var(--mar-primary-color), transparent 80%);
  border-top-color: var(--mar-primary-color);
  animation: mar-loading-spinner-spin 0.9s linear infinite;
  box-sizing: border-box;
}

@keyframes mar-loading-spinner-spin {
  to {
    transform: rotate(360deg);
  }
}

.mar-loading-spinner-label {
  font-family: "JetBrains Mono", ui-monospace, monospace;
  font-size: 0.5625em;
  text-transform: uppercase;
  letter-spacing: 0.15em;
}
</style>
