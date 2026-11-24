<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import { getMediaOptions } from "@/blockedit/model/schema.ts";
import type { MarMediaAsset } from "@/types/media.types";
import MarIcon from "../MarIcon";
import MarFilePreview from "../MarFilePreview";

const props = defineProps<{
  /** Editor node whose options carry the src, name, height, and fullWidth of the pdf. */
  node: {
    options: {
      src?: string;
      name?: string;
      height?: number | null;
      fullWidth?: boolean;
    };
    textContent?: string;
  };
  /** Draws the editor selection outline around the block. */
  selected: boolean;
  /** Editability source, the block behaves as editable when absent. */
  editor?: { isEditable: boolean };
  /** Callback the empty preview calls to store the picked source. */
  updateAttributes?: (attrs: Record<string, unknown>) => void;
  /** Editor wiring, whose requestMedia opens the host's upload dialog from the empty preview. */
  extension?: {
    options: {
      requestMedia?: (kind: "pdf", current?: string) => Promise<MarMediaAsset | null>;
    };
  };
}>();

const src = computed(() => props.node.options.src ?? "");
const name = computed(() => props.node.options.name ?? "Document.pdf");
const height = computed(() => props.node.options.height ?? null);
const fullWidth = computed(() => props.node.options.fullWidth !== false);
const editable = computed(() => props.editor?.isEditable ?? true);
const requestMedia = computed(() => props.extension?.options.requestMedia);

const pick = async (): Promise<void> => {
  const next = await requestMedia.value?.("pdf");
  if (next) props.updateAttributes?.(getMediaOptions("pdf", next));
};
</script>

<template>
  <NodeViewWrapper
    :class="[
      'mar-be-pdf',
      { 'mar-be-pdf-selected': selected, 'mar-be-pdf-auto': !fullWidth, 'mar-be-pdf-blank': !src },
    ]"
    contenteditable="false"
  >
    <div v-if="src" class="mar-be-pdf-bar">
      <MarIcon icon="file-pdf" />
      <span class="mar-be-pdf-name">{{ name }}</span>
      <a
        v-if="src"
        :href="src"
        target="_blank"
        rel="noopener"
        class="mar-be-pdf-open"
      >
        <MarIcon icon="open-in-new" />
      </a>
    </div>
    <div
      v-if="src"
      class="mar-be-pdf-preview"
      :style="{ height: height ? `${height}px` : undefined }"
    >
      <MarFilePreview :url="src" mime-type="application/pdf" :name="name" />
    </div>
    <button
      v-else-if="editable"
      type="button"
      class="mar-be-empty mar-be-empty-page"
      :disabled="!requestMedia"
      @click="pick"
    >
      <span class="mar-be-empty-art">
        <span class="mar-be-empty-sheet">
          <span class="mar-be-empty-line" />
          <span class="mar-be-empty-line" />
          <span class="mar-be-empty-line" />
          <span class="mar-be-empty-line" />
          <span class="mar-be-empty-line" />
        </span>
      </span>
      <span class="mar-be-empty-text">
        <span class="mar-be-empty-title">Add a PDF</span>
        <span class="mar-be-empty-hint">{{ requestMedia ? "Click to upload or pick a PDF" : "Set the PDF from the block menu" }}</span>
      </span>
    </button>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-pdf {
  margin: 0.5em 0;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
  overflow: hidden;
}

.mar-be-pdf-auto {
  max-width: 40em;
}

.mar-be-pdf-blank {
  border: none;
}

.mar-be-pdf-selected {
  outline: 1px solid var(--mar-surface-400);
}

.mar-be-pdf-bar {
  display: flex;
  align-items: center;
  gap: 0.6154em;
  padding: 0.6154em 0.7692em;
  background: var(--mar-surface-50);
  border-bottom: 1px solid var(--mar-content-border-color);
  font-size: 0.8125em;
  color: var(--mar-text-color);
}

.mar-be-pdf-bar .mar-icon {
  font-size: 1.4066em;
}

.mar-be-pdf-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mar-be-pdf-open {
  color: var(--mar-surface-500);
  flex-shrink: 0;
}

.mar-be-pdf-open:hover {
  color: var(--mar-primary-color);
}

.mar-be-pdf-preview {
  overflow: auto;
}
</style>
