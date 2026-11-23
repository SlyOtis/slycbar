<script setup lang="ts">
import {
  computed,
  nextTick,
  onMounted,
  onBeforeUnmount,
  ref,
  useAttrs,
  watch,
} from "vue";
import type {
  MarInlineTextInputKeyword,
  MarInlineTextInputMatch,
  MarInlineTextInputMatchRange,
  MarInlineTextInputNavigate,
  MarInlineTextInputType,
  MarInlineTextInputUnderline,
} from "@/types/inlineTextInput.types";

defineOptions({ inheritAttrs: false });

const props = withDefaults(
  defineProps<{
    /** Bound value; number mode emits clamped numbers or null when empty. */
    modelValue: string | number | null | undefined;
    /** Text renders freely, number renders a numeric inputmode field, percent adds a percent sign and clamps to 0 through 100. */
    type?: MarInlineTextInputType;
    /** Placeholder shown and measured while the value is empty. */
    placeholder?: string;
    /** Lower clamp in the numeric modes, defaulting to 0 in percent mode. */
    min?: number;
    /** Upper clamp in the numeric modes, defaulting to 100 in percent mode. */
    max?: number;
    /** Increment of the numeric modes; its decimals set the precision a typed value rounds to. */
    step?: number;
    /** Minimum character width the field keeps while shorter. */
    minChars?: number;
    /** Blocks input and dims the field. */
    disabled?: boolean;
    /** Accessible label for the bare input. */
    ariaLabel?: string;
    /** Keyword prefixes marked bold and reported through the match event. */
    keywords?: MarInlineTextInputKeyword[];
    /** Resting underline of the field; hover and focus color it primary. */
    underline?: MarInlineTextInputUnderline;
    /** Horizontal alignment of the value. */
    align?: "start" | "center";
  }>(),
  {
    type: "text",
    placeholder: "",
    min: undefined,
    max: undefined,
    step: 1,
    minChars: 1,
    disabled: false,
    ariaLabel: undefined,
    keywords: () => [],
    underline: "none",
    align: "start",
  },
);

const emit = defineEmits<{
  (e: "update:modelValue", value: string | number | null): void;
  (e: "match", value: MarInlineTextInputMatch | null): void;
  (e: "navigate", value: MarInlineTextInputNavigate): void;
  (e: "submit"): void;
  (e: "back"): void;
}>();

const numeric = computed(
  () => props.type === "number" || props.type === "percent",
);

const lower = computed(() =>
  props.min !== undefined ? props.min : props.type === "percent" ? 0 : undefined,
);

const upper = computed(() =>
  props.max !== undefined
    ? props.max
    : props.type === "percent"
      ? 100
      : undefined,
);

const attrs = useAttrs();

const inputEl = ref<HTMLInputElement | null>(null);

const typing = ref<string | null>(null);

const displayValue = computed(() => {
  if (typing.value !== null) return typing.value;
  const v = props.modelValue;
  if (v === null || v === undefined) return "";
  return String(v);
});

const computeMatch = (raw: string): MarInlineTextInputMatchRange | null => {
  const list = props.keywords;
  if (!list || list.length === 0) return null;
  if (!raw) return null;
  for (const kw of list) {
    const sep = kw.separator ?? ":";
    const idx = raw.indexOf(sep);
    if (idx <= 0) continue;
    const head = raw.slice(0, idx);
    const headLower = head.toLowerCase();
    if (!kw.aliases.some((a) => a.toLowerCase() === headLower)) continue;
    return {
      start: 0,
      end: idx + sep.length,
      head,
      separator: sep,
      term: raw.slice(idx + sep.length).trim(),
      key: kw.key,
    };
  }
  return null;
};

const matchResult = computed<MarInlineTextInputMatchRange | null>(() =>
  computeMatch(displayValue.value),
);

const beforeMarked = computed(() => {
  const m = matchResult.value;
  if (!m) return "";
  return displayValue.value.slice(0, m.start);
});

const markedText = computed(() => {
  const m = matchResult.value;
  if (!m) return "";
  return displayValue.value.slice(m.start, m.end);
});

const afterMarked = computed(() => {
  const m = matchResult.value;
  if (!m) return "";
  return displayValue.value.slice(m.end);
});

let lastEmittedKey: string | null | undefined = undefined;
let lastEmittedTerm: string | null = null;

watch(
  matchResult,
  (m) => {
    if (!m) {
      if (lastEmittedKey === null && lastEmittedTerm === null) return;
      lastEmittedKey = null;
      lastEmittedTerm = null;
      emit("match", null);
      return;
    }
    if (lastEmittedKey === m.key && lastEmittedTerm === m.term) return;
    lastEmittedKey = m.key;
    lastEmittedTerm = m.term;
    emit("match", {
      key: m.key,
      head: m.head,
      separator: m.separator,
      term: m.term,
    });
  },
  { immediate: true },
);

const overlayFont = ref<string>("");
const overlayPadding = ref<string>("0");
const overlayLetterSpacing = ref<string>("normal");

const refreshOverlayStyle = () => {
  const el = inputEl.value;
  if (!el) return;
  const s = getComputedStyle(el);
  overlayFont.value = `${s.fontStyle} ${s.fontVariantCaps} ${s.fontWeight} ${s.fontSize}/${s.lineHeight} ${s.fontFamily}`;
  overlayPadding.value = `${s.paddingTop} ${s.paddingRight} ${s.paddingBottom} ${s.paddingLeft}`;
  overlayLetterSpacing.value = s.letterSpacing;
};

const measureEl = ref<HTMLSpanElement | null>(null);

const measureWidth = (
  text: string,
  mark?: { start: number; end: number } | null,
): number => {
  const el = inputEl.value;
  const mel = measureEl.value;
  if (!el || !mel) return 24;
  const style = getComputedStyle(el);
  const padL = parseFloat(style.paddingLeft) || 0;
  const padR = parseFloat(style.paddingRight) || 0;
  const bL = parseFloat(style.borderLeftWidth) || 0;
  const bR = parseFloat(style.borderRightWidth) || 0;
  const sample =
    text.length >= props.minChars
      ? text
      : text + "0".repeat(props.minChars - text.length);
  mel.style.font = `${style.fontStyle} ${style.fontVariant} ${style.fontWeight} ${style.fontSize}/${style.lineHeight} ${style.fontFamily}`;
  mel.style.letterSpacing = style.letterSpacing;
  mel.style.fontFeatureSettings = style.fontFeatureSettings;
  mel.style.fontVariantNumeric = style.fontVariantNumeric;
  mel.textContent = "";
  if (
    mark &&
    mark.start >= 0 &&
    mark.end > mark.start &&
    mark.end <= sample.length
  ) {
    const before = sample.slice(0, mark.start);
    const marked = sample.slice(mark.start, mark.end);
    const after = sample.slice(mark.end);
    if (before) mel.appendChild(document.createTextNode(before));
    const markedSpan = document.createElement("span");
    markedSpan.style.fontWeight = "700";
    markedSpan.textContent = marked;
    mel.appendChild(markedSpan);
    if (after) mel.appendChild(document.createTextNode(after));
  } else {
    mel.textContent = sample || " ";
  }
  const measured = mel.getBoundingClientRect().width;
  return Math.ceil(measured) + padL + padR + bL + bR + 2;
};

const widthPx = ref(0);

const refreshWidth = () => {
  const text = displayValue.value || props.placeholder || "";
  const m = matchResult.value;
  const mark = m && displayValue.value ? { start: m.start, end: m.end } : null;
  widthPx.value = measureWidth(text, mark);
};

const refreshAll = () => {
  refreshOverlayStyle();
  refreshWidth();
};

let resizeObserver: ResizeObserver | null = null;

onMounted(() => {
  nextTick(refreshAll);
  if (typeof ResizeObserver !== "undefined" && inputEl.value) {
    resizeObserver = new ResizeObserver(() => refreshAll());
    resizeObserver.observe(inputEl.value);
  }
});

onBeforeUnmount(() => {
  resizeObserver?.disconnect();
  resizeObserver = null;
});

watch(
  () => [
    displayValue.value,
    props.placeholder,
    props.minChars,
    matchResult.value,
  ],
  () => nextTick(refreshAll),
);

const widthStyle = computed(() =>
  widthPx.value ? `${widthPx.value}px` : "auto",
);

const clamp = (n: number): number => {
  let out = n;
  const low = lower.value;
  const high = upper.value;
  if (low !== undefined && out < low) out = low;
  if (high !== undefined && out > high) out = high;
  return out;
};

const decimals = computed(() => {
  const text = String(props.step);
  const dot = text.indexOf(".");
  return dot === -1 ? 0 : text.length - dot - 1;
});

const snap = (n: number): number =>
  clamp(Number(n.toFixed(decimals.value)));

const onInput = (e: Event) => {
  const raw = (e.target as HTMLInputElement).value;
  const measureText = raw || props.placeholder || "";
  const m = raw ? computeMatch(raw) : null;
  widthPx.value = measureWidth(
    measureText,
    m ? { start: m.start, end: m.end } : null,
  );
  if (numeric.value) {
    typing.value = raw;
    const trimmed = raw.trim().replace(",", ".");
    if (trimmed === "") {
      emit("update:modelValue", null);
      return;
    }
    const n = Number(trimmed);
    if (!Number.isFinite(n)) return;
    emit("update:modelValue", snap(n));
    return;
  }
  emit("update:modelValue", raw);
};

let valueAtFocus: string | number | null = null;

const onFocus = () => {
  valueAtFocus = props.modelValue ?? null;
};

const onBlur = () => {
  typing.value = null;
};

const inputMode = computed(() => (numeric.value ? "numeric" : "text"));

const step = (direction: 1 | -1, magnified: boolean) => {
  const base = typeof props.modelValue === "number" ? props.modelValue : 0;
  const amount = props.step * (magnified ? 10 : 1) * direction;
  typing.value = null;
  emit("update:modelValue", snap(base + amount));
};

const onKeydown = (e: KeyboardEvent) => {
  const el = inputEl.value;
  if (!el) return;
  if (e.key === "Escape") {
    e.preventDefault();
    e.stopPropagation();
    typing.value = null;
    if (valueAtFocus !== (props.modelValue ?? null))
      emit("update:modelValue", valueAtFocus);
    el.blur();
    return;
  }
  if (e.key === "Enter") {
    if (e.isComposing) return;
    if (e.shiftKey || e.metaKey || e.ctrlKey) return;
    e.preventDefault();
    emit("submit");
    return;
  }
  if (e.key === "Backspace" && displayValue.value === "") {
    e.preventDefault();
    emit("back");
    return;
  }
  const vertical = e.key === "ArrowUp" || e.key === "ArrowDown";
  if (vertical && numeric.value && !e.altKey) {
    e.preventDefault();
    step(e.key === "ArrowUp" ? 1 : -1, e.shiftKey);
    return;
  }
  if (vertical) {
    e.preventDefault();
    emit("navigate", e.key === "ArrowUp" ? "up" : "down");
    return;
  }
  const caret = el.selectionStart ?? 0;
  const collapsed = caret === (el.selectionEnd ?? 0);
  if (e.key === "ArrowLeft" && collapsed && caret === 0) {
    e.preventDefault();
    emit("navigate", "prev");
    return;
  }
  if (
    e.key === "ArrowRight" &&
    collapsed &&
    caret === displayValue.value.length
  ) {
    e.preventDefault();
    emit("navigate", "next");
  }
};

const focus = (selectAll = false) => {
  const el = inputEl.value;
  if (!el) return;
  el.focus();
  if (selectAll) el.select();
};

defineExpose({ inputEl, focus });
</script>

<template>
  <span
    class="mar-inline-text-input-wrap"
    :data-marked="matchResult ? '1' : null"
    :data-underline="underline"
    :data-align="align"
  >
    <span
      v-if="matchResult"
      class="mar-inline-text-input-overlay"
      :style="{
        font: overlayFont || undefined,
        padding: overlayPadding,
        letterSpacing: overlayLetterSpacing,
      }"
      aria-hidden="true"
      ><span v-if="beforeMarked">{{ beforeMarked }}</span
      ><span class="mar-inline-text-input-overlay-marked">{{
        markedText
      }}</span
      ><span v-if="afterMarked">{{ afterMarked }}</span></span
    >
    <input
      ref="inputEl"
      v-bind="attrs"
      :type="type === 'number' ? 'text' : type"
      :inputmode="inputMode"
      :value="displayValue"
      :placeholder="placeholder"
      :disabled="disabled"
      :aria-label="ariaLabel"
      :class="[
        'mar-inline-text-input',
        (attrs as Record<string, unknown>).class,
      ]"
      :style="{
        ...((attrs as Record<string, unknown>).style as
          | Record<string, string>
          | undefined),
        width: widthStyle,
      }"
      @input="onInput"
      @focus="onFocus"
      @blur="onBlur"
      @keydown="onKeydown"
    />
    <span v-if="type === 'percent'" class="mar-inline-text-input-suffix">%</span>
    <span
      ref="measureEl"
      class="mar-inline-text-input-measure"
      aria-hidden="true"
    />
  </span>
</template>

<style scoped>
.mar-inline-text-input-wrap {
  position: relative;
  display: inline-block;
  line-height: inherit;
}

.mar-inline-text-input-overlay {
  position: absolute;
  inset: 0;
  pointer-events: none;
  white-space: pre;
  color: inherit;
  overflow: hidden;
  text-align: start;
}

.mar-inline-text-input-suffix {
  padding-right: 0.1em;
  color: var(--mar-text-muted-color, currentColor);
}

.mar-inline-text-input-measure {
  position: absolute;
  visibility: hidden;
  pointer-events: none;
  white-space: pre;
  top: -9999px;
  left: -9999px;
}

.mar-inline-text-input-overlay-marked {
  font-weight: 700;
  color: var(--mar-primary-color, currentColor);
}

.mar-inline-text-input-wrap[data-marked="1"] > .mar-inline-text-input {
  color: transparent;
  caret-color: var(--mar-text-color, currentColor);
}

.mar-inline-text-input {
  font: inherit;
  font-variant-numeric: tabular-nums;
  color: inherit;
  background: transparent;
  border: 0;
  border-bottom: 1px solid transparent;
  border-radius: 0;
  padding: 0 0.1em;
  margin: 0;
  outline: none;
  text-align: start;
  min-width: 1ch;
  box-sizing: content-box;
  appearance: textfield;
  transition: border-color 0.15s cubic-bezier(0.32, 0.72, 0, 1);
}

.mar-inline-text-input-wrap[data-align="center"] > .mar-inline-text-input {
  text-align: center;
}

.mar-inline-text-input-wrap[data-align="center"]
  > .mar-inline-text-input-overlay {
  text-align: center;
}

.mar-inline-text-input-wrap[data-underline="dashed"]
  > .mar-inline-text-input {
  border-bottom: 1px dashed
    color-mix(in srgb, currentColor 35%, transparent);
}

.mar-inline-text-input-wrap[data-underline="solid"]
  > .mar-inline-text-input {
  border-bottom: 1px solid
    color-mix(in srgb, currentColor 35%, transparent);
}

.mar-inline-text-input-wrap[data-underline="dashed"]
  > .mar-inline-text-input:hover,
.mar-inline-text-input-wrap[data-underline="solid"]
  > .mar-inline-text-input:hover {
  border-bottom-color: var(--mar-primary-color, currentColor);
}

.mar-inline-text-input-wrap[data-underline="dashed"]
  > .mar-inline-text-input:focus-visible,
.mar-inline-text-input-wrap[data-underline="solid"]
  > .mar-inline-text-input:focus-visible {
  border-bottom-style: solid;
  border-bottom-color: var(--mar-primary-color, currentColor);
}

.mar-inline-text-input::-webkit-outer-spin-button,
.mar-inline-text-input::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}

.mar-inline-text-input:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.mar-inline-text-input::placeholder {
  color: color-mix(in srgb, currentColor 50%, transparent);
}
</style>
