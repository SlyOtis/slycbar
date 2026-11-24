<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import type { RemotePeer } from "../collab/awareness";

const { peers, host } = defineProps<{
  peers: RemotePeer[];
  host?: HTMLElement | null;
}>();

interface CursorBox {
  clientId: number;
  name: string;
  color: string;
  top: number;
  left: number;
  height: number;
}

const boxes = ref<CursorBox[]>([]);
let raf = 0;

const measure = (): void => {
  const container = host ?? document.body;
  const containerRect = container.getBoundingClientRect();
  const next: CursorBox[] = [];
  for (const peer of peers) {
    if (!peer.selection) continue;
    const el = container.querySelector<HTMLElement>(
      `[data-block-id="${peer.selection.blockId}"]`,
    );
    if (!el) continue;
    const rect = el.getBoundingClientRect();
    next.push({
      clientId: peer.clientId,
      name: peer.user.name,
      color: peer.user.color,
      top: rect.top - containerRect.top,
      left: rect.left - containerRect.left,
      height: rect.height,
    });
  }
  boxes.value = next;
};

const schedule = (): void => {
  cancelAnimationFrame(raf);
  raf = requestAnimationFrame(measure);
};

const peersKey = computed(() =>
  peers.map((p) => `${p.clientId}:${p.selection?.blockId ?? ""}`).join("|"),
);

onMounted(() => {
  schedule();
  window.addEventListener("resize", schedule);
});

onBeforeUnmount(() => {
  cancelAnimationFrame(raf);
  window.removeEventListener("resize", schedule);
});

defineExpose({ refresh: schedule });

let lastKey = "";
setInterval(() => {
  if (peersKey.value !== lastKey) {
    lastKey = peersKey.value;
    schedule();
  }
}, 250);
</script>

<template>
  <div class="mar-remote-cursors" aria-hidden="true">
    <div
      v-for="box in boxes"
      :key="box.clientId"
      class="mar-remote-cursor"
      :style="{
        top: box.top + 'px',
        left: box.left + 'px',
        height: box.height + 'px',
        borderColor: box.color,
      }"
    >
      <span class="mar-remote-cursor-label" :style="{ background: box.color }">
        {{ box.name }}
      </span>
    </div>
  </div>
</template>

<style scoped>
.mar-remote-cursors {
  position: absolute;
  inset: 0;
  pointer-events: none;
  z-index: 5;
}

.mar-remote-cursor {
  position: absolute;
  border-left: 2px solid;
  padding-left: 2px;
}

.mar-remote-cursor-label {
  position: absolute;
  top: -1.76em;
  left: -2px;
  color: var(--mar-overlay-color);
  font-size: 0.7143em;
  line-height: 1;
  padding: 0.24em 0.48em;
  border-radius: 3px;
  white-space: nowrap;
}
</style>
