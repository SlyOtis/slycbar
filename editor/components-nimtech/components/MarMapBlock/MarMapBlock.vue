<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import MarMap from "../MarMap";

const props = defineProps<{
  /** Editor node whose options carry the latitude, longitude, zoom, label, address, variant, and interactive flag. */
  node: {
    options: {
      lat?: number | null;
      lng?: number | null;
      zoom?: number;
      label?: string;
      address?: string;
      variant?: "inline" | "card";
      interactive?: boolean;
    };
  };
  /** Draws a subtle outline around the block when selected. */
  selected: boolean;
  /** Accepted for the node view contract but unused by this block. */
  editor?: { isEditable: boolean };
}>();

const a = computed(() => props.node.options);

const lat = computed(() => (a.value.lat == null ? null : Number(a.value.lat)));
const lng = computed(() => (a.value.lng == null ? null : Number(a.value.lng)));
const zoom = computed(() => Number(a.value.zoom ?? 13));
const label = computed(() => String(a.value.label ?? ""));
const address = computed(() => String(a.value.address ?? ""));
const variant = computed(() =>
  a.value.variant === "card" ? "card" : "inline",
);
const interactive = computed(() => a.value.interactive === true);
</script>

<template>
  <NodeViewWrapper
    class="mar-be-map"
    :class="{ 'mar-be-map-selected': selected }"
    contenteditable="false"
  >
    <MarMap
      :lat="lat"
      :lng="lng"
      :zoom="zoom"
      :label="label"
      :address="address"
      :variant="variant"
      :interactive="interactive"
    />
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-map {
  width: 100%;
  margin: 0.5em 0;
  border-radius: 10px;
}

.mar-be-map-selected {
  outline: 1px solid var(--mar-surface-400);
}
</style>
