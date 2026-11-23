<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import {
  contentString,
  createBlockEditor,
  type BlockEngine,
  type EditorConfig,
} from "@/blockedit/index.ts";
import type {
  MarContentType,
  MarDocument,
  MarDocumentType,
} from "@/blockedit/model/types.ts";
import { BlockTree } from "@/blockedit/render/BlockTree.ts";
import { mentionDeclared } from "@/blockedit/serialize/htmlSerialize.ts";
import MarIconBtn from "../MarIconBtn";
import type * as Y from "yjs";
import { createYBinding, type YBinding } from "@/blockedit/collab/yBinding.ts";
import type { CollabProvider } from "@/blockedit/collab/provider.ts";
import { useMention } from "@/blockedit/interaction/useMention.ts";
import type {
  MarBlockHeadingNumbering,
  MarBlockLinkPreview,
  MarPollData,
  MarCountdownLabels,
} from "../MarBlockEditor/marBlockEditor.types";

const {
  modelValue = "",
  contentType = "json",
  type,
  engine: hostEngine,
  ydoc,
  provider,
  collabField,
  user,
  openAsset,
  mentionTypes,
  resolveLinkPreview,
  resolvePoll,
  votePoll,
  countdownLabels,
  audioSocketUrl,
  createAudioSocket,
  headingNumbering,
} = defineProps<{
  /**
   * Document content as a json MarDocument, or as a string read per contentType.
   * @mock mockParagraph
   */
  modelValue?: MarDocument | string;
  /** How a string modelValue is read. */
  contentType?: MarContentType;
  /** Document type; a template sets the edit modes and a document enforces them. */
  type?: MarDocumentType;
  /** Renders an existing engine instead of creating one, which is how MarBlockEditor delegates its read surface. */
  engine?: BlockEngine | null;
  /** Yjs document that keeps the surface live while reading. */
  ydoc?: Y.Doc;
  /** Awareness and sync provider for the collaboration binding. */
  provider?: CollabProvider | null;
  /** Yjs field the collaboration binding attaches to. */
  collabField?: string;
  /** Local identity published on the awareness state. */
  user?: { name: string; color: string };
  /** Opens an asset when a block requests it. */
  openAsset?: (assetId: string) => void;
  /**
   * Reference kinds the host resolves, such as employee, project, asset and article.
   * A mention carrying any other type reads as inert text and never opens.
   * Left empty, every type is accepted.
   */
  mentionTypes?: string[];
  /** Resolves rich metadata for bookmark, embed, and link cards. */
  resolveLinkPreview?: (url: string) => Promise<MarBlockLinkPreview>;
  /** Resolves the live question, options, and vote tallies for a poll block. */
  resolvePoll?: (pollId: string) => Promise<MarPollData>;
  /** Casts a vote on a poll block and returns the refreshed tallies. */
  votePoll?: (pollId: string, optionIndex: number) => Promise<MarPollData>;
  /** Translated day, hour, minute, and second labels for countdown blocks. */
  countdownLabels?: MarCountdownLabels;
  /** WebSocket endpoint for recorder block playback. */
  audioSocketUrl?: string;
  /** Factory alternative to audioSocketUrl for the recorder socket. */
  createAudioSocket?: () => WebSocket;
  /** Controls automatic heading numbering. */
  headingNumbering?: MarBlockHeadingNumbering;
}>();

const emit = defineEmits<{
  "open-page-block": [assetId: string];
  "open-mention": [mention: { id: string; type: string; href: string }];
  "open-recording": [recId: string];
  "section-change": [state: { index: number; count: number }];
}>();

const engine =
  hostEngine ??
  createBlockEditor({
    content: modelValue,
    editable: false,
    contentType,
    type,
    openAsset,
    mentionTypes,
    resolveLinkPreview: resolveLinkPreview as EditorConfig["resolveLinkPreview"],
    resolvePoll: resolvePoll as EditorConfig["resolvePoll"],
    votePoll: votePoll as EditorConfig["votePoll"],
    countdownLabels,
    audioSocketUrl,
    createAudioSocket,
    onOpenRecording: (recId) => emit("open-recording", recId),
    onOpenMention: (mention) => {
      if (!mentionDeclared(mention.type, mentionTypes)) return;
      emit("open-mention", mention);
    },
    onOpenPageBlock: (assetId) => emit("open-page-block", assetId),
  });

let binding: YBinding | null = null;
if (!hostEngine && ydoc) {
  binding = createYBinding(engine, {
    ydoc,
    field: collabField ?? "default",
    provider: provider ?? null,
    user,
  });
}

onBeforeUnmount(() => {
  binding?.destroy();
  binding = null;
});

watch(
  () => modelValue,
  (value) => {
    if (hostEngine || binding) return;
    if (contentString(value) !== engine.getValue()) engine.setContent(value ?? "");
  },
);

watch(
  () => headingNumbering,
  (value) => {
    if (hostEngine || !value) return;
    if (
      value.enabled !== engine.numbering.value.enabled ||
      value.startLevel !== engine.numbering.value.startLevel
    ) {
      engine.setNumbering(value.enabled, value.startLevel);
    }
  },
  { immediate: true },
);

const surfaceEl = ref<HTMLElement | null>(null);

const { bind: bindMention } = useMention(engine, surfaceEl);

onMounted(bindMention);

const documentWidth = computed(() => engine.doc.value.width || undefined);
const numbering = computed(() => engine.doc.value.page?.numbering ?? null);
const pageCount = computed(
  () =>
    engine.doc.value.root.filter(
      (id) => engine.doc.value.blocks[id]?.kind === "break",
    ).length + 1,
);

const sections = computed(() =>
  engine.doc.value.root.filter(
    (id) => engine.doc.value.blocks[id]?.kind === "section",
  ),
);
const stepped = computed(() =>
  sections.value.some((id) => engine.doc.value.blocks[id]?.read === "section"),
);
const sectionCount = computed(() => (stepped.value ? sections.value.length : 0));
const sectionIndex = ref(0);

const goToSection = (index: number): void => {
  const last = sections.value.length - 1;
  if (last < 0) return;
  sectionIndex.value = Math.min(Math.max(index, 0), last);
};
const nextSection = (): void => goToSection(sectionIndex.value + 1);
const previousSection = (): void => goToSection(sectionIndex.value - 1);

const visibleIds = computed(() => {
  if (!stepped.value) return engine.doc.value.root;
  const current = sections.value[sectionIndex.value];
  return current ? [current] : [];
});

watch(
  [sectionIndex, sectionCount],
  ([index, count]) => {
    if (count && index > count - 1) {
      sectionIndex.value = count - 1;
      return;
    }
    if (stepped.value) emit("section-change", { index, count });
  },
  { immediate: true },
);

defineExpose({
  engine,
  sectionIndex,
  sectionCount,
  goToSection,
  nextSection,
  previousSection,
});
</script>

<template>
  <div class="mar-block-editor mar-block-editor-readonly mar-block-reader">
    <div
      class="mar-block-editor-content"
      :style="{ '--mar-block-width': documentWidth }"
    >
      <div ref="surfaceEl" class="mar-block-surface">
        <BlockTree :ids="visibleIds" :engine="engine" />
      </div>
      <div
        v-if="numbering && !(numbering.skipFirst && pageCount === 1)"
        class="mar-block-page-number"
        :data-format="numbering.format"
        :data-position="numbering.position"
        :style="{
          '--mar-page-from': numbering.from,
          '--mar-page-count': pageCount,
        }"
      />
      <div v-if="stepped" class="mar-block-reader-steps">
        <MarIconBtn
          icon="chevron-left"
          title="Previous section"
          :disabled="sectionIndex === 0"
          @click="previousSection"
        />
        <span class="mar-block-reader-step">{{ sectionIndex + 1 }} / {{ sectionCount }}</span>
        <MarIconBtn
          icon="chevron-right"
          title="Next section"
          :disabled="sectionIndex >= sectionCount - 1"
          @click="nextSection"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
.mar-block-reader-steps {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5em;
  padding-top: 0.75em;
  border-top: 1px solid var(--mar-surface-200);
}

.mar-block-reader-step {
  font-variant-numeric: tabular-nums;
  color: var(--mar-text-muted-color);
}
</style>
