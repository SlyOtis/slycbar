<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from "vue";
import { openModal, type ModalHandle } from "@/composables/useModals.ts";

const {
  modelValue,
  min = 0,
  max = 100,
  step = 1,
  orientation = "horizontal",
  mode = "continuous",
  ticks,
  labels,
  format,
  length,
  showValue = false,
  tooltip = false,
  floating = false,
  disabled = false,
} = defineProps<{
  /** Current value, or the label index in label mode. */
  modelValue: number;
  /** Lower bound of the range; ignored when labels is set. */
  min?: number;
  /** Upper bound of the range; ignored when labels is set. */
  max?: number;
  /** Snap increment for pointer moves and keyboard nudges, and the tick spacing in stepped mode without explicit ticks. */
  step?: number;
  /** Track direction; vertical fills from the bottom. */
  orientation?: "horizontal" | "vertical";
  /** Stepped renders tick marks and snaps to them; labels forces stepped behavior. */
  mode?: "continuous" | "stepped";
  /** Explicit tick values in stepped mode; pointer input snaps to the nearest tick. */
  ticks?: number[];
  /** Switches to label mode where the range becomes the label indexes and displayed values are the label strings. */
  labels?: string[];
  /** Custom display formatting for the value chip and tooltip. */
  format?: (value: number) => string;
  /** Track length along the orientation, a number in pixels or any css length; without it the track fills its container. */
  length?: number | string;
  /** Renders the formatted current value as a chip before the track. */
  showValue?: boolean;
  /** Shows the formatted value in an overlay tooltip anchored to the handle while dragging or hovering. */
  tooltip?: boolean;
  /** Renders the control as a standalone overlay panel: its own surface, an even inset around the track, and the value chip under it. */
  floating?: boolean;
  /** Dims the control, removes it from the tab order, and blocks pointer and keyboard input. */
  disabled?: boolean;
}>();

const emit = defineEmits<{ "update:modelValue": [value: number] }>();

const trackEl = ref<HTMLElement | null>(null);
const handleEl = ref<HTMLElement | null>(null);
const dragging = ref(false);

let tip: ModalHandle | null = null;
const pingTooltip = (value: number): void => {
  if (!tooltip || !handleEl.value) return;
  if (tip) {
    tip.setText?.(display(value));
    return;
  }
  tip = openModal({
    kind: "tooltip",
    text: display(value),
    anchor: handleEl.value,
    placement: { side: "top" },
  });
};
const dropTooltip = (): void => {
  tip?.close();
  tip = null;
};

const lo = computed(() => (labels ? 0 : min));
const hi = computed(() => (labels ? labels.length - 1 : max));
const stepped = computed(() => mode === "stepped" || !!labels);

const display = (value: number): string => {
  if (format) return format(value);
  if (labels) return labels[value] ?? "";
  return String(value);
};

const tickValues = computed<number[]>(() => {
  if (!stepped.value) return [];
  if (ticks && ticks.length) return ticks;
  if (labels) return labels.map((_, i) => i);
  const out: number[] = [];
  for (let v = lo.value; v <= hi.value + 1e-9; v += step) out.push(Number(v.toFixed(6)));
  return out;
});

const ratio = computed(() => {
  if (hi.value === lo.value) return 0;
  return Math.min(1, Math.max(0, (modelValue - lo.value) / (hi.value - lo.value)));
});

const percent = computed(() => `${ratio.value * 100}%`);

const trackStyle = computed<Record<string, string>>(() => {
  if (length === undefined) return {};
  const size = typeof length === "number" ? `${length}px` : length;
  return { [orientation === "vertical" ? "height" : "width"]: size };
});

const ratioToValue = (r: number): number => {
  const raw = lo.value + r * (hi.value - lo.value);
  if (stepped.value) {
    if (ticks && ticks.length) {
      return ticks.reduce((a, b) =>
        Math.abs(b - raw) < Math.abs(a - raw) ? b : a,
      );
    }
    const snapped = Math.round((raw - lo.value) / step) * step + lo.value;
    return Math.min(hi.value, Math.max(lo.value, snapped));
  }
  const snapped = step ? Math.round((raw - lo.value) / step) * step + lo.value : raw;
  return Math.min(hi.value, Math.max(lo.value, snapped));
};

const setFromEvent = (e: PointerEvent) => {
  const el = trackEl.value;
  if (!el) return;
  const rect = el.getBoundingClientRect();
  let r: number;
  if (orientation === "vertical") {
    r = 1 - (e.clientY - rect.top) / rect.height;
  } else {
    r = (e.clientX - rect.left) / rect.width;
  }
  r = Math.min(1, Math.max(0, r));
  const v = ratioToValue(r);
  if (v !== modelValue) emit("update:modelValue", v);
  pingTooltip(v);
};

const onPointerDown = (e: PointerEvent) => {
  if (disabled) return;
  dragging.value = true;
  (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  setFromEvent(e);
};

const onPointerMove = (e: PointerEvent) => {
  if (!dragging.value) return;
  setFromEvent(e);
};

const onPointerUp = (e: PointerEvent) => {
  dragging.value = false;
  (e.currentTarget as HTMLElement).releasePointerCapture?.(e.pointerId);
  dropTooltip();
};

const nudge = (dir: number) => {
  const delta = stepped.value ? 1 : step;
  const v = Math.min(hi.value, Math.max(lo.value, modelValue + dir * delta));
  if (v !== modelValue) emit("update:modelValue", v);
};

const onKeydown = (e: KeyboardEvent) => {
  if (disabled) return;
  if (e.key === "ArrowRight" || e.key === "ArrowUp") {
    e.preventDefault();
    nudge(1);
  } else if (e.key === "ArrowLeft" || e.key === "ArrowDown") {
    e.preventDefault();
    nudge(-1);
  }
};

const tickRatio = (v: number) => {
  if (hi.value === lo.value) return 0;
  return ((v - lo.value) / (hi.value - lo.value)) * 100;
};

const onHandleEnter = (): void => {
  if (!dragging.value) pingTooltip(modelValue);
};
const onHandleLeave = (): void => {
  if (!dragging.value) dropTooltip();
};

onBeforeUnmount(dropTooltip);
</script>

<template>
  <div
    :class="[
      'mar-slider',
      `mar-slider-${orientation}`,
      { 'mar-slider-disabled': disabled, 'mar-slider-floating': floating },
    ]"
    role="slider"
    :aria-valuemin="lo"
    :aria-valuemax="hi"
    :aria-valuenow="modelValue"
    :aria-disabled="disabled"
    :tabindex="disabled ? -1 : 0"
    @keydown="onKeydown"
  >
    <span v-if="showValue" class="mar-slider-value">{{ display(modelValue) }}</span>
    <div
      ref="trackEl"
      class="mar-slider-track"
      :style="trackStyle"
      @pointerdown="onPointerDown"
      @pointermove="onPointerMove"
      @pointerup="onPointerUp"
      @pointercancel="onPointerUp"
    >
      <div class="mar-slider-rail"></div>
      <div class="mar-slider-fill" :style="orientation === 'vertical' ? { height: percent } : { width: percent }"></div>
      <div
        v-for="t in tickValues"
        :key="t"
        class="mar-slider-tick"
        :style="orientation === 'vertical' ? { bottom: `${tickRatio(t)}%` } : { left: `${tickRatio(t)}%` }"
      ></div>
      <div
        ref="handleEl"
        class="mar-slider-handle"
        :style="orientation === 'vertical' ? { bottom: percent } : { left: percent }"
        @mouseenter="onHandleEnter"
        @mouseleave="onHandleLeave"
      ></div>
    </div>
  </div>
</template>

<style scoped>
.mar-slider {
  display: flex;
  outline: none;
}

.mar-slider-horizontal {
  width: 100%;
  align-items: center;
  padding: 0.375em 0;
}

.mar-slider-vertical {
  height: 100%;
  justify-content: center;
  padding: 0 0.375em;
}

.mar-slider-floating {
  flex-direction: column-reverse;
  align-items: center;
  gap: 0.375em;
  padding: 0.5em;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
  background: var(--mar-surface-0);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.18);
}

.mar-slider-track {
  position: relative;
  cursor: pointer;
  touch-action: none;
}

.mar-slider-horizontal .mar-slider-track {
  width: 100%;
  height: 0.75em;
  display: flex;
  align-items: center;
}

.mar-slider-vertical .mar-slider-track {
  height: 100%;
  width: 0.75em;
  display: flex;
  justify-content: center;
}

.mar-slider-rail {
  position: absolute;
  background: var(--mar-surface-300);
  border-radius: 9999px;
}

.mar-slider-horizontal .mar-slider-rail {
  left: 0;
  right: 0;
  height: 0.1875em;
}

.mar-slider-vertical .mar-slider-rail {
  top: 0;
  bottom: 0;
  width: 0.1875em;
}

.mar-slider-fill {
  position: absolute;
  background: var(--mar-primary-color);
  border-radius: 9999px;
}

.mar-slider-horizontal .mar-slider-fill {
  left: 0;
  height: 0.1875em;
}

.mar-slider-vertical .mar-slider-fill {
  bottom: 0;
  width: 0.1875em;
}

.mar-slider-tick {
  position: absolute;
  background: var(--mar-surface-0);
  border: 1px solid var(--mar-surface-400);
  border-radius: 9999px;
  width: 0.375em;
  height: 0.375em;
}

.mar-slider-horizontal .mar-slider-tick {
  top: 50%;
  transform: translate(-50%, -50%);
}

.mar-slider-vertical .mar-slider-tick {
  left: 50%;
  transform: translate(-50%, 50%);
}

.mar-slider-handle {
  position: absolute;
  width: 0.75em;
  height: 0.75em;
  background: var(--mar-surface-0);
  border: 2px solid var(--mar-primary-color);
  border-radius: 9999px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
  transition: box-shadow 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-slider-horizontal .mar-slider-handle {
  top: 50%;
  transform: translate(-50%, -50%);
}

.mar-slider-vertical .mar-slider-handle {
  left: 50%;
  transform: translate(-50%, 50%);
}

.mar-slider:focus-visible .mar-slider-handle {
  box-shadow: 0 0 0 3px
    color-mix(in srgb, var(--mar-primary-color), transparent 75%);
}

.mar-slider-disabled {
  opacity: 0.5;
  pointer-events: none;
}

.mar-slider-value {
  flex-shrink: 0;
  align-self: center;
  padding: 0.0909em 0.5455em;
  border-radius: 9999px;
  background: var(--mar-surface-200);
  font-size: var(--mar-text-2xs);
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  color: var(--mar-text-color);
  margin-right: 0.7273em;
  white-space: nowrap;
}

.mar-slider-vertical .mar-slider-value,
.mar-slider-floating .mar-slider-value {
  margin-right: 0;
}
</style>
