<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from "vue";
import MarIcon from "../MarIcon";
import MarTextInput from "../MarTextInput";
import type { IconType } from "@/types/icon.types";
import { submenuAnchor, type ModalAnchorRect } from "@/composables/useModals.ts";
import type { BlockOption, BlockOptionChoice } from "@/blockedit/interaction/blockOptions.ts";

const props = defineProps<{
  /** Menu options where each entry runs directly, toggles between two choices, opens a submenu of choices, or pops the host's own submenu out beside the row. Entries marked shared lead the list and a rule separates them from the rest. */
  options: BlockOption[]
  /** How many blocks the options are about. Above one the menu heads the list with the count, so the reader sees the choice reaches all of them. */
  count?: number
}>();
const emit = defineEmits<{
  close: [];
  submenu: [option: BlockOption, anchor: ModalAnchorRect];
}>();

const sub = ref<BlockOption | null>(null);
const rootEl = ref<HTMLElement | null>(null);
const mainEl = ref<HTMLElement | null>(null);
const subEl = ref<HTMLElement | null>(null);
const cursor = ref(0);
const draft = ref("");

const count = computed(() =>
  sub.value ? sub.value.choices?.length ?? 0 : props.options.length,
);

onMounted(() => {
  void nextTick(() => rootEl.value?.focus());
});
watch(
  () => props.options,
  () => {
    sub.value = null;
    cursor.value = 0;
    void nextTick(() => rootEl.value?.focus());
  },
);
watch(sub, (option) => {
  cursor.value = 0;
  draft.value = option?.input?.value ?? "";
  void nextTick(() => {
    if (option?.input) subEl.value?.querySelector<HTMLInputElement>(".mar-text-input")?.select();
    else rootEl.value?.focus();
  });
});
watch(cursor, () => {
  void nextTick(() => {
    const panel = sub.value ? subEl.value : mainEl.value;
    if (!panel) return;
    const items = panel.querySelectorAll<HTMLElement>(".mar-block-more-item");
    const idx = sub.value ? cursor.value + 1 : cursor.value;
    const item = items[idx];
    if (!item) return;
    const top = item.offsetTop;
    const bottom = top + item.offsetHeight;
    if (top < panel.scrollTop) panel.scrollTop = top;
    else if (bottom > panel.scrollTop + panel.clientHeight)
      panel.scrollTop = bottom - panel.clientHeight;
  });
});

const activeChoiceTitle = (option: BlockOption): string =>
  option.choices?.find((c) => c.active)?.title ?? "";

const rowAt = (index: number): HTMLElement | null =>
  mainEl.value?.querySelectorAll<HTMLElement>(".mar-block-more-item")[index] ??
  null;

const onMain = (option: BlockOption, row: HTMLElement | null): void => {
  if (option.submenu) {
    if (row) emit("submenu", option, submenuAnchor(row));
    return;
  }
  const choices = option.choices ?? [];
  if (option.input || choices.length > 2) {
    sub.value = option;
    return;
  }
  if (choices.length) {
    const next = choices.find((c) => !c.active) ?? choices[0];
    next?.run();
    emit("close");
    return;
  }
  option.run?.(row ? submenuAnchor(row) : undefined);
  emit("close");
};

const onChoice = (choice: BlockOptionChoice): void => {
  choice.run();
  emit("close");
};

const onApply = (): void => {
  const input = sub.value?.input;
  if (!input) return;
  void input.apply(draft.value.trim());
  emit("close");
};

const back = (): void => {
  sub.value = null;
};

const onKeydown = (e: KeyboardEvent): void => {
  if (sub.value?.input) {
    e.stopPropagation();
    if (e.key === "Enter") {
      e.preventDefault();
      onApply();
    } else if (e.key === "Escape") {
      e.preventDefault();
      back();
    }
    return;
  }
  if (
    ["ArrowDown", "ArrowUp", "ArrowLeft", "ArrowRight", "Enter", "Backspace", "Escape"].includes(
      e.key,
    )
  ) {
    e.stopPropagation();
  }
  if (e.key === "ArrowDown") {
    e.preventDefault();
    cursor.value = Math.min(cursor.value + 1, count.value - 1);
  } else if (e.key === "ArrowUp") {
    e.preventDefault();
    if (sub.value && cursor.value === 0) {
      back();
    } else {
      cursor.value = Math.max(cursor.value - 1, 0);
    }
  } else if (e.key === "Backspace") {
    if (sub.value) {
      e.preventDefault();
      back();
    }
  } else if (e.key === "Enter") {
    e.preventDefault();
    if (sub.value) {
      const choice = sub.value.choices?.[cursor.value];
      if (choice) onChoice(choice);
    } else {
      const option = props.options[cursor.value];
      if (option) onMain(option, rowAt(cursor.value));
    }
  } else if (e.key === "ArrowRight") {
    const option = props.options[cursor.value];
    if (
      !sub.value &&
      option &&
      (option.submenu || option.input || (option.choices?.length ?? 0) > 2)
    ) {
      e.preventDefault();
      onMain(option, rowAt(cursor.value));
    }
  } else if (e.key === "ArrowLeft") {
    if (sub.value) {
      e.preventDefault();
      back();
    }
  } else if (e.key === "Escape") {
    e.preventDefault();
    if (sub.value) back();
    else emit("close");
  }
};
</script>

<template>
  <div
    ref="rootEl"
    class="mar-block-more"
    tabindex="0"
    @keydown="onKeydown"
  >
    <div class="mar-block-more-track" :class="{ 'mar-block-more-sub': sub }">
      <div ref="mainEl" class="mar-block-more-panel">
        <div v-if="(props.count ?? 1) > 1" class="mar-block-more-head">
          <MarIcon icon="copy" class="mar-block-more-icon" />
          <span class="mar-block-more-title">{{ props.count }} blocks selected</span>
        </div>
        <template v-for="(option, i) in props.options" :key="`o-${i}`">
          <div
            v-if="i > 0 && props.options[i - 1]?.shared && !option.shared"
            class="mar-block-more-split"
          />
          <button
            type="button"
            :class="['mar-block-more-item', { 'mar-block-more-item-cursor': !sub && cursor === i }]"
            @mouseenter="cursor = i"
            @click="onMain(option, $event.currentTarget as HTMLElement)"
          >
            <MarIcon :icon="(option.icon as IconType)" class="mar-block-more-icon" />
            <span class="mar-block-more-text">
              <span class="mar-block-more-title">{{ option.title }}</span>
              <span v-if="option.description" class="mar-block-more-desc">{{
                option.description
              }}</span>
            </span>
            <MarIcon
              v-if="option.submenu || option.input || (option.choices && option.choices.length > 2)"
              icon="chevron-right"
              class="mar-block-more-trail"
            />
            <span
              v-else-if="option.choices && option.choices.length === 2"
              class="mar-block-more-trail mar-block-more-trail-value"
            >{{ activeChoiceTitle(option) }}</span>
          </button>
        </template>
      </div>
      <div ref="subEl" class="mar-block-more-panel">
        <button type="button" class="mar-block-more-item mar-block-more-back" @click="back">
          <MarIcon icon="arrow-left" class="mar-block-more-icon" />
          <span class="mar-block-more-title">{{ sub?.title }}</span>
        </button>
        <form v-if="sub?.input" class="mar-block-more-input" @submit.prevent="onApply">
          <MarTextInput v-model="draft" :placeholder="sub.input.placeholder" />
          <span v-if="sub.description" class="mar-block-more-desc">{{ sub.description }}</span>
          <button type="submit" class="mar-block-more-item mar-block-more-apply">
            <MarIcon icon="check" class="mar-block-more-icon" />
            <span class="mar-block-more-title">{{ sub.input.action ?? "Apply" }}</span>
          </button>
        </form>
        <button
          v-for="(choice, i) in sub?.input ? [] : sub?.choices ?? []"
          :key="`c-${i}`"
          type="button"
          :class="['mar-block-more-item', { 'mar-block-more-item-active': choice.active, 'mar-block-more-item-cursor': sub && cursor === i }]"
          @mouseenter="cursor = i"
          @click="onChoice(choice)"
        >
          <MarIcon
            v-if="choice.icon"
            :icon="(choice.icon as IconType)"
            class="mar-block-more-icon"
          />
          <span class="mar-block-more-text">
            <span class="mar-block-more-title">{{ choice.title }}</span>
            <span v-if="choice.description" class="mar-block-more-desc">{{
              choice.description
            }}</span>
          </span>
          <MarIcon v-if="choice.active" icon="check" class="mar-block-more-trail" />
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.mar-block-more {
  background: var(--mar-surface-0);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 12px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.12);
  width: 17em;
  overflow: hidden;
  font-family: inherit;
}

.mar-block-more-track {
  display: flex;
  align-items: flex-start;
  width: 200%;
  transition: transform 0.25s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-block-more-sub {
  transform: translateX(-50%);
}

.mar-block-more-panel {
  width: 50%;
  flex: 0 0 50%;
  padding: 0;
  max-height: 22em;
  overflow-y: auto;
  scrollbar-width: thin;
  scrollbar-color: var(--mar-surface-300) transparent;
}

.mar-block-more-track:not(.mar-block-more-sub) > .mar-block-more-panel:last-child,
.mar-block-more-track.mar-block-more-sub > .mar-block-more-panel:first-child {
  max-height: 0;
  overflow: hidden;
}

.mar-block-more-item {
  display: flex;
  align-items: center;
  gap: 0.6667em;
  width: 100%;
  padding: 0.5833em 0.8333em;
  border: none;
  background: transparent;
  cursor: pointer;
  font-size: 0.75em;
  color: var(--mar-surface-700);
  text-align: left;
  font-family: inherit;
  transition: background 0.1s ease, color 0.1s ease;
}

.mar-block-more:focus {
  outline: none;
}

.mar-block-more-item-cursor {
  background: var(--mar-surface-100);
  color: var(--mar-text-color);
}

.mar-block-more-item-active {
  color: var(--mar-primary-color);
}

.mar-block-more-split {
  height: 1px;
  margin: 0.25em 0;
  background: var(--mar-content-border-color);
}

.mar-block-more-head {
  display: flex;
  align-items: center;
  gap: 0.6667em;
  padding: 0.5833em 0.8333em;
  font-size: 0.75em;
  font-weight: 600;
  color: var(--mar-text-color);
  border-bottom: 1px solid var(--mar-content-border-color);
}

.mar-block-more-back {
  font-weight: 600;
  color: var(--mar-text-color);
  border-bottom: 1px solid var(--mar-content-border-color);
  border-radius: 0;
}

.mar-block-more-input {
  display: flex;
  flex-direction: column;
  gap: 0.5em;
  padding: 0.6667em 0.8333em 0;
  font-size: 0.75em;
}

.mar-block-more-apply {
  margin: 0 -0.8333em;
  width: calc(100% + 1.6667em);
  font-size: 1em;
  border-top: 1px solid var(--mar-content-border-color);
  color: var(--mar-primary-color);
}

.mar-block-more-apply .mar-block-more-icon {
  color: var(--mar-primary-color);
}

.mar-block-more-apply:hover {
  background: var(--mar-surface-100);
}

.mar-block-more-icon {
  font-size: 1.3333em;
  color: var(--mar-surface-500);
  width: 1em;
  flex-shrink: 0;
}

.mar-block-more-item-active .mar-block-more-icon {
  color: var(--mar-primary-color);
}

.mar-block-more-text {
  display: flex;
  flex-direction: column;
  min-width: 0;
  flex: 1 1 auto;
}

.mar-block-more-title {
  font-weight: 500;
  flex: 1 1 auto;
}

.mar-block-more-desc {
  font-size: 0.8333em;
  color: var(--mar-surface-500);
  margin-top: 0.1em;
}

.mar-block-more-trail {
  font-size: 0.9167em;
  color: var(--mar-surface-400);
  flex-shrink: 0;
}

.mar-icon.mar-block-more-trail {
  font-size: 1.3333em;
}

.mar-block-more-trail-value {
  margin-left: auto;
  font-weight: 500;
  color: var(--mar-text-muted-color);
  white-space: nowrap;
}
</style>
