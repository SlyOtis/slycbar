<script setup lang="ts">
import { computed } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import MarWeather from "../MarWeather";

const props = defineProps<{
  /** Editor node whose options carry the coordinates, the address, the label, the variant, the strip, and the cell count. */
  node: {
    options: {
      lat?: number | null;
      lng?: number | null;
      address?: string;
      label?: string;
      variant?: "card" | "inline";
      forecast?: "none" | "hours" | "days";
      count?: number;
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
const address = computed(() => String(a.value.address ?? ""));
const label = computed(() => String(a.value.label ?? ""));
const variant = computed(() => (a.value.variant === "inline" ? "inline" : "card"));
const forecast = computed(() =>
  a.value.forecast === "days" || a.value.forecast === "none"
    ? a.value.forecast
    : "hours",
);
const count = computed(() => Number(a.value.count ?? 6));
</script>

<template>
  <NodeViewWrapper
    class="mar-be-weather"
    :class="{ 'mar-be-weather-selected': selected }"
    contenteditable="false"
  >
    <MarWeather
      :lat="lat"
      :lng="lng"
      :address="address"
      :label="label"
      :variant="variant"
      :forecast="forecast"
      :count="count"
    />
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-weather {
  width: 100%;
  margin: 0.5em 0;
  border-radius: 10px;
}

.mar-be-weather-selected {
  outline: 1px solid var(--mar-surface-400);
}
</style>
