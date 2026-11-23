<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from "vue";
import MarIconBtn from "../MarIconBtn";

const { source = "", readonly = false } = defineProps<{
  /** Mermaid definition rendered to svg, re-rendered on every change. */
  source?: string;
  /** Hides the toolbar, disables zoom and pan, and strips the border and background. */
  readonly?: boolean;
}>();

const wrapper = ref<HTMLElement | null>(null);
const stage = ref<HTMLElement | null>(null);
const viewport = ref<HTMLElement | null>(null);

const scale = ref(1);
const panX = ref(0);
const panY = ref(0);
const fullscreen = ref(false);

let rendering = false;
let dragging = false;
let dragStartX = 0;
let dragStartY = 0;
let baseX = 0;
let baseY = 0;
let renderToken = 0;

const minScale = 0.2;
const maxScale = 6;
const scaleStep = 1.2;

const isDark = () =>
  typeof document !== "undefined" &&
  document.documentElement.classList.contains("dark");

const reset = () => {
  scale.value = 1;
  panX.value = 0;
  panY.value = 0;
};

const render = async () => {
  if (!stage.value || rendering || !source) return;
  rendering = true;
  const token = ++renderToken;
  try {
    const mermaid = (await import("mermaid")).default;
    mermaid.initialize({
      startOnLoad: false,
      theme: isDark() ? "dark" : "default",
      fontFamily:
        'ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
      securityLevel: "loose",
      logLevel: "error",
      flowchart: {
        useMaxWidth: true,
        htmlLabels: true,
        curve: "basis",
        padding: 20,
        nodeSpacing: 50,
        rankSpacing: 50,
      },
      sequence: {
        useMaxWidth: true,
        actorMargin: 60,
        boxMargin: 15,
        mirrorActors: true,
      },
      gantt: { useMaxWidth: true, fontSize: 12 },
    });
    const id = `mar-mermaid-${token}-${source.length}`;
    const { svg } = await mermaid.render(id, source);
    if (token !== renderToken || !stage.value) return;
    stage.value.innerHTML = svg;
    const node = stage.value.querySelector("svg");
    if (node) {
      node.setAttribute("preserveAspectRatio", "xMidYMid meet");
      node.style.display = "block";
      node.style.maxWidth = "100%";
      node.style.maxHeight = "100%";
      node.style.background = "transparent";
    }
    reset();
  } catch (err) {
    if (stage.value) {
      stage.value.innerHTML = `<pre class="mar-mermaid-error">${String(err)}</pre>`;
    }
  } finally {
    rendering = false;
  }
};

let themeObserver: MutationObserver | null = null;

const onKey = (e: KeyboardEvent) => {
  if (e.key === "Escape" && fullscreen.value) void toggleFullscreen();
};

const onFsChange = () => {
  fullscreen.value = document.fullscreenElement === wrapper.value;
};

onMounted(() => {
  void render();
  document.addEventListener("keydown", onKey);
  document.addEventListener("fullscreenchange", onFsChange);
  themeObserver = new MutationObserver(() => void render());
  themeObserver.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["class"],
  });
});

onBeforeUnmount(() => {
  document.removeEventListener("keydown", onKey);
  document.removeEventListener("fullscreenchange", onFsChange);
  themeObserver?.disconnect();
  themeObserver = null;
});

watch(
  () => source,
  () => void render(),
);

const zoomIn = () => {
  scale.value = Math.min(maxScale, scale.value * scaleStep);
};

const zoomOut = () => {
  scale.value = Math.max(minScale, scale.value / scaleStep);
};

const toggleFullscreen = async () => {
  if (!wrapper.value) return;
  if (document.fullscreenElement === wrapper.value) {
    await document.exitFullscreen();
    fullscreen.value = false;
  } else {
    await wrapper.value.requestFullscreen();
    fullscreen.value = true;
  }
};

const onWheel = (e: WheelEvent) => {
  if (readonly || !viewport.value) return;
  e.preventDefault();
  const direction = e.deltaY < 0 ? scaleStep : 1 / scaleStep;
  const next = Math.min(maxScale, Math.max(minScale, scale.value * direction));
  const rect = viewport.value.getBoundingClientRect();
  const cx = e.clientX - rect.left - rect.width / 2;
  const cy = e.clientY - rect.top - rect.height / 2;
  const ratio = next / scale.value;
  panX.value = cx - (cx - panX.value) * ratio;
  panY.value = cy - (cy - panY.value) * ratio;
  scale.value = next;
};

const onPointerDown = (e: PointerEvent) => {
  if (readonly || e.button !== 0) return;
  dragging = true;
  dragStartX = e.clientX;
  dragStartY = e.clientY;
  baseX = panX.value;
  baseY = panY.value;
  viewport.value?.setPointerCapture(e.pointerId);
};

const onPointerMove = (e: PointerEvent) => {
  if (!dragging) return;
  panX.value = baseX + (e.clientX - dragStartX);
  panY.value = baseY + (e.clientY - dragStartY);
};

const onPointerUp = (e: PointerEvent) => {
  if (!dragging) return;
  dragging = false;
  try {
    viewport.value?.releasePointerCapture(e.pointerId);
  } catch {
    void 0;
  }
};
</script>

<template>
  <div
    ref="wrapper"
    :class="[
      'mar-mermaid',
      { 'mar-mermaid-fullscreen': fullscreen, 'mar-mermaid-readonly': readonly },
    ]"
  >
    <div
      ref="viewport"
      :class="['mar-mermaid-viewport', { 'mar-mermaid-dragging': dragging }]"
      @wheel="onWheel"
      @pointerdown="onPointerDown"
      @pointermove="onPointerMove"
      @pointerup="onPointerUp"
      @pointercancel="onPointerUp"
    >
      <div
        ref="stage"
        class="mar-mermaid-stage"
        :style="{
          transform: `translate(${panX}px, ${panY}px) scale(${scale})`,
        }"
      ></div>
    </div>
    <div
      v-if="!readonly"
      class="mar-mermaid-toolbar"
      aria-label="Diagram controls"
    >
      <MarIconBtn icon="zoom-out" tooltip="Zoom out" @click="zoomOut" />
      <MarIconBtn icon="zoom-in" tooltip="Zoom in" @click="zoomIn" />
      <MarIconBtn icon="refresh" tooltip="Reset" @click="reset" />
      <MarIconBtn :icon="fullscreen ? 'shrink' : 'full-screen'" tooltip="Fullscreen" @click="toggleFullscreen" />
    </div>
  </div>
</template>

<style scoped>
.mar-mermaid {
  position: relative;
  margin: 0.5em 0;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
  background: var(--mar-surface-0);
  overflow: hidden;
}

.mar-mermaid-fullscreen {
  margin: 0;
  border: 0;
  border-radius: 0;
  background: var(--mar-surface-0);
}

.mar-mermaid-readonly {
  border: none;
  border-radius: 0;
  background: transparent;
}

.mar-mermaid-readonly .mar-mermaid-viewport {
  cursor: default;
  touch-action: auto;
}

.mar-mermaid-viewport {
  position: relative;
  width: 100%;
  height: 360px;
  overflow: hidden;
  touch-action: none;
  cursor: grab;
  user-select: none;
}

.mar-mermaid-fullscreen .mar-mermaid-viewport {
  height: 100vh;
}

.mar-mermaid-dragging {
  cursor: grabbing;
}

.mar-mermaid-stage {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  transform-origin: center center;
  will-change: transform;
}

.mar-mermaid-stage :deep(svg) {
  display: block;
  max-width: 100%;
  max-height: 100%;
}

.mar-mermaid-stage :deep(.mar-mermaid-error) {
  color: var(--mar-red-500);
  font-size: 0.75em;
  white-space: pre-wrap;
  padding: 1em;
}

.mar-mermaid-toolbar {
  position: absolute;
  bottom: 0.5em;
  right: 0.5em;
  display: flex;
  gap: 0.25em;
  background: color-mix(in srgb, var(--mar-surface-0) 90%, transparent);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 6px;
  padding: 0.25em;
  z-index: 2;
}
</style>
