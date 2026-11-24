<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import {
  NodeViewContent,
  NodeViewWrapper,
} from "@/blockedit/render/views/nodeViewBridge.ts";

interface CountdownLabels {
  days: string;
  hours: string;
  minutes: string;
  seconds: string;
}

const props = defineProps<{
  /** Block node whose options carry the target instant as an ISO string. */
  node: {
    options: {
      target?: string;
      mode?: "stacked" | "inline";
      background?: string;
      backgroundImage?: string;
    };
  };
  /** Draws a selection outline around the block. */
  selected: boolean;
  /** Extension options carrying the unit labels the host translates. */
  extension: { options: { labels?: CountdownLabels } };
}>();

const defaultLabels: CountdownLabels = {
  days: "Days",
  hours: "Hours",
  minutes: "Minutes",
  seconds: "Seconds",
};

const labels = computed(() => props.extension.options.labels ?? defaultLabels);
const mode = computed(() => props.node.options.mode ?? "stacked");
const background = computed(() => String(props.node.options.background ?? "none"));

const backgroundColor = computed(() =>
  background.value === "none" ? undefined : `var(--mar-${background.value})`,
);

const dark = computed(() => {
  const step = Number(background.value.split("-")[1]);
  return Number.isFinite(step) && step >= 500;
});
const backgroundImage = computed(() => String(props.node.options.backgroundImage ?? ""));

const target = computed(() => {
  const raw = props.node.options.target;
  if (!raw) return null;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? null : date;
});

const now = ref(Date.now());
let tick: number | undefined;

onMounted(() => {
  tick = window.setInterval(() => {
    now.value = Date.now();
  }, 1000);
});

onBeforeUnmount(() => {
  window.clearInterval(tick);
});

const remaining = computed(() => {
  if (!target.value) return 0;
  return Math.max(0, target.value.getTime() - now.value);
});

const pad = (value: number): string => String(value).padStart(2, "0");

const units = computed(() => {
  const total = Math.floor(remaining.value / 1000);
  return [
    { key: "days", value: pad(Math.floor(total / 86400)), label: labels.value.days },
    { key: "hours", value: pad(Math.floor(total / 3600) % 24), label: labels.value.hours },
    { key: "minutes", value: pad(Math.floor(total / 60) % 60), label: labels.value.minutes },
    { key: "seconds", value: pad(total % 60), label: labels.value.seconds },
  ];
});
</script>

<template>
  <NodeViewWrapper
    :class="[
      'mar-be-countdown',
      `mar-be-countdown-${mode}`,
      {
        'mar-be-countdown-selected': selected,
        'mar-be-countdown-image': backgroundImage,
        'mar-be-countdown-dark': dark,
      },
    ]"
    :style="{
      backgroundColor,
      backgroundImage: backgroundImage ? `url(${backgroundImage})` : undefined,
    }"
  >
    <NodeViewContent class="mar-be-countdown-title" />
    <div class="mar-be-countdown-units" contenteditable="false">
      <div
        v-for="unit in units"
        :key="unit.key"
        class="mar-be-countdown-unit"
      >
        <span class="mar-be-countdown-value">{{ unit.value }}</span>
        <span class="mar-be-countdown-label">{{ unit.label }}</span>
      </div>
    </div>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-countdown {
  display: flex;
  align-items: center;
  justify-content: center;
  margin: 0.5em 0;
  padding: 2em 1em;
  color: var(--mar-text-color);
  text-align: center;
  background-size: cover;
  background-position: center;
}

.mar-be-countdown-stacked {
  flex-direction: column;
  gap: 1.25em;
}

.mar-be-countdown-inline {
  flex-direction: row;
  flex-wrap: wrap;
  gap: 2em;
}

.mar-be-countdown-dark {
  color: var(--mar-overlay-color);
}

.mar-be-countdown-image {
  background-color: var(--mar-overlay-backdrop);
  background-blend-mode: darken;
  color: var(--mar-overlay-color);
  text-shadow: var(--mar-overlay-text-shadow);
}

.mar-be-countdown-selected {
  outline: 1px solid var(--mar-surface-400);
  outline-offset: 3px;
}

.mar-be-countdown-title {
  font-size: 2em;
  font-weight: 700;
  line-height: 1.2;
}

.mar-be-countdown-stacked .mar-be-countdown-title {
  width: 100%;
}

.mar-be-countdown-title :deep(p) {
  margin: 0;
}

.mar-be-countdown-units {
  display: flex;
  align-items: flex-start;
  gap: 2.5em;
}

.mar-be-countdown-unit {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.375em;
}

.mar-be-countdown-value {
  font-size: 2.25em;
  font-weight: 700;
  line-height: 1;
  font-variant-numeric: tabular-nums;
}

.mar-be-countdown-label {
  font-size: 0.6875em;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--mar-surface-500);
}

.mar-be-countdown-inline .mar-be-countdown-units {
  gap: 1.5em;
}

.mar-be-countdown-dark .mar-be-countdown-label,
.mar-be-countdown-image .mar-be-countdown-label {
  color: var(--mar-overlay-muted-color);
}
</style>
