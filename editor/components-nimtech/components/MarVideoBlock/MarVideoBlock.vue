<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import { getMediaOptions } from "@/blockedit/model/schema.ts";
import type { MarMediaAsset } from "@/types/media.types";
import MarIcon from "../MarIcon";
import MarVideoControls from "../MarVideoControls";

const props = defineProps<{
  /** Block node whose options carry the source url, alignment, fit, height, and autoplay. */
  node: {
    options: {
      src?: string;
      align?: "left" | "center" | "right";
      fit?: boolean;
      height?: number | null;
      autoplay?: boolean;
    };
    textContent?: string;
  };
  /** Draws the selection outline around the frame. */
  selected: boolean;
  /** Editability source, the block behaves as editable when absent. */
  editor?: { isEditable: boolean };
  /** Callback the empty preview calls to store the picked source. */
  updateAttributes?: (attrs: Record<string, unknown>) => void;
  /** Editor wiring, whose requestMedia opens the host's upload dialog from the empty preview. */
  extension?: {
    options: {
      requestMedia?: (kind: "video", current?: string) => Promise<MarMediaAsset | null>;
    };
  };
}>();

const src = computed(() => props.node.options.src ?? "");
const align = computed(() => props.node.options.align ?? "center");
const fit = computed(() => props.node.options.fit ?? true);
const height = computed(() => props.node.options.height ?? null);
const autoplay = computed(() => props.node.options.autoplay === true);
const editable = computed(() => props.editor?.isEditable ?? true);
const requestMedia = computed(() => props.extension?.options.requestMedia);

const pick = async (): Promise<void> => {
  const next = await requestMedia.value?.("video");
  if (next) props.updateAttributes?.(getMediaOptions("video", next));
};
</script>

<template>
  <NodeViewWrapper
    :class="['mar-be-video', `mar-be-video-${align}`, { 'mar-be-video-selected': selected }]"
    contenteditable="false"
  >
    <div
      class="mar-be-video-inner"
      :style="{
        width: fit ? '100%' : 'auto',
        height: height ? `${height}px` : undefined,
      }"
    >
      <MarVideoControls v-if="src" :src="src" :autoplay="autoplay" :muted="autoplay" />
      <button
        v-else-if="editable"
        type="button"
        class="mar-be-empty mar-be-empty-video"
        :disabled="!requestMedia"
        @click="pick"
      >
        <span class="mar-be-empty-art">
          <span class="mar-be-empty-play"><MarIcon icon="play" /></span>
          <span class="mar-be-empty-scrub" />
        </span>
        <span class="mar-be-empty-text">
          <span class="mar-be-empty-title">Add a video</span>
          <span class="mar-be-empty-hint">{{ requestMedia ? "Click to upload or pick a video" : "Set the video from the block menu" }}</span>
        </span>
      </button>
    </div>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-video {
  display: flex;
  margin: 0.5em 0;
}

.mar-be-video-left {
  justify-content: flex-start;
}

.mar-be-video-center {
  justify-content: center;
}

.mar-be-video-right {
  justify-content: flex-end;
}

.mar-be-empty-play > .mar-icon {
  font-size: 0.5714em;
}

.mar-be-video-inner {
  max-width: 100%;
  border-radius: 8px;
  overflow: hidden;
}

.mar-be-video-selected .mar-be-video-inner {
  outline: 1px solid var(--mar-surface-400);
}
</style>
