<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue";
import MarIconBtn from "../MarIconBtn";

const { src, alt = "" } = defineProps<{
  /** URL of the image shown in the zoomable stage. */
  src: string;
  /** Alt text for the image. */
  alt?: string;
}>();

const wrapper = ref<HTMLElement | null>(null);
const fullscreen = ref(false);
const scale = ref(1);
const tx = ref(0);
const ty = ref(0);
const dragging = ref(false);
let startX = 0;
let startY = 0;
let originX = 0;
let originY = 0;

const onFsChange = (): void => {
  fullscreen.value = document.fullscreenElement === wrapper.value;
};

const toggleFullscreen = (): void => {
  if (!wrapper.value) return;
  if (document.fullscreenElement === wrapper.value) void document.exitFullscreen();
  else void wrapper.value.requestFullscreen();
};

onMounted(() => document.addEventListener("fullscreenchange", onFsChange));
onBeforeUnmount(() => document.removeEventListener("fullscreenchange", onFsChange));

const clampScale = (v: number) => Math.min(5, Math.max(1, v));

const reset = () => {
  scale.value = 1;
  tx.value = 0;
  ty.value = 0;
};

const zoomBy = (factor: number) => {
  const next = clampScale(scale.value * factor);
  scale.value = next;
  if (next === 1) {
    tx.value = 0;
    ty.value = 0;
  }
};

const onWheel = (e: WheelEvent) => {
  e.preventDefault();
  zoomBy(e.deltaY < 0 ? 1.1 : 1 / 1.1);
};

const onPointerDown = (e: PointerEvent) => {
  if (scale.value <= 1) return;
  dragging.value = true;
  startX = e.clientX;
  startY = e.clientY;
  originX = tx.value;
  originY = ty.value;
  (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
};

const onPointerMove = (e: PointerEvent) => {
  if (!dragging.value) return;
  tx.value = originX + (e.clientX - startX);
  ty.value = originY + (e.clientY - startY);
};

const onPointerUp = (e: PointerEvent) => {
  if (!dragging.value) return;
  dragging.value = false;
  (e.currentTarget as HTMLElement).releasePointerCapture(e.pointerId);
};
</script>

<template>
  <div
    ref="wrapper"
    :class="['mar-image-controls', { 'mar-image-controls-fs': fullscreen }]"
  >
    <div
      :class="[
        'mar-image-controls-stage',
        { 'mar-image-controls-stage-grab': scale > 1 },
        { 'mar-image-controls-stage-grabbing': dragging },
      ]"
      @wheel="onWheel"
      @pointerdown="onPointerDown"
      @pointermove="onPointerMove"
      @pointerup="onPointerUp"
      @pointercancel="onPointerUp"
    >
      <img
        :src="src"
        :alt="alt"
        class="mar-image-controls-img"
        draggable="false"
        :style="{ transform: `translate(${tx}px, ${ty}px) scale(${scale})` }"
      />
    </div>
    <div class="mar-image-controls-bar" aria-label="Image controls">
      <MarIconBtn icon="zoom-out" tooltip="Zoom out" @click="zoomBy(1 / 1.25)" />
      <span class="mar-image-controls-pct">{{ Math.round(scale * 100) }}%</span>
      <MarIconBtn icon="zoom-in" tooltip="Zoom in" @click="zoomBy(1.25)" />
      <MarIconBtn icon="refresh" tooltip="Reset" @click="reset" />
      <MarIconBtn :icon="fullscreen ? 'shrink' : 'full-screen'" tooltip="Fullscreen" @click="toggleFullscreen" />
    </div>
  </div>
</template>

<style scoped>
.mar-image-controls {
  position: relative;
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  min-height: 0;
}

.mar-image-controls-fs {
  background: light-dark(var(--mar-surface-950), var(--mar-surface-0));
}

.mar-image-controls-stage {
  flex: 1;
  min-height: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  touch-action: none;
}

.mar-image-controls-stage-grab {
  cursor: grab;
}

.mar-image-controls-stage-grabbing {
  cursor: grabbing;
}

.mar-image-controls-img {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
  display: block;
  user-select: none;
  transition: transform 0.05s linear;
}

.mar-image-controls-bar {
  position: absolute;
  bottom: 0.5em;
  right: 0.5em;
  display: flex;
  align-items: center;
  gap: 0.25em;
  padding: 0.25em;
  background: color-mix(in srgb, var(--mar-surface-0) 90%, transparent);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 6px;
  z-index: 2;
}

.mar-image-controls-pct {
  font-size: 0.6875em;
  font-variant-numeric: tabular-nums;
  color: var(--mar-surface-600);
  min-width: 3.6364em;
  text-align: center;
}
</style>
