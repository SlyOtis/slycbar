<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import { useMarInputAnswers, marInputKey } from "@/blockedit/inputAnswers";
import MarTextInput from "../MarTextInput";
import MarTextareaInput from "../MarTextareaInput";
import MarInlineTextInput from "../MarInlineTextInput";

const props = defineProps<{
  /** Block node whose options carry the answer key, question label, multiline flag, required flag, and read view gating. */
  node: {
    options: {
      key?: string;
      label?: string;
      multiline?: boolean;
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
const multiline = computed(() => props.node.options.multiline === true);
const required = computed(() => props.node.options.required === true);
const answerable = computed(() => props.node.options.interactive !== false);
const answerKey = computed(() => marInputKey(props.node.options));

const answers = useMarInputAnswers();
const value = computed(() => answers?.values[answerKey.value] ?? "");

const onLabel = (next: string | number | null) =>
  props.updateAttributes({ label: String(next ?? "") });

const onValue = (next: string | number) =>
  answers?.set(answerKey.value, String(next));
</script>

<template>
  <NodeViewWrapper
    :class="['mar-be-input', { 'mar-be-input-selected': selected }]"
    contenteditable="false"
  >
    <div v-if="editable" class="mar-be-input-head">
      <span class="mar-be-input-label">
        <MarInlineTextInput
          :model-value="label"
          placeholder="Question"
          aria-label="Question"
          underline="dashed"
          :min-chars="16"
          @update:model-value="onLabel"
        />
        <span v-if="required" class="mar-be-input-required">*</span>
      </span>
    </div>
    <MarTextareaInput
      v-if="multiline"
      :label="editable ? 'Answer preview' : label"
      :model-value="value"
      :rows="3"
      :required="!editable && required"
      :disabled="editable || !answers || !answerable"
      @update:model-value="onValue"
    />
    <MarTextInput
      v-else
      :label="editable ? 'Answer preview' : label"
      :model-value="value"
      :required="!editable && required"
      :disabled="editable || !answers || !answerable"
      @update:model-value="onValue"
    />
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
</style>
