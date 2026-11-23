<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import { getMediaOptions } from "@/blockedit/model/schema.ts";
import type { MarMediaAsset } from "@/types/media.types";
import MarIconBtn from "../MarIconBtn";

const props = defineProps<{
  /** Editor node whose options carry the image source, alignment, fit, height, and crop state. */
  node: {
    options: {
      src?: string;
      align?: "left" | "center" | "right";
      fit?: boolean;
      objectFit?: "cover" | "contain" | "fill" | "none" | "scale-down";
      height?: number | null;
      cropX?: number;
      cropY?: number;
      cropScale?: number;
    };
  };
  /** Draws the primary outline around the frame when the block is selected. */
  selected: boolean;
  /** Editability source, the block behaves as editable when absent. */
  editor?: { isEditable: boolean };
  /** Callback the block calls to persist crop changes back into the document. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
  /** Editor wiring, whose requestMedia opens the host's upload dialog from the empty preview. */
  extension?: {
    options: {
      requestMedia?: (kind: "image", current?: string) => Promise<MarMediaAsset | null>;
    };
  };
}>();

const a = computed(() => props.node.options);
const requestMedia = computed(() => props.extension?.options.requestMedia);

const pick = async (): Promise<void> => {
  const next = await requestMedia.value?.("image");
  if (next) props.updateAttributes(getMediaOptions("image", next));
};

const editable = computed(() => props.editor?.isEditable ?? true);
const src = computed(() => String(a.value.src ?? ""));
const align = computed(() => String(a.value.align ?? "center"));
const fit = computed(() => a.value.fit !== false);
const objectFit = computed(() => String(a.value.objectFit ?? "cover"));
const height = computed(() => a.value.height ?? null);

const cropX = ref(Number(a.value.cropX ?? 0));
const cropY = ref(Number(a.value.cropY ?? 0));
const cropScale = ref(Number(a.value.cropScale ?? 1));

watch(
  () => [a.value.cropX, a.value.cropY, a.value.cropScale],
  () => {
    cropX.value = Number(a.value.cropX ?? 0);
    cropY.value = Number(a.value.cropY ?? 0);
    cropScale.value = Number(a.value.cropScale ?? 1);
  },
);

const frameEl = ref<HTMLElement | null>(null);
const fullscreen = ref(false);
const dragging = ref(false);
let startX = 0;
let startY = 0;
let panX = 0;
let panY = 0;

const commit = (): void => {
  props.updateAttributes({
    cropX: Math.round(cropX.value),
    cropY: Math.round(cropY.value),
    cropScale: Number(cropScale.value.toFixed(3)),
  });
};

const onPointerDown = (e: PointerEvent): void => {
  if (!editable.value || !(e.ctrlKey || e.metaKey)) return;
  e.preventDefault();
  dragging.value = true;
  startX = e.clientX;
  startY = e.clientY;
  panX = cropX.value;
  panY = cropY.value;
  (e.currentTarget as Element).setPointerCapture(e.pointerId);
};

const onPointerMove = (e: PointerEvent): void => {
  if (!dragging.value) return;
  cropX.value = panX + (e.clientX - startX);
  cropY.value = panY + (e.clientY - startY);
};

const onPointerUp = (e: PointerEvent): void => {
  if (!dragging.value) return;
  dragging.value = false;
  (e.currentTarget as Element).releasePointerCapture(e.pointerId);
  commit();
};

const onWheel = (e: WheelEvent): void => {
  if (!editable.value || !(e.ctrlKey || e.metaKey)) return;
  e.preventDefault();
  const next = cropScale.value + (e.deltaY > 0 ? -0.06 : 0.06);
  cropScale.value = Math.max(0.25, Math.min(5, next));
  commit();
};

const zoomBy = (factor: number): void => {
  cropScale.value = Math.max(0.25, Math.min(5, cropScale.value * factor));
  commit();
};

const resetCrop = (): void => {
  cropX.value = 0;
  cropY.value = 0;
  cropScale.value = 1;
  commit();
};

const onFsChange = (): void => {
  fullscreen.value = document.fullscreenElement === frameEl.value;
};

const toggleFullscreen = (): void => {
  if (!frameEl.value) return;
  if (document.fullscreenElement === frameEl.value) void document.exitFullscreen();
  else void frameEl.value.requestFullscreen();
};

onMounted(() => document.addEventListener("fullscreenchange", onFsChange));
onBeforeUnmount(() => document.removeEventListener("fullscreenchange", onFsChange));

const cropped = computed(
  () => cropX.value !== 0 || cropY.value !== 0 || cropScale.value !== 1,
);

const imgStyle = computed<Record<string, string>>(() => ({
  "object-fit": objectFit.value,
  transform: `translate(${cropX.value}px, ${cropY.value}px) scale(${cropScale.value})`,
}));
</script>

<template>
  <NodeViewWrapper
    :class="['mar-be-image', `mar-be-image-${align}`, { 'mar-be-image-selected': selected }]"
    contenteditable="false"
  >
    <button
      v-if="!src && editable"
      type="button"
      class="mar-be-empty mar-be-empty-image"
      :disabled="!requestMedia"
      @click="pick"
    >
      <span class="mar-be-empty-art">
        <span class="mar-be-empty-sun" />
        <span class="mar-be-empty-peak mar-be-empty-peak-near" />
        <span class="mar-be-empty-peak mar-be-empty-peak-far" />
      </span>
      <span class="mar-be-empty-text">
        <span class="mar-be-empty-title">Add an image</span>
        <span class="mar-be-empty-hint">{{ requestMedia ? "Click to upload or pick an image" : "Set the image from the block menu" }}</span>
      </span>
    </button>
    <div
      v-else-if="src"
      ref="frameEl"
      :class="['mar-be-image-frame', { 'mar-be-image-frame-auto': !fit, 'mar-be-image-frame-cropped': cropped || height, 'mar-be-image-frame-fs': fullscreen }]"
      :style="{ height: !fullscreen && height ? `${height}px` : undefined }"
      @pointerdown="onPointerDown"
      @pointermove="onPointerMove"
      @pointerup="onPointerUp"
      @pointercancel="onPointerUp"
      @wheel="onWheel"
    >
      <img :src="src" :style="fullscreen ? undefined : imgStyle" draggable="false" alt="" />
      <div v-if="editable" class="mar-be-image-toolbar" aria-label="Image controls">
        <MarIconBtn icon="zoom-out" tooltip="Zoom out" @click="zoomBy(1 / 1.25)" />
        <MarIconBtn icon="zoom-in" tooltip="Zoom in" @click="zoomBy(1.25)" />
        <MarIconBtn icon="refresh" tooltip="Reset" @click="resetCrop" />
        <MarIconBtn :icon="fullscreen ? 'shrink' : 'full-screen'" tooltip="Fullscreen" @click="toggleFullscreen" />
      </div>
    </div>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-image {
  margin: 0.5em 0;
}

.mar-be-image-center {
  text-align: center;
}

.mar-be-image-left {
  text-align: left;
}

.mar-be-image-right {
  text-align: right;
}

.mar-be-image-frame {
  position: relative;
  display: inline-block;
  width: 100%;
  max-width: 100%;
  border-radius: 6px;
  overflow: hidden;
  vertical-align: top;
  touch-action: none;
}

.mar-be-image-frame-auto {
  width: auto;
}

.mar-be-image-frame-cropped {
  cursor: grab;
  background: var(--mar-surface-100);
}

.mar-be-image-frame-cropped:active {
  cursor: grabbing;
}

.mar-be-image-frame img {
  display: block;
  width: 100%;
  height: 100%;
  transform-origin: center center;
  user-select: none;
}

.mar-be-image-frame-auto img {
  width: auto;
  max-width: 100%;
}

.mar-be-image-selected .mar-be-image-frame {
  outline: 2px solid var(--mar-primary-color);
}

.mar-be-image-toolbar {
  position: absolute;
  bottom: 1.25em;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  gap: 0.125em;
  background: color-mix(in srgb, var(--mar-surface-0) 88%, transparent);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 9999px;
  padding: 0.1875em;
  z-index: 2;
  opacity: 0;
  transition: opacity 0.15s ease;
}

.mar-be-image-frame:hover .mar-be-image-toolbar,
.mar-be-image-frame-fs .mar-be-image-toolbar {
  opacity: 1;
}

.mar-be-image-toolbar :deep(.mar-icon-btn) {
  width: 1.5em;
  height: 1.5em;
}

.mar-be-image-frame-fs {
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--mar-surface-950);
  border-radius: 0;
}

.mar-be-image-frame-fs img {
  width: auto !important;
  height: auto !important;
  max-width: 100%;
  max-height: 100%;
  object-fit: contain !important;
  transform: none !important;
}
</style>
