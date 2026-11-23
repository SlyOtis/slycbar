<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue";
import MarIconBtn from "../MarIconBtn";
import { postSidebarCycle, deleteSidebarCycle, type MarSidebarCycleEntry } from "../MarSidebar/MarSidebar.vue";

const {
  label,
  width = "18em",
  side = "start",
  head = true,
} = defineProps<{
  /** Heading of the panel. */
  label: string;
  /** Expanded size, which the content is always laid out at whatever the container is doing. */
  width?: string;
  /** Edge the panel sits on. The content pins to the opposite edge, so collapsing slides it out that way. */
  side?: "start" | "end";
  /** Draws the heading row with the collapse control. Turn it off when the host owns the width. */
  head?: boolean;
}>();

/** Open state of the panel, collapsed to nothing when false. */
const open = defineModel<boolean>("open", { default: true });

const rootEl = ref<HTMLElement | null>(null);

const cycle: MarSidebarCycleEntry = {
  el: () => rootEl.value,
  side: () => (side === "start" ? "left" : "right"),
  getCollapsed: () => !open.value,
  close: () => (open.value = false),
  open: () => (open.value = true),
};

onMounted(() => postSidebarCycle(cycle));

onBeforeUnmount(() => deleteSidebarCycle(cycle));
</script>

<template>
  <div
    ref="rootEl"
    class="mar-side-panel"
    :class="[`mar-side-panel-${side}`, { 'mar-side-panel-open': open, 'mar-side-panel-headless': !head }]"
    :style="{ '--mar-side-panel-width': width }"
  >
    <div class="mar-side-panel-content" :inert="!open">
      <div v-if="head" class="mar-side-panel-head">
        <span class="mar-side-panel-title">{{ label }}</span>
        <span class="mar-side-panel-actions"><slot name="actions" /></span>
        <MarIconBtn
          :icon="side === 'start' ? 'chevron-left' : 'chevron-right'"
          :tooltip="label"
          @click="open = false"
        />
      </div>

      <div class="mar-side-panel-body">
        <slot />
      </div>

      <div v-if="$slots.footer" class="mar-side-panel-foot">
        <slot name="footer" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.mar-side-panel {
  --mar-side-panel-size: 0em;
  position: relative;
  display: grid;
  grid-template-columns: var(--mar-side-panel-size);
  flex: none;
  min-height: 0;
  overflow: hidden;
  background: var(--mar-surface-0);
  transition: grid-template-columns 0.2s ease;
  will-change: grid-template-columns;
}

.mar-side-panel-open {
  --mar-side-panel-size: calc(var(--mar-side-panel-width) - 1px);
  border-inline-end: 1px solid var(--mar-content-border-color);
}

.mar-side-panel-headless {
  flex: 1;
  grid-template-columns: 100%;
  width: 100%;
  min-width: 0;
  transition: none;
  will-change: auto;
}

.mar-side-panel-end.mar-side-panel-open {
  border-inline-end: none;
  border-inline-start: 1px solid var(--mar-content-border-color);
}

.mar-side-panel-content {
  position: absolute;
  inset-block: 0;
  inset-inline-end: 0;
  display: flex;
  flex-direction: column;
  width: var(--mar-side-panel-width);
  min-height: 0;
}

.mar-side-panel-end .mar-side-panel-content {
  inset-inline-end: auto;
  inset-inline-start: 0;
}

.mar-side-panel-head {
  display: flex;
  flex: none;
  align-items: center;
  gap: 0.5em;
  padding: 0.375em 0.5em 0.375em 0.75em;
  border-bottom: 1px solid var(--mar-content-border-color);
}

.mar-side-panel-title {
  flex: 1;
  overflow: hidden;
  font-size: var(--mar-text-xs);
  font-weight: 600;
  white-space: nowrap;
  text-overflow: ellipsis;
}

.mar-side-panel-actions {
  display: inline-flex;
  align-items: center;
  gap: 0.25em;
}

.mar-side-panel-body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
}

.mar-side-panel-foot {
  flex: none;
  border-top: 1px solid var(--mar-content-border-color);
}
</style>
