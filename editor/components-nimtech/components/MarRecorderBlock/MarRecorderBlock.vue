<script setup lang="ts">
import { computed, defineAsyncComponent, onMounted, ref, watch } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import MarIconBtn from "../MarIconBtn";
import { openModal } from "@/composables/useModals.ts";
import {
  useRecorderSession,
  startRecorder,
  pauseRecorder,
  resumeRecorder,
  stopRecorder,
  discardRecorder,
  setTranscript,
  setRecorderName,
  getActiveRecorder,
} from "@/composables/useRecorder.ts";

const props = defineProps<{
  /** Editor node whose options hold the persisted recId and transcript. */
  node: {
    options: {
      recId?: string;
      transcript?: string;
    };
    textContent?: string;
  };
  /** Editor instance whose isEditable flag switches between the recorder and the read only transcript view. */
  editor: { isEditable: boolean };
  /** Node view callback that persists recId and transcript changes into the document. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
  /** Extension options carrying the transcription socket config and the open recording callback. */
  extension: {
    options: {
      socketUrl?: string;
      createSocket?: () => WebSocket;
      onOpenRecording?: (recId: string) => void;
    };
  };
}>();

const editable = computed(() => props.editor?.isEditable ?? true);

const newId = () => {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return `rec-${Date.now()}-${Math.floor(performance.now())}`;
};

const recId = ref<string>(props.node.options.recId ?? "");

onMounted(() => {
  if (!recId.value) {
    recId.value = newId();
    props.updateAttributes({ recId: recId.value });
  }
  const docTranscript = props.node.options.transcript ?? "";
  const sess = useRecorderSession(recId.value);
  if (!sess.transcript && docTranscript) {
    setTranscript(recId.value, docTranscript);
  }
});

const session = computed(() => useRecorderSession(recId.value || "pending"));
const transcript = computed(() => session.value.transcript);
const recording = computed(() => session.value.recording);
const paused = computed(() => session.value.paused);
const bars = computed(() => session.value.bars);
const error = computed(() => session.value.error);


const WAVE_SLOTS = 56;
const waveBars = computed<number[]>(() => {
  const b = bars.value;
  if (b.length >= WAVE_SLOTS) return b.slice(b.length - WAVE_SLOTS);
  return [...new Array(WAVE_SLOTS - b.length).fill(0), ...b];
});

watch(transcript, (t) => {
  if (recId.value) props.updateAttributes({ transcript: t });
});

const showTranscript = ref(true);

const elapsedLabel = computed(() => {
  const e = session.value.elapsed;
  const m = Math.floor(e / 60);
  const s = e % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
});

const recordAnchor = ref<HTMLElement | null>(null);

const defaultName = () => session.value.name || `Recording ${elapsedDate()}`;

const elapsedDate = () => new Date().toISOString().slice(0, 16).replace("T", " ");

const locate = (): void => {
  const el =
    typeof document !== "undefined"
      ? document.querySelector(`[data-rec-id="${recId.value}"]`)
      : null;
  if (el) {
    el.scrollIntoView({ behavior: "smooth", block: "center" });
  } else {
    props.extension.options.onOpenRecording?.(recId.value);
  }
};

const confirmCancel = async (anchor?: HTMLElement): Promise<void> => {
  const ok = await openModal<boolean>({
    kind: "popup",
    component: defineAsyncComponent(() => import("../MarRecorderCancelDialog")),
    anchor: anchor ? { target: anchor } : undefined,
    placement: { side: "top", align: "end", offset: 6, minWidth: 288 },
    backdrop: "invisible",
    props: { name: session.value.name || "this recording" },
  });
  if (!ok) return;
  discardRecorder(recId.value);
  props.updateAttributes({ transcript: "" });
};

const opts = () => ({
  socketUrl: props.extension.options.socketUrl,
  createSocket: props.extension.options.createSocket,
  onLocate: locate,
  onRequestCancel: (anchor?: HTMLElement) => void confirmCancel(anchor),
});

const onRecord = async () => {
  if (!recId.value) return;
  const active = getActiveRecorder();
  if (!active || active.id === recId.value) {
    if (!session.value.name) setRecorderName(recId.value, defaultName());
    void startRecorder(recId.value, opts());
    return;
  }
  const target = recordAnchor.value;
  if (!target) return;
  const result = await openModal<{ name: string }>({
    kind: "dropdown",
    component: defineAsyncComponent(() => import("../MarRecorderStartPanel")),
    anchor: { target },
    placement: { side: "bottom", align: "start" },
    backdrop: "invisible",
    props: { defaultName: defaultName(), activeName: active.name || "a recording" },
  });
  if (!result) return;
  stopRecorder(active.id);
  setRecorderName(recId.value, result.name);
  void startRecorder(recId.value, opts());
};
const onPauseResume = () => {
  if (!recId.value) return;
  if (paused.value) resumeRecorder(recId.value);
  else pauseRecorder(recId.value);
};
const onStop = () => {
  if (recId.value) stopRecorder(recId.value);
};
</script>

<template>
  <NodeViewWrapper
    v-if="!editable"
    class="mar-be-rec-readonly"
    contenteditable="false"
  >
    <div class="mar-be-rec-readonly-title">{{ session.name || "Transcript" }}</div>
    <div v-if="transcript" class="mar-be-rec-readonly-text">{{ transcript }}</div>
  </NodeViewWrapper>
  <NodeViewWrapper
    v-else
    class="mar-be-rec"
    contenteditable="false"
    :data-rec-id="recId"
  >
    <div v-if="editable" class="mar-be-rec-player">
      <span v-if="!recording" ref="recordAnchor" class="mar-be-rec-anchor">
        <MarIconBtn icon="mic" class="mar-be-rec-main" tooltip="Record" @click="onRecord" />
      </span>
      <template v-else>
        <MarIconBtn
          :icon="paused ? 'play' : 'pause'"
          class="mar-be-rec-main mar-be-rec-live"
          :class="{ 'mar-be-rec-paused': paused }"
          :tooltip="paused ? 'Resume' : 'Pause'"
          @click="onPauseResume"
        />
        <MarIconBtn icon="stop-circle" tooltip="Stop" @click="onStop" />
      </template>

      <div class="mar-be-rec-wave">
        <template v-if="recording || bars.length">
          <span
            v-for="(b, i) in waveBars"
            :key="i"
            class="mar-be-rec-bar"
            :style="{ height: `${4 + b * 96}%` }"
          ></span>
        </template>
        <span v-else class="mar-be-rec-idle">Ready to record</span>
      </div>

      <span class="mar-be-rec-time">{{ elapsedLabel }}</span>

      <MarIconBtn
        icon="chevron-right"
        class="mar-be-rec-toggle"
        :class="{ 'mar-be-rec-toggle-open': showTranscript }"
        :tooltip="showTranscript ? 'Hide transcript' : 'Show transcript'"
        @click="showTranscript = !showTranscript"
      />
    </div>

    <div v-if="error && editable" class="mar-be-rec-error">{{ error }}</div>

    <div
      v-if="editable ? showTranscript : !!transcript"
      class="mar-be-rec-transcript"
    >
      <template v-if="transcript">{{ transcript }}</template>
      <span v-else class="mar-be-rec-placeholder">
        Transcript appears here as you record.
      </span>
    </div>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-rec-readonly {
  display: block;
  margin: 0.75em 0;
}

.mar-be-rec-readonly-title {
  font-weight: 600;
  font-size: 0.9375em;
  color: var(--mar-text-color);
  margin-bottom: 0.2667em;
}

.mar-be-rec-readonly-text {
  font-size: 0.8125em;
  line-height: 1.5;
  color: var(--mar-text-color);
  white-space: pre-wrap;
}

.mar-be-rec {
  margin: 0.5em 0;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 10px;
  background: var(--mar-surface-50);
  overflow: hidden;
}

.mar-be-rec-player {
  display: flex;
  align-items: center;
  gap: 0.5em;
  padding: 0.5em 0.625em;
}

.mar-be-rec-anchor {
  display: inline-flex;
  flex-shrink: 0;
}

.mar-be-rec-main {
  background: var(--mar-primary-color);
  color: var(--mar-primary-contrast-color);
}

.mar-be-rec-main:hover:not(:disabled) {
  background: var(--mar-primary-color);
  color: var(--mar-primary-contrast-color);
}

.mar-be-rec-live {
  background: var(--mar-red-500);
  color: var(--mar-overlay-color);
  animation: mar-be-rec-pulse 1.4s ease-in-out infinite;
}

.mar-be-rec-live:hover:not(:disabled) {
  background: var(--mar-red-500);
  color: var(--mar-overlay-color);
}

.mar-be-rec-paused {
  animation: none;
}

@keyframes mar-be-rec-pulse {
  0%,
  100% {
    box-shadow: 0 0 0 0
      color-mix(in srgb, var(--mar-red-500), transparent 60%);
  }
  50% {
    box-shadow: 0 0 0 0.375em transparent;
  }
}

.mar-be-rec-wave {
  flex: 1;
  min-width: 0;
  height: 2em;
  display: flex;
  align-items: center;
  justify-content: stretch;
  gap: 1px;
  overflow: hidden;
}

.mar-be-rec-bar {
  flex: 1 1 0;
  min-width: 0;
  min-height: 2px;
  border-radius: 9999px;
  background: var(--mar-primary-color);
  opacity: 0.85;
}

.mar-be-rec-idle {
  font-size: 0.75em;
  color: var(--mar-surface-400);
}

.mar-be-rec-time {
  font-size: 0.8125em;
  font-variant-numeric: tabular-nums;
  color: var(--mar-surface-600);
  flex-shrink: 0;
}

.mar-be-rec-toggle {
  flex-shrink: 0;
}

.mar-be-rec-toggle :deep(svg) {
  transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-be-rec-toggle-open :deep(svg) {
  transform: rotate(90deg);
}

.mar-be-rec-error {
  padding: 0 1em 0.6667em;
  font-size: 0.75em;
  color: var(--mar-red-500);
}

.mar-be-rec-transcript {
  padding: 0.7692em 0.9231em;
  border-top: 1px solid var(--mar-content-border-color);
  font-size: 0.8125em;
  line-height: 1.5;
  color: var(--mar-text-color);
  white-space: pre-wrap;
}

.mar-be-rec-placeholder {
  color: var(--mar-surface-400);
}
</style>
