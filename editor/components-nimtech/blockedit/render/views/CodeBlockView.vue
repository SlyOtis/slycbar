<script setup lang="ts">
import { computed, ref } from "vue";
import { NodeViewWrapper } from "./nodeViewBridge.ts";
import MarCode from "@/components/MarCode";
import MarMermaidBlock from "@/components/MarMermaidBlock";
import MarSwitchInput from "@/components/MarSwitchInput";
import MarDropdownInput from "@/components/MarDropdownInput";

const props = defineProps<{
  node: { options: Record<string, unknown>; textContent: string };
  updateAttributes: (attrs: Record<string, unknown>) => void;
  editor: { isEditable: boolean };
  setText: (text: string) => void;
  getPos: () => string;
  selected: boolean;
}>();

const languages = [
  "plaintext",
  "bash",
  "css",
  "csharp",
  "go",
  "javascript",
  "json",
  "python",
  "rust",
  "sql",
  "typescript",
  "vue",
  "yaml",
];

const previewOn = ref(props.node.textContent.trim().length > 0);

const language = computed<string>(() => {
  const raw = (props.node.options as { language?: string | null }).language;
  return typeof raw === "string" && raw.length > 0 ? raw : "plaintext";
});

const lineNumbers = computed(() => props.node.options.lineNumbers !== false);

const lineWrap = computed(() => props.node.options.lineWrap === true);

const isMermaid = computed(() => language.value === "mermaid");

const codeText = computed(() => props.node.textContent);

const onCodeChange = (text: string) => {
  if (text === props.node.textContent) return;
  props.setText(text);
};

const onLanguageChange = (value: string | string[] | null) => {
  if (typeof value !== "string" || !value) return;
  props.updateAttributes({ language: value });
};
</script>

<template>
  <NodeViewWrapper
    :class="[
      'mar-cb',
      { 'mar-cb-selected': selected, 'mar-cb-mermaid': isMermaid },
    ]"
    contenteditable="false"
  >
    <div v-if="editor.isEditable" class="mar-cb-controls">
      <MarSwitchInput
        v-if="isMermaid"
        :model-value="previewOn"
        label="Preview"
        @update:model-value="previewOn = $event"
      />
      <MarDropdownInput
        v-else
        class="mar-cb-lang"
        :model-value="language"
        :options="languages"
        search-placeholder="Language…"
        @update:model-value="onLanguageChange"
      />
    </div>
    <MarMermaidBlock
      v-if="isMermaid && (previewOn || !editor.isEditable)"
      :source="codeText"
      :readonly="!editor.isEditable"
    />
    <MarCode
      v-else
      :model-value="codeText"
      :language="language"
      :show-line-numbers="lineNumbers"
      :line-wrap="lineWrap"
      :readonly="!editor.isEditable"
      fit-content
      @update:model-value="onCodeChange"
    />
  </NodeViewWrapper>
</template>

<style scoped>
.mar-cb {
  position: relative;
  border: 2px solid var(--mar-content-border-color);
  border-radius: 10px;
  margin: 0.5rem 0;
  overflow: hidden;
}

.mar-cb-selected {
  border-color: var(--mar-surface-400);
}

.mar-cb-controls {
  position: absolute;
  top: 0.375rem;
  right: 0.375rem;
  z-index: 2;
  display: flex;
  align-items: center;
  gap: 0.375rem;
  user-select: none;
}

.mar-cb-lang {
  flex: 0 0 7.875em;
}

.mar-cb :deep(.mar-code-block) {
  border: none;
  border-radius: 0;
}

.mar-cb :deep(.cm-content) {
  padding: 0.625rem 0.75rem;
}

.mar-cb :deep(.mar-mermaid) {
  margin: 0;
  border: none;
  border-radius: 0;
}
</style>
