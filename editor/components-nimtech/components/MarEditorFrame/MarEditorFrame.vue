<script setup lang="ts">
import { computed, ref, useSlots } from "vue";
import { EditorView } from "@codemirror/view";
import MarIcon from "../MarIcon";
import MarSidePanel from "../MarSidePanel";
import type { MarCodeDiagnostic } from "../MarCode/marCode.types";
import type { MarEditorFrameMode, MarEditorFrameSplit } from "./marEditorFrame.types";

const {
  mode = "both",
  diagnostics = [],
  referenceLabel = "Reference",
  assistantLabel = "Assistant",
  referenceWidth = "20em",
  assistantWidth = "22em",
  showDiagnostics = true,
  split = "rows",
} = defineProps<{
  /** Shows the preview alone, the code alone, or both stacked; the host's tabs in `content-actions` set it. */
  mode?: MarEditorFrameMode;
  /** Problems in the code, listed in the bar under it, 1 based lines and columns as `MarCode` takes them. */
  diagnostics?: MarCodeDiagnostic[];
  /** Name of the reference panel. */
  referenceLabel?: string;
  /** Name of the assistant panel. */
  assistantLabel?: string;
  /** Open width of the reference column, a css length; the column never takes more than 30% of the frame. */
  referenceWidth?: string;
  /** Open width of the assistant column, a css length; the column never takes more than 35% of the frame. */
  assistantWidth?: string;
  /** Shows the diagnostics bar under the code; off when the host shows its problems elsewhere. */
  showDiagnostics?: boolean;
  /** How both are laid out: the preview over the code in two rows, or side by side in two columns with the diagnostics under the code. */
  split?: MarEditorFrameSplit;
}>();

/** Open state of the reference on the left, shown while the code is. */
const reference = defineModel<boolean>("reference", { default: true });

/** Open state of the assistant on the right, spanning every row. */
const assistant = defineModel<boolean>("assistant", { default: false });

const slots = useSlots();

const referenceShown = computed(() => !!slots.reference && reference.value && mode !== "preview");
const assistantShown = computed(() => !!slots.assistant && assistant.value);

const code = ref<HTMLElement | null>(null);
const preview = ref<HTMLElement | null>(null);

/** Share of the code and preview width the code takes in the columns split, in percent. */
const ratio = ref(50);

const dragging = ref(false);

const clampRatio = (value: number): number => Math.min(80, Math.max(20, value));

const onDividerDown = (event: PointerEvent): void => {
  if (!code.value || !preview.value) return;
  const target = event.currentTarget as HTMLElement;
  const start = code.value.getBoundingClientRect().left;
  const total = preview.value.getBoundingClientRect().right - start;
  if (total <= 0) return;
  target.setPointerCapture(event.pointerId);
  dragging.value = true;
  const move = (e: PointerEvent): void => {
    ratio.value = clampRatio(((e.clientX - start) / total) * 100);
  };
  const up = (): void => {
    dragging.value = false;
    target.removeEventListener("pointermove", move);
    target.removeEventListener("pointerup", up);
    target.removeEventListener("pointercancel", up);
  };
  target.addEventListener("pointermove", move);
  target.addEventListener("pointerup", up);
  target.addEventListener("pointercancel", up);
  event.preventDefault();
};

const onDividerKey = (event: KeyboardEvent): void => {
  if (event.key === "ArrowLeft") ratio.value = clampRatio(ratio.value - 2);
  else if (event.key === "ArrowRight") ratio.value = clampRatio(ratio.value + 2);
  else if (event.key === "Home") ratio.value = 20;
  else if (event.key === "End") ratio.value = 80;
  else return;
  event.preventDefault();
};

const jump = (diagnostic: MarCodeDiagnostic): void => {
  if (!diagnostic.line || !code.value) return;
  const editor = [...code.value.querySelectorAll<HTMLElement>(".cm-editor")].find((el) => el.getClientRects().length);
  const view = editor && EditorView.findFromDOM(editor);
  if (!view) return;
  const doc = view.state.doc;
  const line = doc.line(Math.min(Math.max(1, Math.floor(diagnostic.line)), doc.lines));
  const pos = line.from + Math.min(Math.max(0, (diagnostic.column || 1) - 1), line.length);
  view.dispatch({ selection: { anchor: pos }, effects: EditorView.scrollIntoView(pos, { y: "center" }) });
  view.focus();
};
</script>

<template>
  <div
    class="mar-editor-frame"
    :class="[`mar-editor-frame-mode-${mode}`, `mar-editor-frame-split-${split}`, { 'mar-editor-frame-dragging': dragging }]"
    :style="{
      '--mar-editor-frame-reference': referenceShown ? `min(${referenceWidth}, 30cqi)` : 'min(0em, 30cqi)',
      '--mar-editor-frame-assistant': assistantShown ? `min(${assistantWidth}, 35cqi)` : 'min(0em, 35cqi)',
      '--mar-editor-frame-code': `${ratio}%`,
    }"
  >
    <MarSidePanel
      v-if="$slots.reference"
      class="mar-editor-frame-reference"
      :open="referenceShown"
      :label="referenceLabel"
      :head="false"
      :width="`min(${referenceWidth}, 30cqi)`"
      @update:open="reference = $event"
    >
      <slot name="reference" />
    </MarSidePanel>

    <div v-show="mode !== 'code'" ref="preview" class="mar-editor-frame-preview">
      <slot name="preview" />
    </div>

    <div
      v-if="split === 'columns' && mode === 'both'"
      class="mar-editor-frame-divider"
      role="separator"
      aria-orientation="vertical"
      aria-valuemin="20"
      aria-valuemax="80"
      :aria-valuenow="Math.round(ratio)"
      tabindex="0"
      @pointerdown="onDividerDown"
      @keydown="onDividerKey"
    />

    <div v-show="mode !== 'preview'" ref="code" class="mar-editor-frame-code">
      <slot />
    </div>

    <div
      v-if="showDiagnostics && mode !== 'preview' && diagnostics.length"
      class="mar-editor-frame-diagnostics"
      role="status"
    >
      <ul class="mar-editor-frame-diagnostics-list">
        <li
          v-for="(d, i) in diagnostics"
          :key="i"
          class="mar-editor-frame-diagnostic"
          :class="`mar-editor-frame-diagnostic-${d.severity ?? 'error'}`"
          :tabindex="d.line ? 0 : undefined"
          @click="jump(d)"
          @keydown.enter="jump(d)"
        >
          <MarIcon icon="triangle-alert" class="mar-editor-frame-diagnostic-icon" />
          <span v-if="d.line" class="mar-editor-frame-diagnostic-at">{{ d.line }}:{{ d.column }}</span>
          <span class="mar-editor-frame-diagnostic-message">{{ d.message }}</span>
        </li>
      </ul>
    </div>

    <MarSidePanel
      v-if="$slots.assistant"
      v-model:open="assistant"
      class="mar-editor-frame-assistant"
      :label="assistantLabel"
      :head="false"
      side="end"
      :width="`min(${assistantWidth}, 35cqi)`"
    >
      <slot name="assistant" />
    </MarSidePanel>
  </div>
</template>

<style scoped>
.mar-editor-frame {
  display: grid;
  flex: 1;
  block-size: 100%;
  min-block-size: 0;
  min-inline-size: 0;
  container-type: inline-size;
  overflow: hidden;
  background: var(--mar-surface-0);
  grid-template-columns: var(--mar-editor-frame-reference) minmax(0, 1fr) var(--mar-editor-frame-assistant);
  grid-template-rows: minmax(0, 1fr) minmax(0, 1fr) auto;
  grid-template-areas:
    "reference preview assistant"
    "reference code assistant"
    "reference diagnostics assistant";
  transition: grid-template-columns 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-editor-frame-dragging {
  transition: none;
}

.mar-editor-frame-mode-preview {
  grid-template-rows: minmax(0, 1fr) 0 0;
}

.mar-editor-frame-mode-code {
  grid-template-rows: 0 minmax(0, 1fr) auto;
}

.mar-editor-frame > * {
  min-inline-size: 0;
  min-block-size: 0;
}

.mar-editor-frame-reference {
  grid-area: reference;
}

.mar-editor-frame-assistant {
  grid-area: assistant;
}

.mar-editor-frame-preview {
  grid-area: preview;
  display: flex;
  flex-direction: column;
  overflow: auto;
  background: var(--mar-surface-100);
}

.mar-editor-frame-mode-both .mar-editor-frame-preview {
  border-block-end: 1px solid var(--mar-content-border-color);
}

.mar-editor-frame-code {
  grid-area: code;
  display: flex;
  flex-direction: column;
}

.mar-editor-frame-split-columns {
  grid-template-columns: var(--mar-editor-frame-reference) minmax(0, var(--mar-editor-frame-code, 50%)) auto minmax(0, 1fr) var(--mar-editor-frame-assistant);
  grid-template-rows: minmax(0, 1fr) auto;
  grid-template-areas:
    "reference code divider preview assistant"
    "reference diagnostics divider preview assistant";
}

.mar-editor-frame-split-columns.mar-editor-frame-mode-preview {
  grid-template-columns: var(--mar-editor-frame-reference) 0 0 minmax(0, 1fr) var(--mar-editor-frame-assistant);
  grid-template-rows: minmax(0, 1fr) 0;
}

.mar-editor-frame-split-columns.mar-editor-frame-mode-code {
  grid-template-columns: var(--mar-editor-frame-reference) minmax(0, 1fr) 0 0 var(--mar-editor-frame-assistant);
  grid-template-rows: minmax(0, 1fr) auto;
}

.mar-editor-frame-split-columns.mar-editor-frame-mode-both .mar-editor-frame-preview {
  border-block-end: none;
}

.mar-editor-frame-divider {
  grid-area: divider;
  inline-size: 0.5em;
  cursor: col-resize;
  touch-action: none;
  background: linear-gradient(to right, transparent calc(50% - 0.5px), var(--mar-content-border-color) calc(50% - 0.5px), var(--mar-content-border-color) calc(50% + 0.5px), transparent calc(50% + 0.5px));
  transition: background 0.15s ease;
}

.mar-editor-frame-divider:hover,
.mar-editor-frame-divider:focus-visible {
  outline: none;
  background: linear-gradient(to right, transparent calc(50% - 1px), var(--mar-primary-color) calc(50% - 1px), var(--mar-primary-color) calc(50% + 1px), transparent calc(50% + 1px));
}

.mar-editor-frame-code :deep(.mar-code-block) {
  border-radius: 0;
}


.mar-editor-frame-diagnostics {
  grid-area: diagnostics;
  max-block-size: 12em;
  overflow: auto;
  border-block-start: 1px solid var(--mar-content-border-color);
  background: color-mix(in srgb, var(--mar-danger-color), transparent 92%);
}

.mar-editor-frame-diagnostics-list {
  display: flex;
  flex-direction: column;
  gap: 0.25em;
  margin: 0;
  padding: 0.5em 0.75em;
  list-style: none;
  font-family: var(--mar-font-mono);
  font-size: 0.75em;
}

.mar-editor-frame-diagnostic {
  display: grid;
  grid-template-columns: auto auto minmax(0, 1fr);
  align-items: baseline;
  gap: 0.5em;
  color: var(--mar-danger-color);
}

.mar-editor-frame-diagnostic[tabindex] {
  cursor: pointer;
}

.mar-editor-frame-diagnostic[tabindex]:hover {
  text-decoration: underline;
}

.mar-editor-frame-diagnostic-warning {
  color: var(--mar-warn-color);
}

.mar-editor-frame-diagnostic-icon {
  align-self: center;
}

.mar-editor-frame-diagnostic-at {
  font-variant-numeric: tabular-nums;
  opacity: 0.8;
}

.mar-editor-frame-diagnostic-message {
  grid-column: 3;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
</style>
