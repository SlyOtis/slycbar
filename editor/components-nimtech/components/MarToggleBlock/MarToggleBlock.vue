<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper, NodeViewContent } from "@/blockedit/render/views/nodeViewBridge.ts";
import MarIcon from "../MarIcon";
import { useCollapse } from "@/composables/useCollapse";

const props = defineProps<{
  /** Block node whose options carry the open state, background flag, and summary text. */
  node: {
    options: {
      open?: boolean;
      background?: boolean;
      summary?: string;
    };
    textContent?: string;
  };
  /** Editor context; a non editable editor puts the block in read mode. */
  editor: { isEditable: boolean };
  /** Draws a selection outline around the block. */
  selected: boolean;
  /** Callback persisting open toggles and summary edits back into the document. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
}>();

const editable = computed(() => props.editor?.isEditable ?? true);

const open = computed(() => !!props.node.options.open);
const background = computed(() => props.node.options.background !== false);
const summary = computed(() => props.node.options.summary ?? "");

const body = useCollapse(() => open.value || !editable.value);

const toggleOpen = () => props.updateAttributes({ open: !open.value });

const onSummaryInput = (e: Event) => {
  props.updateAttributes({
    summary: (e.target as HTMLInputElement).value,
  });
};
</script>

<template>
  <NodeViewWrapper
    :class="['mar-be-toggle', { 'mar-be-toggle-open': open || !editable, 'mar-be-toggle-selected': selected, 'mar-be-toggle-bg': background }]"
  >
    <div class="mar-be-toggle-head" contenteditable="false">
      <button
        v-if="editable"
        type="button"
        class="mar-be-toggle-chevron"
        @click="toggleOpen"
      >
        <MarIcon icon="chevron-right" class="mar-be-toggle-chevron-icon" />
      </button>
      <input
        v-if="editable"
        class="mar-be-toggle-summary"
        :value="summary"
        placeholder="Toggle"
        @input="onSummaryInput"
      />
      <span v-else class="mar-be-toggle-summary-text">{{ summary }}</span>
    </div>
    <div
      :ref="body.body"
      class="mar-be-toggle-body"
      :style="body.style.value"
      @transitionend="body.onTransitionEnd"
    >
      <div class="mar-be-toggle-inner">
        <NodeViewContent />
      </div>
    </div>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-toggle {
  margin: 0.25em 0;
  border-radius: 8px;
}

.mar-be-toggle-bg {
  background: color-mix(in srgb, var(--mar-surface-200) 45%, transparent);
  padding: 0.375em 0.625em;
}

.mar-be-toggle-selected {
  outline: 1px solid var(--mar-surface-400);
}

.mar-be-toggle-head {
  display: flex;
  align-items: center;
  gap: 0.375em;
}

.mar-be-toggle-chevron {
  width: 1.5em;
  height: 1.5em;
  font-size: 0.8333em;
  flex-shrink: 0;
  border: none;
  background: transparent;
  color: var(--mar-surface-500);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
  transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1),
    background 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-be-toggle-chevron-icon {
  font-size: 1.2em;
}

.mar-be-toggle-chevron:hover {
  background: var(--mar-surface-100);
}

.mar-be-toggle-open .mar-be-toggle-chevron {
  transform: rotate(90deg);
}

.mar-be-toggle-summary {
  flex: 1;
  min-width: 0;
  border: none;
  background: transparent;
  outline: none;
  font-family: inherit;
  font-size: 0.9375em;
  font-weight: 600;
  color: var(--mar-text-color);
  padding: 0.1333em 0;
}

.mar-be-toggle-summary-text {
  flex: 1;
  min-width: 0;
  font-size: 0.9375em;
  font-weight: 600;
  color: var(--mar-text-color);
  padding: 0.1333em 0;
}

.mar-be-toggle-inner {
  padding: 0.25em 0 0.25em 1.625em;
}
</style>
