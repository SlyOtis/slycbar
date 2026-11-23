<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import MarCode from "../MarCode";

const props = defineProps<{
  /** Editor node whose options carry the html markup and the source flag. */
  node: {
    options: {
      html?: string;
      source?: boolean;
    };
  };
  /** Editor callback writing edited markup back onto the node. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
  /** Editor instance whose isEditable flag gates the source view. */
  editor: { isEditable: boolean };
  /** Marks the node as selected in the editor, drawing an outline. */
  selected: boolean;
}>();

const html = computed<string>(() => String(props.node.options.html ?? ""));
const sourceMode = computed(() => props.node.options.source === true);
const showSource = computed(() => props.editor.isEditable && sourceMode.value);

const onCodeChange = (text: string): void => {
  if (text === html.value) return;
  props.updateAttributes({ html: text });
};
</script>

<template>
  <NodeViewWrapper
    :class="['mar-html-block', { 'mar-html-block-selected': selected }]"
    contenteditable="false"
  >
    <MarCode
      v-if="showSource"
      :model-value="html"
      language="html"
      :show-line-numbers="false"
      fit-content
      @update:model-value="onCodeChange"
    />
    <div v-else class="mar-html-block-rendered" v-html="html"></div>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-html-block {
  position: relative;
  margin: 0.5em 0;
}

.mar-html-block-selected {
  outline: 2px solid var(--mar-surface-400);
  outline-offset: 2px;
  border-radius: 6px;
}

.mar-html-block-rendered {
  min-height: 1em;
}
</style>
