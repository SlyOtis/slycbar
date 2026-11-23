<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import MarLoadingSpinner from "../MarLoadingSpinner";
import type { MarImageFrame } from "@/types/image.types";

const {
  src,
  alt = "",
  fit = "cover",
  rounded = "none",
  placeholder = null,
  frame,
  lazy = false,
  spinner = true,
  srcFor,
  widths = [128, 256, 320, 480, 640, 960, 1280, 1920],
  resizeDelay = 200,
} = defineProps<{
  /** URL of the image, the fallback slot shows when absent or null. */
  src?: string | null;
  /** Alt text for the inner img element. */
  alt?: string;
  /** How the image fills the frame through object fit. */
  fit?: "cover" | "contain";
  /** Corner radius of the frame from none to a full circle. */
  rounded?: "none" | "sm" | "md" | "lg" | "full";
  /** Low resolution source rendered blurred under the image until it loads, the theme surface shows when absent. */
  placeholder?: string | null;
  /** Region of the image the frame shows, as fractions of the image. */
  frame?: MarImageFrame;
  /** Defers the request through native lazy loading, for images far down a long grid. */
  lazy?: boolean;
  /** Renders the loading spinner over the placeholder while the image loads. */
  spinner?: boolean;
  /** Builds a source for a pixel width and the measured aspect of the box. Given it, the frame asks for the first rung that covers its measured box times the device pixel ratio, and climbs when the box grows past it. */
  srcFor?: (width: number, aspect: number) => string;
  /** Rungs the measured width snaps up to, so a handful of variants serve every box and stay cacheable. */
  widths?: number[];
  /** Milliseconds of quiet after a resize before the frame settles on its rung. */
  resizeDelay?: number;
}>();

const emit = defineEmits<{
  load: [image: HTMLImageElement];
  error: [];
}>();

const loaded = ref(false);
const errored = ref(false);
const previous = ref<string | null>(null);
const root = ref<HTMLElement | null>(null);
const rung = ref<number | null>(null);
const refined = ref(false);
const sharpDenied = ref(false);
const boxAspect = ref(1);

let observer: ResizeObserver | null = null;
let timer: ReturnType<typeof setTimeout> | null = null;

const ladder = computed(() => [...widths].sort((a, b) => a - b));

const rungFor = (box: number) => {
  const want = box * (window.devicePixelRatio || 1);
  return ladder.value.find((w) => w >= want) ?? ladder.value[ladder.value.length - 1];
};

const settle = () => {
  timer = null;
  const box = root.value?.clientWidth ?? 0;
  const high = root.value?.clientHeight ?? 0;
  if (box <= 0) return;
  const span = frame && frame.width > 0 ? box / frame.width : box;
  const want = rungFor(span);
  const shown = refined.value && sharper.value !== null ? sharper.value : rung.value;
  if (shown !== null && want <= shown) return;
  if (high > 0) boxAspect.value = Math.round((box / high) * 1000) / 1000;
  refined.value = false;
  rung.value = want;
};

const onResize = () => {
  if (timer) clearTimeout(timer);
  timer = setTimeout(settle, resizeDelay);
};

const sharper = computed(() => {
  if (rung.value === null) return null;
  return ladder.value.find((w) => w > rung.value!) ?? null;
});

const resolved = computed(() => {
  if (!srcFor) return src ?? null;
  if (rung.value === null) return null;
  const width = refined.value && sharper.value !== null ? sharper.value : rung.value;
  return srcFor(width, boxAspect.value);
});

onMounted(() => {
  if (!srcFor || !root.value) return;
  observer = new ResizeObserver(onResize);
  observer.observe(root.value);
});

onBeforeUnmount(() => {
  if (timer) clearTimeout(timer);
  observer?.disconnect();
  observer = null;
});

watch(
  () => resolved.value,
  () => {
    loaded.value = false;
    errored.value = false;
  },
);

const classes = computed(() => [
  "mar-image",
  `mar-image-fit-${fit}`,
  `mar-image-rounded-${rounded}`,
  { "mar-image-loaded": loaded.value },
  { "mar-image-errored": errored.value },
]);

const frameStyle = computed(() => {
  if (!frame || frame.width <= 0 || frame.height <= 0) return undefined;
  return {
    width: `${100 / frame.width}%`,
    height: `${100 / frame.height}%`,
    transform: `translate(${-frame.x * 100}%, ${-frame.y * 100}%)`,
  };
});

const carried = computed(() =>
  previous.value && previous.value !== resolved.value ? previous.value : null,
);

const onLoad = (event: Event) => {
  loaded.value = true;
  errored.value = false;
  previous.value = resolved.value;
  emit("load", event.target as HTMLImageElement);
  if (srcFor && !refined.value && !sharpDenied.value && sharper.value !== null) refined.value = true;
};

const onError = () => {
  if (refined.value) {
    sharpDenied.value = true;
    refined.value = false;
    return;
  }
  loaded.value = false;
  errored.value = true;
  emit("error");
};
</script>

<template>
  <div ref="root" :class="classes">
    <img
      v-if="carried"
      class="mar-image-carried"
      :src="carried"
      alt=""
      :style="frameStyle"
      draggable="false"
    />
    <div v-if="placeholder && !loaded && !carried" class="mar-image-placeholder">
      <img :src="placeholder" alt="" :style="frameStyle" draggable="false" />
    </div>
    <img
      v-if="resolved && !errored"
      class="mar-image-img"
      :src="resolved"
      :alt="alt"
      :loading="lazy ? 'lazy' : undefined"
      :style="frameStyle"
      draggable="false"
      @load="onLoad"
      @error="onError"
    />
    <div v-if="!loaded && !errored && resolved && !carried" class="mar-image-loading">
      <slot name="loading">
        <MarLoadingSpinner v-if="spinner" mode="inline" label="" />
      </slot>
    </div>
    <div v-if="errored || (!resolved && !carried)" class="mar-image-fallback">
      <slot name="fallback" />
    </div>
  </div>
</template>

<style scoped>
.mar-image {
  position: relative;
  display: flex;
  width: 100%;
  height: 100%;
  overflow: hidden;
  background: var(--mar-surface-100);
  container-type: inline-size;
}

@container (max-width: 6rem) {
  .mar-image-loading {
    transform: scale(0.7);
  }
}

@container (max-width: 3rem) {
  .mar-image-loading {
    transform: scale(0.45);
  }
}

.mar-image-rounded-sm {
  border-radius: 3px;
}

.mar-image-rounded-md {
  border-radius: 6px;
}

.mar-image-rounded-lg {
  border-radius: 8px;
}

.mar-image-rounded-full {
  border-radius: 50%;
}

.mar-image-img {
  position: relative;
  z-index: 2;
  flex-shrink: 0;
  width: 100%;
  height: 100%;
  display: block;
  opacity: 0;
  transition: opacity 0.2s ease;
}

.mar-image-loaded .mar-image-img {
  opacity: 1;
}

.mar-image:not(.mar-image-loaded) .mar-image-img {
  position: absolute;
  inset: 0;
}

.mar-image-carried {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  display: block;
  z-index: 0;
}

.mar-image-placeholder {
  position: relative;
  width: 100%;
  height: 100%;
  display: block;
  z-index: 1;
  overflow: hidden;
  filter: blur(0.75em);
  transform: scale(1.1);
}

.mar-image-placeholder img {
  width: 100%;
  height: 100%;
  display: block;
}

.mar-image-fit-cover .mar-image-img,
.mar-image-fit-cover .mar-image-carried,
.mar-image-fit-cover .mar-image-placeholder img {
  object-fit: cover;
}

.mar-image-fit-contain .mar-image-img,
.mar-image-fit-contain .mar-image-carried,
.mar-image-fit-contain .mar-image-placeholder img {
  object-fit: contain;
}

.mar-image-loading,
.mar-image-fallback {
  position: absolute;
  inset: 0;
  z-index: 3;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--mar-surface-500);
}

.mar-image-loaded .mar-image-loading {
  display: none;
}
</style>
