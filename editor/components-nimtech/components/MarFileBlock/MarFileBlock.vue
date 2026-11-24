<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import { getMediaOptions } from "@/blockedit/model/schema.ts";
import type { MarMediaAsset } from "@/types/media.types";
import MarIcon from "../MarIcon";
import type { IconType } from "@/types/icon.types";
import { getFileIcon } from "@/utils/fileIcon";

const props = defineProps<{
  /** Editor node whose options carry the name, mimeType, and assetId of the file. */
  node: {
    options: {
      assetId?: string;
      url?: string;
      name?: string;
      mimeType?: string;
    };
    textContent?: string;
  };
  /** Marks the node as selected in the editor, highlighting the chip border. */
  selected: boolean;
  /** Editability source, the block behaves as editable when absent. */
  editor?: { isEditable: boolean };
  /** Callback the empty preview calls to store the picked file. */
  updateAttributes?: (attrs: Record<string, unknown>) => void;
  /** Extension instance whose onOpen option receives the assetId when the chip is clicked, and whose requestMedia opens the host's media dialog from the empty preview. */
  extension: {
    options: {
      onOpen: (assetId: string) => void;
      requestMedia?: (kind: "file", current?: string) => Promise<MarMediaAsset | null>;
    };
  };
}>();

const editable = computed(() => props.editor?.isEditable ?? true);
const url = computed(() => props.node.options.url ?? "");
const blank = computed(() => !props.node.options.assetId && !url.value);
const requestMedia = computed(() => props.extension.options.requestMedia);
const name = computed(() => props.node.options.name ?? "File");
const mimeType = computed(() => props.node.options.mimeType ?? "");

const pick = async (): Promise<void> => {
  const next = await requestMedia.value?.("file");
  if (next) props.updateAttributes?.(getMediaOptions("file", next));
};

const icon = computed<IconType>(() => getFileIcon(name.value, mimeType.value));

const open = () => {
  const assetId = props.node.options.assetId;
  if (assetId) props.extension.options.onOpen(assetId);
  else if (url.value) window.open(url.value, "_blank", "noopener");
};
</script>

<template>
  <NodeViewWrapper
    :class="['mar-be-file', { 'mar-be-file-selected': selected }]"
    contenteditable="false"
  >
    <template v-if="blank">
      <button
        v-if="editable"
        type="button"
        class="mar-be-empty mar-be-empty-row"
        :disabled="!requestMedia"
        @click="pick"
      >
        <span class="mar-be-empty-thumb"><MarIcon icon="attach-file" /></span>
        <span class="mar-be-empty-text">
          <span class="mar-be-empty-title">Attach a file</span>
          <span class="mar-be-empty-hint">{{ requestMedia ? "Click to upload or pick a file" : "Set the file from the block menu" }}</span>
        </span>
      </button>
    </template>
    <button v-else type="button" class="mar-be-file-btn" @click="open">
      <MarIcon :icon="icon" class="mar-be-file-icon" />
      <span class="mar-be-file-name">{{ name }}</span>
      <MarIcon icon="download" class="mar-be-file-action" />
    </button>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-file {
  margin: 0.25em 0;
}

.mar-be-file-btn {
  display: flex;
  align-items: center;
  gap: 0.6154em;
  width: 100%;
  padding: 0.6154em 0.7692em;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 6px;
  background: var(--mar-surface-50);
  cursor: pointer;
  font-family: inherit;
  font-size: 0.8125em;
  color: var(--mar-text-color);
  text-align: left;
  transition: background 0.15s cubic-bezier(0.4, 0, 0.2, 1),
    border-color 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-be-empty-thumb > .mar-icon {
  font-size: 0.8889em;
}

.mar-be-file-btn:hover {
  background: var(--mar-surface-100);
  border-color: var(--mar-surface-400);
}

.mar-be-file-selected .mar-be-file-btn {
  border-color: var(--mar-surface-400);
}

.mar-be-file-icon {
  flex-shrink: 0;
  font-size: 1.2308em;
  color: var(--mar-primary-color);
}

.mar-be-file-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mar-be-file-action {
  flex-shrink: 0;
  font-size: 1.2308em;
  color: var(--mar-surface-400);
}
</style>
