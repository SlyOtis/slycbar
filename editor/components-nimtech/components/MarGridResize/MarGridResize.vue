<script setup lang="ts">
import { ref } from "vue";
import type { MarGridResizeAlign } from "./marGridResize.types";

const {
  align,
  target,
  variable,
  min = 0,
  max,
} = defineProps<{
  /** Edge of the containing cell the handle pins to, deciding the resize axis and cursor. */
  align: MarGridResizeAlign;
  /** CSS selector of the element that is measured and receives the variable. */
  target: string;
  /** CSS custom property name written on the target as a pixel value. */
  variable: string;
  /**
   * Lower clamp of the size in pixels.
   * @minimum 0
   */
  min?: number;
  /**
   * Upper clamp of the size in pixels, defaulting to the current width or height of the target.
   * @minimum 0
   */
  max?: number;
}>();

const emit = defineEmits<{ resize: [value: number] }>();

const dragging = ref(false);

function horizontal() {
  return align === "left" || align === "right";
}

function sizeFrom(rect: DOMRect, x: number, y: number) {
  if (align === "left") return x - rect.left;
  if (align === "right") return rect.right - x;
  if (align === "top") return y - rect.top;
  return rect.bottom - y;
}

function apply(x: number, y: number) {
  const el = document.querySelector<HTMLElement>(target);
  if (!el) return;
  const rect = el.getBoundingClientRect();
  const upper = max ?? (horizontal() ? rect.width : rect.height);
  const size = Math.min(Math.max(sizeFrom(rect, x, y), min), upper);
  el.style.setProperty(variable, `${size}px`);
  emit("resize", size);
}

function move(e: PointerEvent) {
  apply(e.clientX, e.clientY);
}

function up() {
  dragging.value = false;
  window.removeEventListener("pointermove", move);
  window.removeEventListener("pointerup", up);
  document.body.style.removeProperty("user-select");
  document.body.style.removeProperty("cursor");
}

function down(e: PointerEvent) {
  e.preventDefault();
  dragging.value = true;
  document.body.style.setProperty("user-select", "none");
  document.body.style.setProperty("cursor", horizontal() ? "col-resize" : "row-resize");
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", up);
}
</script>

<template>
  <div
    :class="[
      'mar-grid-resize',
      `mar-grid-resize-${align}`,
      { 'mar-grid-resize-dragging': dragging },
    ]"
    @pointerdown="down"
  ></div>
</template>

<style scoped>
.mar-grid-resize {
  position: absolute;
  z-index: 2;
  touch-action: none;
}

.mar-grid-resize::before {
  content: "";
  position: absolute;
  inset: 0;
  margin: auto;
  background: var(--mar-content-border-color);
  transition: background 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-grid-resize:hover::before,
.mar-grid-resize-dragging::before {
  background: var(--mar-primary-color);
}

.mar-grid-resize-left,
.mar-grid-resize-right {
  top: 0;
  bottom: 0;
  width: 0.625em;
  cursor: col-resize;
}

.mar-grid-resize-left::before,
.mar-grid-resize-right::before {
  width: 1px;
  height: 100%;
}

.mar-grid-resize-top,
.mar-grid-resize-bottom {
  left: 0;
  right: 0;
  height: 0.625em;
  cursor: row-resize;
}

.mar-grid-resize-top::before,
.mar-grid-resize-bottom::before {
  height: 1px;
  width: 100%;
}

.mar-grid-resize-left {
  left: 0;
  transform: translateX(-50%);
}

.mar-grid-resize-right {
  right: 0;
  transform: translateX(50%);
}

.mar-grid-resize-top {
  top: 0;
  transform: translateY(-50%);
}

.mar-grid-resize-bottom {
  bottom: 0;
  transform: translateY(50%);
}
</style>
