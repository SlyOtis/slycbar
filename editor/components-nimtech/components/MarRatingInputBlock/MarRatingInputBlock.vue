<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import { useMarInputAnswers, marInputKey } from "@/blockedit/inputAnswers";
import MarInlineTextInput from "../MarInlineTextInput";
import MarSliderInput from "../MarSliderInput";

const props = defineProps<{
  /** Block node whose options carry the answer key, question label, scale maximum, required flag, and read view gating. */
  node: {
    options: {
      key?: string;
      label?: string;
      max?: number;
      required?: boolean;
      interactive?: boolean;
    };
  };
  /** Editor context; an editable editor puts the block in authoring mode. */
  editor: { isEditable: boolean };
  /** Draws a selection outline around the block. */
  selected: boolean;
  /** Callback persisting label edits back into the document. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
}>();

const editable = computed(() => props.editor?.isEditable ?? true);
const label = computed(() => String(props.node.options.label ?? ""));
const max = computed(() =>
  Math.min(10, Math.max(2, Number(props.node.options.max) || 5)),
);
const required = computed(() => props.node.options.required === true);
const answerable = computed(() => props.node.options.interactive !== false);
const answerKey = computed(() => marInputKey(props.node.options));

const answers = useMarInputAnswers();
const value = computed(() => Number(answers?.values[answerKey.value]) || 1);

const onLabel = (next: string | number | null) =>
  props.updateAttributes({ label: String(next ?? "") });

const onValue = (next: number) => answers?.set(answerKey.value, String(next));
</script>

<template>
  <NodeViewWrapper
    :class="['mar-be-input', { 'mar-be-input-selected': selected }]"
    contenteditable="false"
  >
    <div class="mar-be-input-head">
      <span class="mar-be-input-label">
        <MarInlineTextInput
          v-if="editable"
          :model-value="label"
          placeholder="Question"
          aria-label="Question"
          underline="dashed"
          :min-chars="16"
          @update:model-value="onLabel"
        />
        <template v-else>{{ label }}</template>
        <span v-if="required" class="mar-be-input-required">*</span>
      </span>
    </div>
    <div :class="{ 'mar-be-input-freeze': editable || !answers || !answerable }">
      <MarSliderInput
        :model-value="value"
        :min="1"
        :max="max"
        :step="1"
        mode="stepped"
        show-value
        @update:model-value="onValue"
      />
    </div>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-input {
  margin: 0.5em 0;
  display: flex;
  flex-direction: column;
  gap: 0.375em;
}

.mar-be-input-selected {
  outline: 1px solid var(--mar-surface-400);
  outline-offset: 3px;
}

.mar-be-input-head {
  display: flex;
  align-items: center;
  gap: 0.5em;
}

.mar-be-input-label {
  flex: 1;
  min-width: 0;
  font-size: 0.9375em;
  font-weight: 600;
  color: var(--mar-text-color);
}

.mar-be-input-required {
  color: var(--mar-danger-color);
  margin-left: 0.1333em;
}

.mar-be-input-freeze {
  opacity: 0.7;
  pointer-events: none;
}
</style>
