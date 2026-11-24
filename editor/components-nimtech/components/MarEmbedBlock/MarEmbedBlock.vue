<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import MarIcon from "../MarIcon";

const props = defineProps<{
  /** Editor node whose options carry the url, height, and fullWidth of the embed. */
  node: {
    options: {
      url?: string;
      height?: number | null;
      fullWidth?: boolean;
    };
    textContent?: string;
  };
  /** Marks the node as selected in the editor, adding an outline. */
  selected: boolean;
  /** Editor instance whose isEditable flag switches between the iframe and the readonly link rendering. */
  editor?: { isEditable: boolean };
}>();

const editable = computed(() => props.editor?.isEditable ?? true);
const url = computed(() => props.node.options.url ?? "");
const height = computed(() => props.node.options.height ?? null);
const fullWidth = computed(() => props.node.options.fullWidth !== false);
</script>

<template>
  <NodeViewWrapper v-if="!editable" class="mar-be-embed-readonly" contenteditable="false">
    <a :href="url" target="_blank" rel="noopener" class="mar-be-embed-readonly-link">
      <MarIcon icon="open-in-new" />
      <span>{{ url }}</span>
    </a>
  </NodeViewWrapper>
  <NodeViewWrapper
    v-else
    :class="[
      'mar-be-embed',
      { 'mar-be-embed-selected': selected, 'mar-be-embed-auto': !fullWidth, 'mar-be-embed-blank': !url },
    ]"
    contenteditable="false"
  >
    <iframe
      v-if="url"
      :src="url"
      class="mar-be-embed-frame"
      :style="{ height: height ? `${height}px` : undefined }"
      sandbox="allow-scripts allow-same-origin allow-popups allow-forms"
      loading="lazy"
    ></iframe>
    <div v-else class="mar-be-empty mar-be-empty-browser">
      <span class="mar-be-empty-art">
        <span class="mar-be-empty-chrome">
          <span class="mar-be-empty-dot" />
          <span class="mar-be-empty-dot" />
          <span class="mar-be-empty-dot" />
          <span class="mar-be-empty-url" />
        </span>
        <span class="mar-be-empty-viewport"><MarIcon icon="globe" /></span>
      </span>
      <span class="mar-be-empty-text">
        <span class="mar-be-empty-title">Embed a page</span>
        <span class="mar-be-empty-hint">Set the address from the block menu</span>
      </span>
    </div>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-embed-readonly {
  display: block;
  margin: 0.5em 0;
}

.mar-be-embed-readonly-link {
  display: inline-flex;
  align-items: center;
  gap: 0.4286em;
  color: var(--mar-primary-color);
  font-size: 0.875em;
  text-decoration: none;
  word-break: break-all;
}

.mar-be-embed-readonly-link .mar-icon {
  font-size: 1.3061em;
}

.mar-be-empty-viewport .mar-icon {
  font-size: 0.6531em;
}

.mar-be-embed-readonly-link:hover {
  text-decoration: underline;
}

.mar-be-embed {
  margin: 0.5em 0;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
  overflow: hidden;
}

.mar-be-embed-blank {
  border: none;
}

.mar-be-embed-auto {
  max-width: 40em;
}

.mar-be-embed-selected {
  outline: 1px solid var(--mar-surface-400);
}

.mar-be-embed-frame {
  width: 100%;
  height: 24em;
  border: none;
  display: block;
}
</style>
