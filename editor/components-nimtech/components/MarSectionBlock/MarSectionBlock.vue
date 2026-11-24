<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper, NodeViewContent } from "@/blockedit/render/views/nodeViewBridge.ts";

const props = defineProps<{
  /** Block node whose options carry the heading, the field key, the edit mode, and the read mode. */
  node: {
    options: {
      heading?: string;
      key?: string;
    };
    edit?: string;
    read?: string;
    textContent?: string;
  };
  /** Editor context; author mode lets the heading be renamed, a non editable editor puts the block in read mode. */
  editor: { isEditable: boolean; authoring?: boolean };
  /** Draws a selection outline around the block. */
  selected: boolean;
  /** Callback persisting heading edits back into the document. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
}>();

const editable = computed(() => props.editor?.isEditable ?? true);
const authoring = computed(() => props.editor?.authoring === true);
const blockLocked = computed(() => {
  const mode = props.node.edit ?? "open";
  return mode === "lockBlock" || mode === "locked";
});
const headingEditable = computed(() => editable.value && (authoring.value || !blockLocked.value));
const heading = computed(() => props.node.options.heading ?? "");

const onHeadingInput = (e: Event) => {
  props.updateAttributes({ heading: (e.target as HTMLInputElement).value });
};
</script>

<template>
  <NodeViewWrapper
    :class="['mar-be-section', { 'mar-be-section-locked': blockLocked, 'mar-be-section-selected': selected }]"
  >
    <div class="mar-be-section-head" contenteditable="false">
      <input
        v-if="headingEditable"
        class="mar-be-section-heading-input"
        :value="heading"
        placeholder="Section"
        @input="onHeadingInput"
      />
      <span v-else class="mar-be-section-heading">{{ heading }}</span>
    </div>
    <NodeViewContent class="mar-be-section-body" />
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-section {
  margin: 0.75em 0;
}

.mar-be-section-selected {
  outline: 1px solid var(--mar-surface-400);
  border-radius: 8px;
}

.mar-be-section-head {
  display: flex;
  align-items: center;
  margin-bottom: 0.25em;
  padding-bottom: 0.25em;
  border-bottom: 1px solid var(--mar-surface-200);
}

.mar-be-section-heading,
.mar-be-section-heading-input {
  flex: 1;
  min-width: 0;
  font-family: inherit;
  font-size: 1.125em;
  font-weight: 700;
  color: var(--mar-text-color);
  padding: 0.1111em 0;
}

.mar-be-section-heading-input {
  border: none;
  background: transparent;
  outline: none;
}

.mar-be-section-locked .mar-be-section-heading {
  user-select: none;
}

.mar-be-section-body {
  padding-left: 0.125em;
}

.mar-be-section-body :deep(p) {
  margin: 0.25em 0;
}
</style>
