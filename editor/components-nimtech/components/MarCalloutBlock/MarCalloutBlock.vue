<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper, NodeViewContent } from "@/blockedit/render/views/nodeViewBridge.ts";
import MarIcon from "../MarIcon";
import type { IconType } from "@/types/icon.types";

const props = defineProps<{
  /** Editor node whose options carry the variant and icon. */
  node: {
    options: {
      variant?: "info" | "neutral" | "warn" | "danger" | "success";
      icon?: IconType;
    };
    textContent?: string;
  };
  /** Draws an outline when the block is selected. */
  selected: boolean;
}>();

const variant = computed(() => props.node.options.variant ?? "info");

const icon = computed<IconType>(() => props.node.options.icon ?? "info");
</script>

<template>
  <NodeViewWrapper
    :class="[
      'mar-callout',
      `mar-callout-${variant}`,
      { 'mar-callout-selected': selected },
    ]"
  >
    <div class="mar-callout-icon" contenteditable="false">
      <MarIcon :icon="icon" />
    </div>
    <NodeViewContent class="mar-callout-content" />
  </NodeViewWrapper>
</template>

<style scoped>
.mar-callout {
  display: flex;
  gap: 0.625em;
  padding: 0.625em 0.75em;
  margin: 0.375em 0;
  border-radius: 8px;
  background: var(--mar-surface-100);
}

.mar-callout-selected {
  outline: 1px solid var(--mar-surface-400);
}

.mar-callout-icon {
  flex-shrink: 0;
  display: flex;
  align-items: flex-start;
  line-height: 1.5;
  color: var(--mar-surface-600);
}

.mar-callout-icon .mar-icon {
  font-size: 1.1429em;
}

.mar-callout-content {
  flex: 1;
  min-width: 0;
}

.mar-callout-content :deep(p) {
  margin: 0;
}

.mar-callout-info {
  background: color-mix(in srgb, var(--mar-primary-color), transparent 90%);
}

.mar-callout-info .mar-callout-icon {
  color: var(--mar-primary-color);
}

.mar-callout-success {
  background: color-mix(in srgb, var(--mar-green-500), transparent 88%);
}

.mar-callout-success .mar-callout-icon {
  color: var(--mar-green-600);
}

.mar-callout-warn {
  background: color-mix(in srgb, var(--mar-yellow-500), transparent 85%);
}

.mar-callout-warn .mar-callout-icon {
  color: var(--mar-yellow-600);
}

.mar-callout-danger {
  background: color-mix(in srgb, var(--mar-red-500), transparent 90%);
}

.mar-callout-danger .mar-callout-icon {
  color: var(--mar-red-600);
}

.mar-callout-neutral {
  background: var(--mar-surface-100);
}

.mar-callout-neutral .mar-callout-icon {
  color: var(--mar-surface-600);
}
</style>
