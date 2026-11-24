<script setup lang="ts">
import { computed } from "vue";
import {
  NodeViewContent,
  NodeViewWrapper,
} from "@/blockedit/render/views/nodeViewBridge.ts";
import type { MarMediaAsset, MarMediaKind } from "@/types/media.types";
import MarIcon from "../MarIcon";

const props = defineProps<{
  /** Block node whose options carry the image sources, the grid size, the gutter, and the corner radius. */
  node: {
    options: {
      images?: string[];
      columns?: number;
      rows?: number;
      gap?: number;
      radius?: number;
      showTitle?: boolean;
      titleSize?: "sm" | "md" | "lg" | "xl";
    };
  };
  /** Editor context; an editable editor makes every cell open the host picker. */
  editor?: { isEditable: boolean };
  /** Draws a selection outline around the block. */
  selected: boolean;
  /** Callback persisting the image edits back into the document. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
  /** Extension options wiring the media dialog the host opens for a cell. */
  extension: {
    options: {
      requestMedia?: (
        kind: MarMediaKind,
        current?: string,
      ) => Promise<MarMediaAsset | null>;
    };
  };
}>();

const editable = computed(() => props.editor?.isEditable ?? true);
const columns = computed(() => Math.min(6, Math.max(1, Number(props.node.options.columns) || 3)));
const rows = computed(() => Math.min(6, Math.max(1, Number(props.node.options.rows) || 2)));
const gap = computed(() => Math.max(0, Number(props.node.options.gap) || 0));
const radius = computed(() => Math.max(0, Number(props.node.options.radius) || 0));
const showTitle = computed(() => props.node.options.showTitle !== false);
const titleSize = computed(() => props.node.options.titleSize ?? "md");

const images = computed(() =>
  Array.isArray(props.node.options.images) ? (props.node.options.images as string[]) : [],
);

const cells = computed(() =>
  Array.from(
    { length: columns.value * rows.value },
    (_, index) => images.value[index] ?? "",
  ),
);

const onPick = async (index: number): Promise<void> => {
  const request = props.extension.options.requestMedia;
  if (!request) return;
  const asset = await request("image", cells.value[index] ?? "");
  if (!asset) return;
  const next = [...cells.value];
  next[index] = asset.url;
  props.updateAttributes({ images: next });
};
</script>

<template>
  <NodeViewWrapper
    :class="['mar-be-image-grid', { 'mar-be-image-grid-selected': selected }]"
  >
    <NodeViewContent
      v-if="showTitle"
      :class="['mar-be-image-grid-title', `mar-be-image-grid-title-${titleSize}`]"
    />
    <div
      class="mar-be-image-grid-grid"
      contenteditable="false"
      :style="{
        gridTemplateColumns: `repeat(${columns}, 1fr)`,
        gap: `${gap}px`,
      }"
    >
      <component
        :is="editable ? 'button' : 'div'"
        v-for="(image, index) in cells"
        :key="index"
        :type="editable ? 'button' : undefined"
        class="mar-be-image-grid-cell"
        :class="{ 'mar-be-image-grid-cell-empty': !image }"
        :style="{ borderRadius: `${radius}px` }"
        @click="editable ? onPick(index) : undefined"
      >
        <img v-if="image" :src="image" alt="" />
        <MarIcon v-else-if="editable" icon="plus" />
      </component>
    </div>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-image-grid {
  display: flex;
  flex-direction: column;
  gap: 0.625em;
  margin: 0.5em 0;
}

.mar-be-image-grid-selected {
  outline: 1px solid var(--mar-surface-400);
  outline-offset: 3px;
}

.mar-be-image-grid-title {
  font-weight: 600;
  color: var(--mar-text-color);
}

.mar-be-image-grid-title-sm {
  font-size: 0.875em;
}

.mar-be-image-grid-title-md {
  font-size: 1.125em;
}

.mar-be-image-grid-title-lg {
  font-size: 1.5em;
}

.mar-be-image-grid-title-xl {
  font-size: 2em;
}

.mar-be-image-grid-title :deep(p) {
  margin: 0;
}

.mar-be-image-grid-grid {
  display: grid;
}

.mar-be-image-grid-cell {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  aspect-ratio: 4 / 3;
  padding: 0;
  overflow: hidden;
  border: none;
  background: none;
  color: var(--mar-surface-500);
}

.mar-be-image-grid .mar-be-image-grid-cell img {
  display: block;
  width: 100%;
  height: 100%;
  max-width: none;
  margin: 0;
  object-fit: cover;
  border-radius: inherit;
}

button.mar-be-image-grid-cell {
  cursor: pointer;
}

button.mar-be-image-grid-cell .mar-icon {
  font-size: 1.2em;
}

.mar-be-image-grid-cell-empty {
  background: var(--mar-surface-100);
}

button.mar-be-image-grid-cell:hover {
  color: var(--mar-primary-color);
}

button.mar-be-image-grid-cell-empty:hover {
  background: var(--mar-surface-200);
}
</style>
