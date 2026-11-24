<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import MarInlineTextInput from "../MarInlineTextInput";
import MarListInput from "../MarListInput";

interface PollResult {
  question: string;
  options: string[];
  votes: number[];
  userVoteIndex: number | null;
  status: string;
}

const props = defineProps<{
  /** Block node whose options carry the linked poll id and the authored question and options. */
  node: {
    options: {
      pollId?: string;
      question?: string;
      options?: string[];
    };
  };
  /** Editor context; an editable editor puts the block in authoring mode. */
  editor?: { isEditable: boolean };
  /** Draws a selection outline around the block. */
  selected: boolean;
  /** Callback persisting question and option edits back into the document. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
  /** Extension options wiring poll creation, resolution, voting, and updates to the consumer. */
  extension: {
    options: {
      create?: (
        question: string,
        options: string[],
      ) => Promise<{ id: string } | null>;
      resolve?: (pollId: string) => Promise<PollResult>;
      vote?: (pollId: string, optionIndex: number) => Promise<PollResult>;
      update?: (
        pollId: string,
        patch: { question?: string; options?: string[] },
      ) => Promise<void>;
    };
  };
}>();

const editable = computed(() => props.editor?.isEditable ?? true);
const pollId = computed(() => props.node.options.pollId ?? "");
const question = computed(() => props.node.options.question ?? "");
const options = computed(() =>
  Array.isArray(props.node.options.options) ? props.node.options.options : [],
);

const result = ref<PollResult | null>(null);
const loading = ref(false);
const voting = ref(false);

const canVote = computed(() => !!props.extension.options.vote);

let createTimer: ReturnType<typeof window.setTimeout> | undefined;
let updateTimer: ReturnType<typeof window.setTimeout> | undefined;

const persist = (): void => {
  const q = question.value.trim();
  const opts = options.value.filter((o) => o.trim() !== "");
  if (!q || opts.length < 2) return;
  if (!pollId.value) {
    const create = props.extension.options.create;
    if (!create) return;
    window.clearTimeout(createTimer);
    createTimer = window.setTimeout(async () => {
      const ref = await create(q, opts);
      if (ref) props.updateAttributes({ pollId: ref.id });
    }, 500);
    return;
  }
  const update = props.extension.options.update;
  if (!update) return;
  window.clearTimeout(updateTimer);
  updateTimer = window.setTimeout(() => {
    void update(pollId.value, { question: q, options: opts });
  }, 500);
};

const onQuestion = (next: string | number | null): void => {
  props.updateAttributes({ question: String(next ?? "") });
  persist();
};

const onOptions = (next: string[]): void => {
  props.updateAttributes({ options: next.filter((o) => o.trim() !== "") });
  persist();
};

const load = async (): Promise<void> => {
  const resolve = props.extension.options.resolve;
  if (!pollId.value || !resolve) return;
  loading.value = true;
  try {
    result.value = await resolve(pollId.value);
  } finally {
    loading.value = false;
  }
};

watch(pollId, load, { immediate: true });

const displayQuestion = computed(() => result.value?.question ?? question.value);
const displayOptions = computed(() => result.value?.options ?? options.value);
const totalVotes = computed(() =>
  (result.value?.votes ?? []).reduce((sum, v) => sum + v, 0),
);
const hasVoted = computed(() => result.value?.userVoteIndex != null);
const closed = computed(() => result.value?.status === "closed");
const showResults = computed(() => hasVoted.value || closed.value);

const percent = (index: number): number => {
  const v = result.value?.votes?.[index] ?? 0;
  return totalVotes.value ? Math.round((v / totalVotes.value) * 100) : 0;
};

const onVote = async (index: number): Promise<void> => {
  const vote = props.extension.options.vote;
  if (!vote || !pollId.value || voting.value || hasVoted.value || closed.value)
    return;
  voting.value = true;
  try {
    result.value = await vote(pollId.value, index);
  } finally {
    voting.value = false;
  }
};
</script>

<template>
  <NodeViewWrapper
    :class="['mar-be-poll', { 'mar-be-poll-selected': selected }]"
    contenteditable="false"
  >
    <template v-if="editable">
      <span class="mar-be-poll-question">
        <MarInlineTextInput
          :model-value="question"
          placeholder="Question"
          aria-label="Question"
          underline="dashed"
          :min-chars="16"
          @update:model-value="onQuestion"
        />
      </span>
      <MarListInput
        :model-value="options"
        label="Options"
        placeholder="Add option"
        @update:model-value="onOptions"
      />
    </template>
    <template v-else>
      <div class="mar-be-poll-question">{{ displayQuestion }}</div>
      <div class="mar-be-poll-options">
        <button
          v-for="(option, index) in displayOptions"
          :key="index"
          type="button"
          class="mar-be-poll-option"
          :class="{ 'mar-be-poll-option-picked': result?.userVoteIndex === index }"
          :disabled="!canVote || voting || hasVoted || closed"
          @click="onVote(index)"
        >
          <span
            v-if="showResults"
            class="mar-be-poll-option-fill"
            :style="{ width: percent(index) + '%' }"
          />
          <span class="mar-be-poll-option-label">{{ option }}</span>
          <span v-if="showResults" class="mar-be-poll-option-pct">
            {{ percent(index) }}%
          </span>
        </button>
      </div>
      <div v-if="showResults" class="mar-be-poll-total">
        {{ totalVotes }} votes
      </div>
    </template>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-poll {
  margin: 0.5em 0;
  display: flex;
  flex-direction: column;
  gap: 0.5em;
}

.mar-be-poll-selected {
  outline: 1px solid var(--mar-surface-400);
  outline-offset: 3px;
}

.mar-be-poll-question {
  font-size: 0.9375em;
  font-weight: 600;
  color: var(--mar-text-color);
}

.mar-be-poll-options {
  display: flex;
  flex-direction: column;
  gap: 0.375em;
}

.mar-be-poll-option {
  position: relative;
  display: flex;
  align-items: center;
  gap: 0.5714em;
  border: none;
  background: none;
  color: var(--mar-text-color);
  font-family: inherit;
  font-size: 0.875em;
  text-align: left;
  padding: 0.5em 0.7143em;
  cursor: pointer;
  transition: color 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-be-poll-option:hover:not(:disabled) {
  color: var(--mar-primary-color);
}

.mar-be-poll-option:disabled {
  cursor: default;
}

.mar-be-poll-option-picked {
  color: var(--mar-primary-color);
  font-weight: 600;
}

.mar-be-poll-option-fill {
  position: absolute;
  inset: 0 auto 0 0;
  background: var(--mar-highlight-background);
  transition: width 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-be-poll-option-label {
  position: relative;
  flex: 1;
  min-width: 0;
}

.mar-be-poll-option-pct {
  position: relative;
  flex-shrink: 0;
  color: var(--mar-surface-500);
  font-size: 0.8571em;
}

.mar-be-poll-total {
  font-size: 0.75em;
  color: var(--mar-surface-500);
}
</style>
