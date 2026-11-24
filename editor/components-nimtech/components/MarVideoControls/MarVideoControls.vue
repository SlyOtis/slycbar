<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import MarIcon from "../MarIcon";
import MarSliderInput from "../MarSliderInput";

const {
  src,
  poster = null,
  autoplay = false,
  loop = false,
  muted = false,
} = defineProps<{
  /** Video url bound to the native element. */
  src: string;
  /** Poster frame shown before playback. */
  poster?: string | null;
  /** Plays on mount. */
  autoplay?: boolean;
  /** Restarts playback when it ends. */
  loop?: boolean;
  /** Starts muted. */
  muted?: boolean;
}>();

const emit = defineEmits<{ ended: [] }>();

const videoEl = ref<HTMLVideoElement | null>(null);
const rootEl = ref<HTMLElement | null>(null);
const playing = ref(false);
const currentTime = ref(0);
const duration = ref(0);
const volume = ref(1);
const volumeOpen = ref(false);

const progress = computed(() =>
  duration.value ? currentTime.value / duration.value : 0,
);

const formatTime = (t: number): string => {
  if (!isFinite(t)) return "0:00";
  const m = Math.floor(t / 60);
  const s = Math.floor(t % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
};

const toggle = () => {
  const v = videoEl.value;
  if (!v) return;
  if (v.paused) v.play();
  else v.pause();
  rootEl.value?.focus();
};

const onTime = () => {
  const v = videoEl.value;
  if (v) currentTime.value = v.currentTime;
};

const onMeta = () => {
  const v = videoEl.value;
  if (v) duration.value = v.duration;
};

const skip = (delta: number) => {
  const v = videoEl.value;
  if (!v) return;
  v.currentTime = Math.max(0, Math.min(duration.value, v.currentTime + delta));
};

const onSeek = (e: MouseEvent) => {
  const el = e.currentTarget as HTMLElement;
  const rect = el.getBoundingClientRect();
  const v = videoEl.value;
  if (!v || !duration.value) return;
  v.currentTime = ((e.clientX - rect.left) / rect.width) * duration.value;
};

const vol = computed({
  get: () => volume.value,
  set: (x: number) => {
    volume.value = x;
    if (videoEl.value) videoEl.value.volume = x;
  },
});

const fullscreen = () => videoEl.value?.requestFullscreen();

const closeVolume = (e: MouseEvent) => {
  if (!volumeOpen.value) return;
  if (!(e.target as HTMLElement).closest(".mar-video-controls-volume")) {
    volumeOpen.value = false;
  }
};

watch(
  () => src,
  () => {
    playing.value = false;
    currentTime.value = 0;
    duration.value = 0;
  },
);

onMounted(() => document.addEventListener("pointerdown", closeVolume));
onBeforeUnmount(() => {
  document.removeEventListener("pointerdown", closeVolume);
  videoEl.value?.pause();
});
</script>

<template>
  <div
    ref="rootEl"
    class="mar-video-controls"
    tabindex="0"
    @keydown.space.prevent="toggle"
  >
    <div class="mar-video-controls-stage">
      <video
        ref="videoEl"
        :src="src"
        :poster="poster ?? undefined"
        :autoplay="autoplay"
        :loop="loop"
        :muted="muted"
        playsinline
        preload="metadata"
        class="mar-video-controls-video"
        @timeupdate="onTime"
        @loadedmetadata="onMeta"
        @play="playing = true"
        @pause="playing = false"
        @ended="emit('ended')"
        @click="toggle"
      />
    </div>
    <div class="mar-video-controls-bar">
      <button
        type="button"
        class="mar-video-controls-btn mar-video-controls-play"
        @click="toggle"
      >
        <MarIcon :icon="playing ? 'pause' : 'play'" class="mar-video-controls-icon" />
      </button>
      <button
        type="button"
        class="mar-video-controls-btn"
        title="Back 15 seconds"
        @click="skip(-15)"
      >
        <MarIcon icon="undo" class="mar-video-controls-icon" /><span class="mar-video-controls-15">15</span>
      </button>
      <button
        type="button"
        class="mar-video-controls-btn"
        title="Forward 15 seconds"
        @click="skip(15)"
      >
        <span class="mar-video-controls-15">15</span><MarIcon icon="redo" class="mar-video-controls-icon" />
      </button>
      <div class="mar-video-controls-track" @click="onSeek">
        <span
          class="mar-video-controls-fill"
          :style="{ width: `${progress * 100}%` }"
        ></span>
      </div>
      <span class="mar-video-controls-time">
        {{ formatTime(currentTime) }} / {{ formatTime(duration) }}
      </span>
      <div class="mar-video-controls-volume">
        <button
          type="button"
          class="mar-video-controls-btn"
          :title="volume === 0 ? 'unmute' : 'volume'"
          @click.stop="volumeOpen = !volumeOpen"
        >
          <MarIcon :icon="volume === 0 ? 'volume-off' : 'volume-up'" class="mar-video-controls-icon" />
        </button>
        <div v-if="volumeOpen" class="mar-video-controls-volume-pop">
          <MarSliderInput v-model="vol" orientation="vertical" :min="0" :max="1" :step="0.01" />
        </div>
      </div>
      <button
        type="button"
        class="mar-video-controls-btn"
        title="Fullscreen"
        @click="fullscreen"
      >
        <MarIcon icon="full-screen" class="mar-video-controls-icon" />
      </button>
    </div>
  </div>
</template>

<style scoped>
.mar-video-controls {
  position: relative;
  width: 100%;
  aspect-ratio: 16 / 9;
  background: var(--mar-image-backdrop);
  border-radius: 6px;
  overflow: hidden;
}

.mar-video-controls-stage {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--mar-image-backdrop);
}

.mar-video-controls-video {
  width: 100%;
  height: 100%;
  object-fit: contain;
  display: block;
  cursor: pointer;
}

.mar-video-controls-bar {
  position: absolute;
  bottom: 0.75em;
  left: 50%;
  transform: translateX(-50%);
  width: calc(100% - 1.5em);
  max-width: 32em;
  display: flex;
  align-items: center;
  gap: 0.375em;
  padding: 0.25em 0.5em;
  background: var(--mar-surface-0);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 9999px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.12);
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-video-controls:hover .mar-video-controls-bar,
.mar-video-controls:focus-within .mar-video-controls-bar {
  opacity: 1;
  pointer-events: auto;
}

.mar-video-controls-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.075em;
  border: none;
  background: transparent;
  color: var(--mar-surface-700);
  cursor: pointer;
  border-radius: 9999px;
  padding: 0.3em;
  font-size: 0.8333em;
  flex-shrink: 0;
}

.mar-video-controls-btn:hover {
  background: var(--mar-surface-200);
  color: var(--mar-text-color);
}

.mar-video-controls-play {
  color: var(--mar-primary-color);
}

.mar-video-controls-icon {
  font-size: 1.2em;
}

.mar-video-controls-15 {
  font-size: 0.675em;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

.mar-video-controls-track {
  flex: 1;
  min-width: 0;
  height: 0.25em;
  border-radius: 9999px;
  background: var(--mar-surface-300);
  cursor: pointer;
}

.mar-video-controls-fill {
  display: block;
  height: 100%;
  border-radius: 9999px;
  background: var(--mar-primary-color);
}

.mar-video-controls-time {
  font-size: 0.6875em;
  font-variant-numeric: tabular-nums;
  color: var(--mar-surface-600);
  flex-shrink: 0;
}

.mar-video-controls-volume {
  position: relative;
  flex-shrink: 0;
}

.mar-video-controls-volume-pop {
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
