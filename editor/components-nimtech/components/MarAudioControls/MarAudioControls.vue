<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import MarIcon from "../MarIcon";
import MarSliderInput from "../MarSliderInput";

const props = defineProps<{
  /** Whether playback is currently running, toggling the play and pause icon. */
  playing: boolean;
  /** Elapsed playback time in seconds, shown left of the duration. @minimum 0 */
  currentTime: number;
  /** Total track length in seconds, shown right of the elapsed time. @minimum 0 */
  duration: number;
  /** Current volume as a fraction, zero renders the muted icon. @minimum 0 @maximum 1 */
  volume: number;
  /** Waveform peak heights as fractions of full bar height. @minimum 0 @maximum 1 */
  peaks: number[];
  /** Played share of the waveform, bars at or below it render as played. @minimum 0 @maximum 1 */
  progress: number;
  /** Renders the clickable waveform strip driven by peaks and progress. */
  showWaveform?: boolean;
  /** Renders the 15 second back and forward skip buttons. */
  showSkip?: boolean;
}>();

const emit = defineEmits<{
  toggle: [];
  skip: [delta: number];
  seek: [ratio: number];
  "update:volume": [value: number];
}>();

const volumeOpen = ref(false);
const rootEl = ref<HTMLElement | null>(null);

const togglePlay = () => {
  rootEl.value?.focus();
  emit("toggle");
};

const formatTime = (t: number): string => {
  if (!isFinite(t)) return "0:00";
  const m = Math.floor(t / 60);
  const s = Math.floor(t % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
};

const vol = computed({
  get: () => props.volume,
  set: (v: number) => emit("update:volume", v),
});

const onWaveformClick = (e: MouseEvent) => {
  const el = e.currentTarget as HTMLElement;
  const rect = el.getBoundingClientRect();
  emit("seek", (e.clientX - rect.left) / rect.width);
  rootEl.value?.focus();
};

const closeVolume = (e: MouseEvent) => {
  if (!volumeOpen.value) return;
  if (!(e.target as HTMLElement).closest(".mar-audio-controls-volume")) {
    volumeOpen.value = false;
  }
};

onMounted(() => document.addEventListener("pointerdown", closeVolume));
onBeforeUnmount(() => document.removeEventListener("pointerdown", closeVolume));
</script>

<template>
  <div ref="rootEl" class="mar-audio-controls" tabindex="0" @keydown.space.prevent="togglePlay">
    <button type="button" class="mar-audio-controls-btn mar-audio-controls-play" @click="togglePlay">
      <MarIcon :icon="playing ? 'pause' : 'play'" />
    </button>
    <button
      v-if="showSkip"
      type="button"
      class="mar-audio-controls-btn"
      title="Back 15 seconds"
      @click="emit('skip', -15)"
    >
      <MarIcon icon="undo" /><span class="mar-audio-controls-15">15</span>
    </button>
    <button
      v-if="showSkip"
      type="button"
      class="mar-audio-controls-btn"
      title="Forward 15 seconds"
      @click="emit('skip', 15)"
    >
      <span class="mar-audio-controls-15">15</span><MarIcon icon="redo" />
    </button>
    <div v-if="showWaveform" class="mar-audio-controls-waveform" @click="onWaveformClick">
      <span
        v-for="(p, i) in peaks"
        :key="i"
        :class="['mar-audio-controls-bar', { 'mar-audio-controls-bar-played': peaks.length ? i / peaks.length <= progress : false }]"
        :style="{ height: `${Math.max(8, Math.min(1, p) * 100)}%` }"
      ></span>
    </div>
    <span class="mar-audio-controls-time">{{ formatTime(currentTime) }} / {{ formatTime(duration) }}</span>
    <div class="mar-audio-controls-volume">
      <button
        type="button"
        class="mar-audio-controls-btn"
        :title="volume === 0 ? 'unmute' : 'volume'"
        @click.stop="volumeOpen = !volumeOpen"
      >
        <MarIcon :icon="volume === 0 ? 'volume-off' : 'volume-up'" />
      </button>
      <div v-if="volumeOpen" class="mar-audio-controls-volume-pop">
        <MarSliderInput v-model="vol" orientation="vertical" :min="0" :max="1" :step="0.01" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.mar-audio-controls {
  display: flex;
  align-items: center;
  gap: 0.5em;
  min-width: 0;
}

.mar-audio-controls-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.075em;
  font-size: 0.8334em;
  border: none;
  background: transparent;
  color: var(--mar-surface-700);
  cursor: pointer;
  border-radius: 5px;
  padding: 0.3em;
  flex-shrink: 0;
}

.mar-audio-controls-btn > .mar-icon {
  font-size: 1.2em;
}

.mar-audio-controls-btn:hover {
  background: var(--mar-surface-200);
  color: var(--mar-text-color);
}

.mar-audio-controls-play {
  color: var(--mar-primary-color);
}

.mar-audio-controls-15 {
  font-size: 0.675em;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

.mar-audio-controls-waveform {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 0.0625em;
  height: 2em;
  cursor: pointer;
}

.mar-audio-controls-bar {
  flex: 1;
  min-width: 0.0625em;
  border-radius: 9999px;
  background: var(--mar-surface-300);
}

.mar-audio-controls-bar-played {
  background: var(--mar-primary-color);
}

.mar-audio-controls-time {
  font-size: 0.6875em;
  font-variant-numeric: tabular-nums;
  color: var(--mar-surface-600);
  flex-shrink: 0;
}

.mar-audio-controls-volume {
  position: relative;
  flex-shrink: 0;
}

.mar-audio-controls-volume-pop {
  position: absolute;
  bottom: calc(100% + 0.25em);
  left: 50%;
  transform: translateX(-50%);
  height: 6em;
  padding: 0.5em 0.25em;
  background: var(--mar-surface-0);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.15);
  z-index: 10;
}
</style>
