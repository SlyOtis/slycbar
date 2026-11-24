<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper, NodeViewContent } from "@/blockedit/render/views/nodeViewBridge.ts";
import { contentShapeOf } from "@/blockedit/model/schema.ts";
import type { BlockEngine } from "@/blockedit/engine/BlockEngine.ts";

const props = defineProps<{
  /** Block node whose id resolves the block in the document and whose options carry the field the block names. */
  node: {
    id: string;
    options: {
      field?: string;
    };
  };
  /** Block editor engine holding the document the block's content shape is read from. */
  engine: BlockEngine;
  /** Editor context; a non editable editor renders the reference as fixed text. */
  editor: { isEditable: boolean; authoring?: boolean };
  /** Draws a selection outline around the block. */
  selected: boolean;
  /** Callback persisting the field name back into the document. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
}>();

const editable = computed(() => props.editor?.isEditable ?? true);
const field = computed(() => props.node.options.field ?? "");
const block = computed(() => props.engine.doc.value.blocks[props.node.id]);
const repeats = computed(
  () => block.value !== undefined && contentShapeOf(block.value) === "slot",
);

const onFieldInput = (e: Event) => {
  props.updateAttributes({ field: (e.target as HTMLInputElement).value });
};
</script>

<template>
  <NodeViewWrapper
    :class="[
      'mar-be-template',
      repeats ? 'mar-be-template-repeat' : 'mar-be-template-leaf',
      { 'mar-be-template-selected': selected },
    ]"
  >
    <span class="mar-be-template-ref" contenteditable="false">
      <span class="mar-be-template-open">{{ repeats ? "{range ." : "{." }}</span>
      <span v-if="editable" class="mar-be-template-field">
        <span class="mar-be-template-field-ghost">{{ field || "field" }}</span>
        <input
          class="mar-be-template-field-input"
          :value="field"
          placeholder="field"
          @input="onFieldInput"
        />
      </span>
      <span v-else class="mar-be-template-field-text">{{ field }}</span>
      <span class="mar-be-template-close">}</span>
    </span>
    <NodeViewContent v-if="repeats" class="mar-be-template-body" />
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-template {
  margin: 0.25em 0;
  font-size: 1em;
}

.mar-be-template-repeat {
  margin: 0.75em 0;
  padding: 0.5em;
  border: 1px dashed var(--mar-surface-300);
  border-radius: 8px;
  background: var(--mar-surface-50);
}

.mar-be-template-selected {
  outline: 1px solid var(--mar-surface-400);
  border-radius: 8px;
}

.mar-be-template-ref {
  display: inline-flex;
  align-items: baseline;
  font-family: "JetBrains Mono", ui-monospace, monospace;
  font-size: 0.875em;
  color: var(--mar-primary-700);
  background: var(--mar-primary-50);
  border-radius: 4px;
  padding: 0.125em 0.375em;
  user-select: none;
}

.mar-be-template-open,
.mar-be-template-close {
  color: var(--mar-text-muted-color);
}

.mar-be-template-field {
  display: inline-grid;
  max-inline-size: 100%;
}

.mar-be-template-field-ghost,
.mar-be-template-field-input {
  grid-area: 1 / 1;
  font: inherit;
  letter-spacing: inherit;
  padding: 0;
  min-inline-size: 3ch;
}

.mar-be-template-field-ghost {
  visibility: hidden;
  white-space: pre;
}

.mar-be-template-field-input {
  inline-size: 100%;
  border: none;
  background: transparent;
  outline: none;
  color: inherit;
}

.mar-be-template-field-input::placeholder {
  color: var(--mar-text-muted-color);
}

.mar-be-template-field-text {
  white-space: pre;
}

.mar-be-template-body {
  margin-top: 0.5em;
}

.mar-be-template-body :deep(p) {
  margin: 0.25em 0;
}
</style>
