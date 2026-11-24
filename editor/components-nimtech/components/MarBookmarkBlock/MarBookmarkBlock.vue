<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import MarIcon from "../MarIcon";
import MarImage from "../MarImage";
import type { MarBlockLinkPreview } from "../MarBlockEditor/marBlockEditor.types";

const props = defineProps<{
  /** Editor node whose options carry the url and an optional display override of card or inline. */
  node: {
    options: {
      url?: string;
      display?: "card" | "inline";
    };
    textContent?: string;
  };
  /** Strengthens the card border when the block is selected. */
  selected: boolean;
  /** Editor state that collapses the card to a plain link when isEditable is false. */
  editor?: { isEditable: boolean };
  /** Extension options carrying the resolve hook that loads link metadata. */
  extension: {
    options: {
      resolve?: (url: string) => Promise<MarBlockLinkPreview>;
    };
  };
}>();

const editable = computed(() => props.editor?.isEditable ?? true);

const url = computed(() => props.node.options.url ?? "");
const preview = ref<MarBlockLinkPreview | null>(null);
const loading = ref(false);

const load = async () => {
  const resolve = props.extension.options.resolve;
  if (!url.value) {
    preview.value = null;
    return;
  }
  if (!resolve) {
    preview.value = { url: url.value, title: url.value };
    return;
  }
  loading.value = true;
  try {
    preview.value = await resolve(url.value);
  } catch {
    preview.value = { url: url.value, title: url.value };
  } finally {
    loading.value = false;
  }
};

watch(url, load, { immediate: true });

const host = computed(() => {
  try {
    return new URL(url.value).host;
  } catch {
    return url.value;
  }
});

const display = computed(() => {
  const explicit = props.node.options.display;
  if (explicit === "card" || explicit === "inline") return explicit;
  const p = preview.value;
  if (!p) return "inline";
  if (p.card === "summary_large_image" || p.card === "player" || p.embedUrl)
    return "card";
  return "inline";
});

const isPlayer = computed(
  () => preview.value?.card === "player" || !!preview.value?.embedUrl,
);

const variant = computed(() => {
  if (display.value === "inline") return "compact";
  return isPlayer.value ? "player" : "large";
});

const siteLabel = computed(
  () => preview.value?.siteName || preview.value?.provider || host.value,
);
</script>

<template>
  <NodeViewWrapper v-if="!editable" class="mar-be-bookmark-readonly" contenteditable="false">
    <a :href="url" target="_blank" rel="noopener" class="mar-be-bookmark-readonly-link">
      <MarIcon icon="open-in-new" class="mar-be-bookmark-readonly-icon" />
      <span>{{ preview?.title || host }}</span>
    </a>
  </NodeViewWrapper>
  <NodeViewWrapper
    v-else
    :class="['mar-be-bookmark', `mar-be-bookmark-${variant}`, { 'mar-be-bookmark-selected': selected }]"
    contenteditable="false"
  >
    <div v-if="!url" class="mar-be-empty mar-be-empty-row">
      <span class="mar-be-empty-thumb"><MarIcon icon="bookmark" class="mar-be-bookmark-empty-icon" /></span>
      <span class="mar-be-empty-text">
        <span class="mar-be-empty-title">Add a link</span>
        <span class="mar-be-empty-hint">Set the address from the block menu and the card fills from the page</span>
      </span>
    </div>
    <a v-else :href="url" target="_blank" rel="noopener" class="mar-be-bookmark-card">
      <div
        v-if="variant !== 'compact'"
        :class="['mar-be-bookmark-hero', { 'mar-be-bookmark-hero-empty': !preview?.imageUrl }]"
      >
        <MarImage
          v-if="preview?.imageUrl"
          class="mar-be-bookmark-hero-img"
          :src="preview.imageUrl"
        />
        <MarIcon v-else :icon="variant === 'player' ? 'play' : 'image'" class="mar-icon-xxlarge" />
        <span v-if="variant === 'player' && preview?.imageUrl" class="mar-be-bookmark-play">
          <MarIcon icon="play" class="mar-icon-large" />
        </span>
      </div>
      <div class="mar-be-bookmark-body">
        <div class="mar-be-bookmark-title">
          {{ preview?.title || (loading ? "Loading..." : host) }}
        </div>
        <div v-if="preview?.description" class="mar-be-bookmark-desc">
          {{ preview.description }}
        </div>
        <div class="mar-be-bookmark-meta">
          <MarImage
            v-if="preview?.favicon"
            :src="preview.favicon"
            fit="contain"
            :spinner="false"
            class="mar-be-bookmark-favicon"
          >
            <template #fallback>
              <MarIcon icon="open-in-new" class="mar-be-bookmark-favicon-fallback" />
            </template>
          </MarImage>
          <MarIcon v-else icon="open-in-new" class="mar-be-bookmark-favicon" />
          <span class="mar-be-bookmark-site">{{ siteLabel }}</span>
          <span v-if="preview?.author" class="mar-be-bookmark-author">{{ preview.author }}</span>
        </div>
      </div>
      <div
        v-if="variant === 'compact'"
        :class="['mar-be-bookmark-thumb', { 'mar-be-bookmark-thumb-empty': !preview?.imageUrl }]"
      >
        <MarImage
          v-if="preview?.imageUrl"
          class="mar-be-bookmark-thumb-img"
          :src="preview.imageUrl"
        />
        <MarIcon v-else icon="image" class="mar-icon-large" />
      </div>
    </a>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-bookmark-readonly {
  display: block;
  margin: 0.5em 0;
}

.mar-be-bookmark-readonly-link {
  display: inline-flex;
  align-items: center;
  gap: 0.4286em;
  color: var(--mar-primary-color);
  font-size: 0.875em;
  text-decoration: none;
}

.mar-be-bookmark-readonly-link:hover {
  text-decoration: underline;
}

.mar-be-bookmark-readonly-icon {
  font-size: 1.1429em;
}

.mar-be-bookmark-empty-icon {
  font-size: 0.8889em;
}

.mar-be-bookmark {
  margin: 0.5em 0;
}

.mar-be-bookmark-card {
  display: flex;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
  overflow: hidden;
  text-decoration: none;
  color: var(--mar-text-color);
  transition: border-color 0.15s cubic-bezier(0.4, 0, 0.2, 1),
    box-shadow 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-be-bookmark-compact .mar-be-bookmark-card {
  align-items: stretch;
}

.mar-be-bookmark-large .mar-be-bookmark-card,
.mar-be-bookmark-player .mar-be-bookmark-card {
  flex-direction: column;
}

.mar-be-bookmark-card:hover {
  border-color: var(--mar-surface-400);
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.06);
}

.mar-be-bookmark-selected .mar-be-bookmark-card {
  border-color: var(--mar-surface-400);
}

.mar-be-bookmark-hero {
  position: relative;
  width: 100%;
  aspect-ratio: 1.91;
  background: var(--mar-surface-100);
}

.mar-be-bookmark-hero-empty {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--mar-surface-400);
  background: var(--mar-highlight-background);
}

.mar-be-bookmark-hero-img {
  width: 100%;
  height: 100%;
  display: block;
}

.mar-be-bookmark-play {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--mar-overlay-color);
  background: rgba(0, 0, 0, 0.25);
}

.mar-be-bookmark-body {
  flex: 1;
  min-width: 0;
  padding: 0.625em 0.75em;
  display: flex;
  flex-direction: column;
  gap: 0.25em;
}

.mar-be-bookmark-title {
  font-size: 0.8125em;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mar-be-bookmark-desc {
  font-size: 0.75em;
  color: var(--mar-surface-600);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.mar-be-bookmark-meta {
  display: flex;
  align-items: center;
  gap: 0.5455em;
  font-size: 0.6875em;
  color: var(--mar-surface-500);
  margin-top: auto;
}

.mar-be-bookmark-favicon {
  width: 1.2727em;
  height: 1.2727em;
  border-radius: 2px;
  background: transparent;
}

.mar-be-bookmark-favicon-fallback {
  font-size: 1.4545em;
}

.mar-be-bookmark-author {
  color: var(--mar-surface-400);
}

.mar-be-bookmark-author::before {
  content: "·";
  margin-right: 0.5455em;
}

.mar-be-bookmark-thumb {
  width: 7.5em;
  flex-shrink: 0;
  background: var(--mar-surface-100);
}

.mar-be-bookmark-thumb-empty {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--mar-surface-400);
  background: var(--mar-highlight-background);
}

.mar-be-bookmark-thumb-img {
  width: 100%;
  height: 100%;
  display: block;
}
</style>
