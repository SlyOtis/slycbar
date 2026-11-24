<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import type { BlockEngine } from "@/blockedit/engine/BlockEngine.ts";
import type { PageBreakMode } from "@/blockedit/model/types.ts";

const props = defineProps<{
  /** Block node whose options carry the break mode this block takes. */
  node: {
    id: string;
    options: {
      mode?: PageBreakMode;
    };
  };
  /** Block editor engine holding the document whose page rule an auto break defers to. */
  engine: BlockEngine;
  /** Editor context; a non editable editor draws the break without its control. */
  editor: { isEditable: boolean };
  /** Draws a selection outline around the block. */
  selected: boolean;
  /** Callback persisting the break mode back into the document. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
}>();

const MODES: { value: PageBreakMode; label: string }[] = [
  { value: "always", label: "Page break" },
  { value: "avoid", label: "Keep together" },
  { value: "auto", label: "Follow document" },
];

const editable = computed(() => props.editor?.isEditable ?? true);
const mode = computed<PageBreakMode>(() => props.node.options.mode ?? "always");
const documentMode = computed<PageBreakMode>(
  () => props.engine.doc.value.page.break.mode,
);
const effective = computed<PageBreakMode>(() =>
  mode.value === "auto" ? documentMode.value : mode.value,
);
const breakAfter = computed(() =>
  effective.value === "always" ? "page" : effective.value,
);
const label = computed(
  () => MODES.find((m) => m.value === mode.value)?.label ?? "Page break",
);

const onModeChange = (e: Event) => {
  props.updateAttributes({ mode: (e.target as HTMLSelectElement).value });
};
</script>

<template>
  <NodeViewWrapper
    :class="[
      'mar-be-break',
      `mar-be-break-${effective}`,
      { 'mar-be-break-selected': selected },
    ]"
    :style="{ breakAfter }"
  >
    <span class="mar-be-break-rule" />
    <span v-if="editable" class="mar-be-break-control">
      <span class="mar-be-break-label">{{ label }}</span>
      <select class="mar-be-break-select" :value="mode" @change="onModeChange">
        <option v-for="m in MODES" :key="m.value" :value="m.value">
          {{ m.label }}
        </option>
      </select>
    </span>
    <span class="mar-be-break-rule" />
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-break {
  display: flex;
  align-items: center;
  gap: 0.5em;
  margin: 1em 0;
  user-select: none;
}

.mar-be-break-rule {
  flex: 1;
  border-top: 1px dashed var(--mar-surface-300);
}

.mar-be-break-avoid .mar-be-break-rule {
  border-top-style: dotted;
}

.mar-be-break-selected {
  outline: 1px solid var(--mar-surface-400);
  border-radius: 8px;
}

.mar-be-break-control {
  position: relative;
  display: inline-flex;
  align-items: center;
  border-radius: 4px;
  padding: 0.125em 0.375em;
  background: var(--mar-surface-50);
  color: var(--mar-text-muted-color);
  font-size: 0.75em;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.mar-be-break-select {
  position: absolute;
  inset: 0;
  opacity: 0;
  cursor: pointer;
  font: inherit;
}

@media print {
  .mar-be-break-rule,
  .mar-be-break-control {
    display: none;
  }
}
</style>
