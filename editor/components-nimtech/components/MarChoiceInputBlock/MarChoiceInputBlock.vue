<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import { useMarInputAnswers, marInputKey } from "@/blockedit/inputAnswers";
import MarDropdownInput from "../MarDropdownInput";
import MarIcon from "../MarIcon";
import MarIconBtn from "../MarIconBtn";
import MarInlineTextInput from "../MarInlineTextInput";

const props = defineProps<{
  /** Block node whose options carry the answer key, question label, option list, multi flag, required flag, and read view gating. */
  node: {
    options: {
      key?: string;
      label?: string;
      options?: string[];
      multi?: boolean;
      required?: boolean;
      interactive?: boolean;
    };
  };
  /** Editor context; an editable editor puts the block in authoring mode. */
  editor: { isEditable: boolean };
  /** Draws a selection outline around the block. */
  selected: boolean;
  /** Callback persisting label and option edits back into the document. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
}>();

const editable = computed(() => props.editor?.isEditable ?? true);
const label = computed(() => String(props.node.options.label ?? ""));
const options = computed(() =>
  Array.isArray(props.node.options.options) ? props.node.options.options : [],
);
const multi = computed(() => props.node.options.multi === true);
const required = computed(() => props.node.options.required === true);
const answerable = computed(() => props.node.options.interactive !== false);
const answerKey = computed(() => marInputKey(props.node.options));

const answers = useMarInputAnswers();
const value = computed(() => answers?.values[answerKey.value] ?? "");
const singleValue = computed(() => (value.value === "" ? null : value.value));
const multiValue = computed(() =>
  value.value === "" ? [] : value.value.split("|"),
);

type RowInput = { focus: () => void } | null;

const rows = ref<string[]>([]);
const rowEls = ref<RowInput[]>([]);

const filled = (list: string[]): string[] =>
  list.filter((option) => option.trim() !== "");

const trail = (): void => {
  if (rows.value.length === 0 || rows.value[rows.value.length - 1] !== "") {
    rows.value.push("");
  }
};

watch(
  options,
  (next) => {
    const current = filled(rows.value);
    if (next.length === current.length && next.every((o, i) => o === current[i])) return;
    rows.value = [...next];
    trail();
  },
  { immediate: true, deep: true },
);

const persist = (): void =>
  props.updateAttributes({ options: filled(rows.value) });

const setRowEl = (el: unknown, index: number): void => {
  rowEls.value[index] = el as RowInput;
};

const focusRow = (index: number): void => {
  void nextTick(() => rowEls.value[index]?.focus());
};

const onRow = (index: number, next: string | number | null): void => {
  rows.value[index] = String(next ?? "");
  trail();
  persist();
};

const onEnter = (index: number): void => {
  rows.value.splice(index + 1, 0, "");
  focusRow(index + 1);
};

const onBackspace = (index: number, event: KeyboardEvent): void => {
  if (rows.value[index] !== "" || rows.value.length <= 1) return;
  event.preventDefault();
  removeRow(index);
  focusRow(Math.max(0, index - 1));
};

const removeRow = (index: number): void => {
  rows.value.splice(index, 1);
  rowEls.value.splice(index, 1);
  trail();
  persist();
};

const onValue = (next: string | string[] | null): void => {
  if (!answers) return;
  if (Array.isArray(next)) answers.set(answerKey.value, next.join("|"));
  else answers.set(answerKey.value, next ?? "");
};
</script>

<template>
  <NodeViewWrapper
    :class="['mar-be-input', { 'mar-be-input-selected': selected }]"
    contenteditable="false"
  >
    <template v-if="editable">
      <div class="mar-be-input-head">
        <span class="mar-be-input-label">
          <MarInlineTextInput
            :model-value="label"
            placeholder="Question"
            aria-label="Question"
            underline="dashed"
            :min-chars="16"
            @update:model-value="
              (next) => props.updateAttributes({ label: String(next ?? '') })
            "
          />
          <span v-if="required" class="mar-be-input-required">*</span>
        </span>
      </div>
      <div class="mar-be-choice-rows">
        <div
          v-for="(row, index) in rows"
          :key="index"
          class="mar-be-choice-row"
        >
          <MarIcon
            :icon="multi ? 'check-square' : 'circle'"
            class="mar-be-choice-glyph"
          />
          <MarInlineTextInput
            :ref="(el) => setRowEl(el, index)"
            :model-value="row"
            :placeholder="index === rows.length - 1 ? 'Add option' : 'Option'"
            aria-label="Option"
            underline="dashed"
            :min-chars="18"
            @update:model-value="(next) => onRow(index, next)"
            @keydown.enter.prevent="onEnter(index)"
            @keydown.backspace="onBackspace(index, $event)"
          />
          <MarIconBtn
            v-if="index < rows.length - 1"
            icon="trash"
            severity="danger"
            class="mar-be-choice-remove"
            @click="removeRow(index)"
          />
        </div>
      </div>
    </template>
    <MarDropdownInput
      v-else-if="multi"
      :label="label"
      :options="options"
      :model-value="multiValue"
      :select-min="0"
      :select-max="options.length"
      :required="required"
      :disabled="!answers || !answerable"
      @update:model-value="onValue"
    />
    <MarDropdownInput
      v-else
      :label="label"
      :options="options"
      :model-value="singleValue"
      :required="required"
      :disabled="!answers || !answerable"
      @update:model-value="onValue"
    />
  </NodeViewWrapper>
</template>

<style scoped>
.mar-be-input {
  margin: 0.5em 0;
  display: flex;
  flex-direction: column;
  gap: 0.375em;
}

.mar-be-input-selected {
  outline: 1px solid var(--mar-surface-400);
  outline-offset: 3px;
}

.mar-be-input-head {
  display: flex;
  align-items: center;
  gap: 0.5em;
}

.mar-be-input-label {
  flex: 1;
  min-width: 0;
  font-size: 0.9375em;
  font-weight: 600;
  color: var(--mar-text-color);
}

.mar-be-input-required {
  color: var(--mar-danger-color);
  margin-left: 0.1333em;
}

.mar-be-choice-rows {
  display: flex;
  flex-direction: column;
  gap: 0.125em;
}

.mar-be-choice-row {
  display: flex;
  align-items: center;
  gap: 0.5714em;
  font-size: 0.875em;
  color: var(--mar-text-color);
}

.mar-be-choice-glyph {
  flex-shrink: 0;
  font-size: 1.1429em;
  color: var(--mar-surface-500);
}

.mar-be-choice-remove {
  opacity: 0;
  transition: opacity 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-be-choice-row:hover .mar-be-choice-remove,
.mar-be-choice-row:focus-within .mar-be-choice-remove {
  opacity: 1;
}
</style>
