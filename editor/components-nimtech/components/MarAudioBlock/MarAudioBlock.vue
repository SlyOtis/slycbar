<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import { getMediaOptions } from "@/blockedit/model/schema.ts";
import type { MarMediaAsset } from "@/types/media.types";
import MarIcon from "../MarIcon";
import MarImage from "../MarImage";
import MarAudioControls from "../MarAudioControls";

const props = defineProps<{
  /** Editor node whose options carry src, title, description, layout, cover, waveform, and autoplay. */
  node: {
    options: {
      src?: string;
      title?: string;
      description?: string;
      layout?: "large" | "slim" | "compact" | "card" | "full" | "mini" | "meta";
      cover?: string;
      waveform?: number[];
      autoplay?: boolean;
    };
    textContent?: string;
  };
  /** Marks the block as selected in the editor and strengthens the border. */
  selected: boolean;
  /** Editability source, the block behaves as editable when absent. */
  editor?: { isEditable: boolean };
  /** Callback the empty preview calls to store the picked source. */
  updateAttributes?: (attrs: Record<string, unknown>) => void;
  /** Editor wiring, whose requestMedia opens the host's upload dialog from the empty preview. */
  extension?: {
    options: {
      requestMedia?: (kind: "audio", current?: string) => Promise<MarMediaAsset | null>;
    };
  };
}>();

const options = computed(() => props.node.options);

const autoplay = computed(() => options.value.autoplay === true);
const editable = computed(() => props.editor?.isEditable ?? true);
const requestMedia = computed(() => props.extension?.options.requestMedia);
const emptyBars = [38, 62, 84, 50, 72, 96, 58, 34, 66, 88, 46, 70, 54, 80, 42, 60, 92, 48, 30, 64];

const pick = async (): Promise<void> => {
  const next = await requestMedia.value?.("audio");
  if (next) props.updateAttributes?.(getMediaOptions("audio", next));
};

const src = computed(() => options.value.src ?? "");
const title = computed(() => options.value.title ?? "");
const description = computed(() => options.value.description ?? "");
const cover = computed(() => options.value.cover ?? "");
const layout = computed(() => options.value.layout ?? "large");
const peaks = computed<number[]>(() =>
  Array.isArray(options.value.waveform) ? options.value.waveform : [],
);

const hasCover = computed(
  () => layout.value === "card" || layout.value === "full",
);
const hasText = computed(() =>
  ["large", "meta", "card", "full", "mini"].includes(layout.value),
);
const showWaveform = computed(() =>
  ["large", "slim", "compact", "full"].includes(layout.value),
);
const showSkip = computed(() => layout.value !== "slim");

const audioEl = ref<HTMLAudioElement | null>(null);
const playing = ref(false);
const currentTime = ref(0);
const duration = ref(0);
const volume = ref(1);

const progress = computed(() =>
  duration.value ? currentTime.value / duration.value : 0,
);

const togglePlay = () => {
  const el = audioEl.value;
  if (!el) return;
  if (el.paused) el.play();
  else el.pause();
};

const skip = (delta: number) => {
  const el = audioEl.value;
  if (!el) return;
  el.currentTime = Math.min(
    el.duration || 0,
    Math.max(0, el.currentTime + delta),
  );
};

const seekToRatio = (ratio: number) => {
  const el = audioEl.value;
  if (!el || !el.duration) return;
  el.currentTime = Math.min(1, Math.max(0, ratio)) * el.duration;
};

const onTimeUpdate = () => {
  if (audioEl.value) currentTime.value = audioEl.value.currentTime;
};
const onMeta = () => {
  if (audioEl.value) duration.value = audioEl.value.duration;
};
const onPlay = () => {
  playing.value = true;
};
const onPause = () => {
  playing.value = false;
};

watch(volume, (v) => {
  if (audioEl.value) audioEl.value.volume = v;
});

onMounted(() => {
  if (autoplay.value) void audioEl.value?.play().catch(() => undefined);
});

onBeforeUnmount(() => audioEl.value?.pause());
</script>

<template>
  <NodeViewWrapper
    :class="['mar-audio-block', `mar-audio-block-${layout}`, { 'mar-audio-block-selected': selected, 'mar-audio-block-blank': !src }]"
    contenteditable="false"
  >
    <audio
      ref="audioEl"
      :src="src"
      @timeupdate="onTimeUpdate"
      @loadedmetadata="onMeta"
      @play="onPlay"
      @pause="onPause"
      @ended="onPause"
    ></audio>

    <template v-if="!src">
      <button
        v-if="editable"
        type="button"
        class="mar-be-empty mar-be-empty-row"
        :disabled="!requestMedia"
        @click="pick"
      >
        <span class="mar-be-empty-thumb"><MarIcon icon="music" class="mar-audio-block-empty-icon" /></span>
        <span class="mar-be-empty-text">
          <span class="mar-be-empty-title">Add audio</span>
          <span class="mar-be-empty-hint">{{ requestMedia ? "Click to upload or pick a recording" : "Set the audio from the block menu" }}</span>
        </span>
        <span class="mar-be-empty-wave">
          <span v-for="(bar, i) in emptyBars" :key="i" :style="{ '--mar-be-empty-bar': `${bar}%` }" />
        </span>
      </button>
    </template>

    <div v-else-if="layout === 'mini'" class="mar-audio-block-mini">
      <button type="button" class="mar-audio-block-mini-play" @click="togglePlay">
        <MarIcon :icon="playing ? 'pause' : 'play'" class="mar-audio-block-play-icon" />
      </button>
      <span class="mar-audio-block-title">{{ title || "Audio" }}</span>
    </div>

    <div v-else-if="hasCover" class="mar-audio-block-cover-row">
      <div class="mar-audio-block-cover">
        <MarImage v-if="cover" :src="cover" fit="cover" />
        <span v-else class="mar-audio-block-cover-icon">
          <MarIcon icon="music" class="mar-icon-xlarge" />
        </span>
      </div>
      <div class="mar-audio-block-content">
        <div v-if="hasText" class="mar-audio-block-text">
          <span v-if="title" class="mar-audio-block-title">{{ title }}</span>
          <span v-if="description" class="mar-audio-block-desc">{{ description }}</span>
        </div>
        <MarAudioControls
          :playing="playing"
          :current-time="currentTime"
          :duration="duration"
          v-model:volume="volume"
          :peaks="peaks"
          :progress="progress"
          :show-waveform="showWaveform"
          :show-skip="showSkip"
          @toggle="togglePlay"
          @skip="skip"
          @seek="seekToRatio"
        />
      </div>
    </div>

    <div v-else-if="layout === 'meta'" class="mar-audio-block-meta">
      <div class="mar-audio-block-meta-head">
        <span class="mar-audio-block-icon"><MarIcon icon="music" class="mar-icon-large" /></span>
        <div class="mar-audio-block-text">
          <span v-if="title" class="mar-audio-block-title">{{ title }}</span>
          <span v-if="description" class="mar-audio-block-desc">{{ description }}</span>
        </div>
      </div>
      <MarAudioControls
        :playing="playing"
        :current-time="currentTime"
        :duration="duration"
        v-model:volume="volume"
        :peaks="peaks"
        :progress="progress"
        :show-waveform="false"
        :show-skip="showSkip"
        @toggle="togglePlay"
        @skip="skip"
        @seek="seekToRatio"
      />
    </div>

    <template v-else>
      <div
        v-if="layout === 'large' && hasText"
        class="mar-audio-block-text mar-audio-block-text-top"
      >
        <span v-if="title" class="mar-audio-block-title">{{ title }}</span>
        <span v-if="description" class="mar-audio-block-desc">{{ description }}</span>
      </div>
      <MarAudioControls
        :playing="playing"
        :current-time="currentTime"
        :duration="duration"
        v-model:volume="volume"
        :peaks="peaks"
        :progress="progress"
        :show-waveform="showWaveform"
        :show-skip="showSkip"
        @toggle="togglePlay"
        @skip="skip"
        @seek="seekToRatio"
      />
    </template>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-audio-block {
  margin: 0.5em 0;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
  background: var(--mar-surface-50);
  padding: 0.375em;
}

.mar-audio-block-blank {
  border: none;
  padding: 0;
  background: none;
}

.mar-audio-block-slim,
.mar-audio-block-compact {
  padding: 0.25em;
}

.mar-audio-block-card {
  display: inline-block;
  width: auto;
  max-width: 22em;
}

.mar-audio-block-selected {
  border-color: var(--mar-surface-400);
}

.mar-audio-block-mini {
  display: inline-flex;
  align-items: center;
  gap: 0.375em;
  padding: 0.125em 0.5em 0.125em 0.125em;
}

.mar-audio-block-mini-play {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 0.8333em;
  width: 1.8em;
  height: 1.8em;
  border: none;
  border-radius: 9999px;
  background: var(--mar-highlight-background);
  color: var(--mar-primary-color);
  cursor: pointer;
}

.mar-audio-block-play-icon {
  font-size: 1.2em;
}

.mar-audio-block-empty-icon {
  font-size: 0.8889em;
}

.mar-audio-block-cover-row {
  display: flex;
  gap: 0.625em;
  align-items: stretch;
}

.mar-audio-block-cover {
  width: 4em;
  align-self: stretch;
  flex-shrink: 0;
  border-radius: 6px;
  overflow: hidden;
  background: var(--mar-highlight-background);
}

.mar-audio-block-cover :deep(img) {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.mar-audio-block-cover-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 100%;
  color: var(--mar-primary-color);
}

.mar-audio-block-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.375em;
}

.mar-audio-block-meta-head {
  display: flex;
  align-items: center;
  gap: 0.625em;
  margin-bottom: 0.5em;
}

.mar-audio-block-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2.25em;
  height: 2.25em;
  flex-shrink: 0;
  border-radius: 8px;
  background: var(--mar-highlight-background);
  color: var(--mar-primary-color);
}

.mar-audio-block-text {
  display: flex;
  flex-direction: column;
  gap: 0.125em;
  min-width: 0;
}

.mar-audio-block-text-top {
  margin-bottom: 0.5em;
}

.mar-audio-block-title {
  font-size: 0.875em;
  font-weight: 600;
  color: var(--mar-text-color);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.mar-audio-block-desc {
  font-size: 0.75em;
  color: var(--mar-surface-500);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
