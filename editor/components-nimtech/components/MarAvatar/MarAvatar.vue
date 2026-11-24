<script setup lang="ts">
import { computed, ref, watch } from "vue";
import MarIcon from "../MarIcon";
import MarImage from "../MarImage";
import { useOrganicClip } from "@/composables/useOrganicClip";
import { fileMatchesAccept } from "@/utils/fileAccept";
import type { OrganicPathEdge } from "@/utils/organicPath";
import type { IconType } from "@/types/icon.types";

export type MarAvatarShape = "circle" | "square" | "organic";

const {
  src,
  placeholder,
  label,
  icon,
  scale = false,
  shape = "circle",
  wobble,
  inset,
  points,
  rectangular,
  edges,
  seed,
  editable,
  accept = "image/*",
} = defineProps<{
  /** Image URL that wins over icon and initials while it loads; a failing source falls back. */
  src?: string | null;
  /** Low resolution source rendered blurred under the image until it loads. */
  placeholder?: string | null;
  /** Person name supplying the alt text, hover title, initials fallback, and the deterministic initials background hue. */
  label?: string;
  /** Glyph shown when no image is set. */
  icon?: string;
  /** Drops the default box so the avatar fills the element containing it. */
  scale?: boolean;
  /** Circle, square, or organic clipped form. */
  shape?: MarAvatarShape;
  /**
   * Organic edge wobble amount as a fraction of the box size.
   * @minimum 0
   * @maximum 1
   */
  wobble?: number;
  /**
   * Organic inset from the box edge as a fraction of the box size.
   * @minimum 0
   * @maximum 1
   */
  inset?: number;
  /** Number of control points on the organic path. */
  points?: number;
  /** Wobbles the edges of a rectangle instead of an ellipse blob. */
  rectangular?: boolean;
  /** Which rectangle edges wobble in rectangular mode. */
  edges?: OrganicPathEdge | OrganicPathEdge[] | "vertical" | "horizontal";
  /** Fixes the organic geometry so equal seeds render identical shapes. */
  seed?: number;
  /** Turns the avatar into an image change target: clicking opens a file picker, a dragged image drops onto it, and the picked file arrives on the change emit. */
  editable?: boolean;
  /** Accept pattern constraining the picker and dropped files in editable mode. */
  accept?: string;
}>();

const emit = defineEmits<{
  change: [file: File];
}>();

const rootEl = ref<HTMLElement | null>(null);

const clipPath = useOrganicClip(rootEl, {
  active: () => shape === "organic",
  path: () => ({ wobble, inset, points, rectangular, edges }),
  seed: () => seed,
});

const errored = ref(false);

watch(
  () => src,
  () => {
    errored.value = false;
  },
);

const showImage = computed(() => !!src && !errored.value);

const initials = computed(() => {
  if (!label) return "";
  const parts = label.trim().split(/\s+/);
  const first = parts[0] ?? "";
  if (parts.length === 1) return first.slice(0, 2).toUpperCase();
  const last = parts[parts.length - 1] ?? "";
  return ((first[0] ?? "") + (last[0] ?? "")).toUpperCase();
});

const showInitials = computed(
  () => !showImage.value && !icon && initials.value !== "",
);

const labelColor = computed(() => {
  if (!label) return "";
  let hash = 0;
  for (let i = 0; i < label.length; i++) {
    hash = ((hash << 5) - hash + label.charCodeAt(i)) | 0;
  }
  const hue = Math.abs(hash) % 360;
  return `hsl(${hue}, 55%, 55%)`;
});

const rootStyle = computed(() => {
  const style: Record<string, string> = {};
  if (clipPath.value) style.clipPath = clipPath.value;
  if (showInitials.value) {
    style.backgroundColor = labelColor.value;
    style.color = "var(--mar-overlay-color)";
  }
  return style;
});

const inputEl = ref<HTMLInputElement | null>(null);
const dragDepth = ref(0);

const pick = (e: Event) => {
  if (!editable) return;
  e.stopPropagation();
  inputEl.value?.click();
};

const onInputChange = (e: Event) => {
  const target = e.target as HTMLInputElement;
  const file = target.files?.[0];
  if (file && fileMatchesAccept(file, accept)) emit("change", file);
  target.value = "";
};

const onDragEnter = () => {
  if (editable) dragDepth.value++;
};

const onDragLeave = () => {
  if (editable && dragDepth.value > 0) dragDepth.value--;
};

const onDrop = (e: DragEvent) => {
  if (!editable) return;
  e.stopPropagation();
  dragDepth.value = 0;
  const file = e.dataTransfer?.files?.[0];
  if (file && fileMatchesAccept(file, accept)) emit("change", file);
};

const classes = computed(() => [
  "mar-avatar",
  `mar-avatar-${shape}`,
  {
    "mar-avatar-scale": scale,
    "mar-avatar-editable": editable,
    "mar-avatar-drag": editable && dragDepth.value > 0,
  },
]);
</script>

<template>
  <span
    ref="rootEl"
    :class="classes"
    :style="rootStyle"
    :title="label ?? undefined"
    :role="editable ? 'button' : undefined"
    :tabindex="editable ? 0 : undefined"
    @click="pick"
    @keydown.enter="pick"
    @keydown.space.prevent="pick"
    @dragenter.prevent="onDragEnter"
    @dragover.prevent
    @dragleave.prevent="onDragLeave"
    @drop.prevent="onDrop"
  >
    <MarImage
      v-if="showImage"
      class="mar-avatar-img"
      :src="src"
      :placeholder="placeholder"
      :alt="label ?? ''"
      @error="errored = true"
    />
    <MarIcon v-else-if="icon" :icon="(icon as IconType)" class="mar-avatar-icon" />
    <span v-else-if="initials" class="mar-avatar-initials">{{ initials }}</span>
    <span v-if="editable" class="mar-avatar-edit">
      <MarIcon icon="camera" class="mar-avatar-edit-icon" />
    </span>
    <input
      v-if="editable"
      ref="inputEl"
      type="file"
      class="mar-avatar-input"
      :accept="accept"
      @change="onInputChange"
      @click.stop
    />
  </span>
</template>

<style scoped>
.mar-avatar {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  inline-size: 1.625em;
  block-size: 1.625em;
  max-inline-size: 100%;
  background: var(--mar-surface-200);
  color: var(--mar-surface-700);
  overflow: hidden;
  font-weight: 600;
  flex-shrink: 0;
  user-select: none;
}

.mar-avatar-circle {
  border-radius: 50%;
}

.mar-avatar-square {
  border-radius: 0.3125em;
}

.mar-avatar-organic {
  border-radius: 0;
}

.mar-avatar-scale {
  inline-size: 100%;
  block-size: 100%;
}

.mar-avatar-img {
  width: 100%;
  height: 100%;
}

.mar-avatar-initials {
  font-size: 0.6875em;
}

.mar-avatar-icon {
  font-size: 1em;
}

.mar-avatar-scale .mar-avatar-initials,
.mar-avatar-scale .mar-avatar-icon,
.mar-avatar-scale .mar-avatar-edit-icon {
  font-size: 1.375em;
}

.mar-avatar-editable {
  position: relative;
  cursor: pointer;
}

.mar-avatar-editable > * {
  pointer-events: none;
}

.mar-avatar-edit {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: color-mix(in srgb, var(--mar-surface-950), transparent 55%);
  color: var(--mar-surface-0);
  opacity: 0;
  transition: opacity 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-avatar-editable:hover .mar-avatar-edit,
.mar-avatar-editable:focus-visible .mar-avatar-edit,
.mar-avatar-drag .mar-avatar-edit {
  opacity: 1;
}

.mar-avatar-drag .mar-avatar-edit {
  background: color-mix(in srgb, var(--mar-primary-color), transparent 35%);
}

.mar-avatar-edit-icon {
  font-size: 1em;
}

.mar-avatar-input {
  display: none;
}
</style>
