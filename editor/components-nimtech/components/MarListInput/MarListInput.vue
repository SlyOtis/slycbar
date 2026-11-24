<script setup lang="ts">
import { computed, ref } from "vue";
import { openModal } from "@/composables/useModals.ts";
import MarDropdown from "../MarDropdown";

const {
  modelValue = [],
  options,
  strict = false,
  label,
  placeholder,
  disabled = false,
  invalid = false,
  fluid = true,
} = defineProps<{
  /** Committed values rendered as removable chips. */
  modelValue?: string[];
  /** Allowed or suggested values driving the suggestion panel. */
  options?: string[];
  /** Restricts added values to options. */
  strict?: boolean;
  /** Field label above the field, in the label style MarField shares. */
  label?: string;
  /** Placeholder shown only while no chips exist. */
  placeholder?: string;
  /** Disables the field and chip removal. */
  disabled?: boolean;
  /** Paints the border red. */
  invalid?: boolean;
  /** Full width layout. */
  fluid?: boolean;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string[]];
}>();

const draft = ref("");
const fieldEl = ref<HTMLDivElement | null>(null);
const inputEl = ref<HTMLInputElement | null>(null);
const panelOpen = ref(false);

const suggestions = computed(() => {
  if (!options) return [];
  const selected = new Set(modelValue.map((v) => v.toLowerCase()));
  const q = draft.value.trim().toLowerCase();
  return options.filter(
    (o) =>
      !selected.has(o.toLowerCase()) && (q === "" || o.toLowerCase().includes(q)),
  );
});

function add(raw: string) {
  const trimmed = raw.trim();
  if (!trimmed) return;
  const match = options?.find(
    (o) => o.toLowerCase() === trimmed.toLowerCase(),
  );
  if (strict && !match) return;
  const value = match ?? trimmed;
  if (modelValue.some((v) => v.toLowerCase() === value.toLowerCase())) return;
  emit("update:modelValue", [...modelValue, value]);
}

function commitDraft() {
  const parts = draft.value.split(",");
  for (const part of parts) add(part);
  draft.value = "";
}

async function openPanel() {
  if (disabled || panelOpen.value || !fieldEl.value) return;
  if (!suggestions.value.length) return;
  panelOpen.value = true;
  const picked = await openModal<string>({
    kind: "dropdown",
    component: MarDropdown,
    anchor: { target: fieldEl.value },
    placement: {
      side: "bottom",
      align: "start",
      offset: 4,
      matchAnchorMinWidth: true,
    },
    backdrop: "invisible",
    props: { options: () => suggestions.value, searchable: false },
  });
  panelOpen.value = false;
  if (!picked) return;
  add(picked);
  draft.value = "";
  inputEl.value?.focus();
}

function onBlur() {
  if (panelOpen.value) return;
  commitDraft();
}

function remove(value: string) {
  emit(
    "update:modelValue",
    modelValue.filter((v) => v !== value),
  );
}

function onInput(event: Event) {
  const target = event.target as HTMLInputElement;
  draft.value = target.value;
  if (target.value.includes(",")) {
    commitDraft();
    return;
  }
  openPanel();
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === "Enter" || event.key === ",") {
    event.preventDefault();
    commitDraft();
  } else if (
    event.key === "Backspace" &&
    draft.value === "" &&
    modelValue.length > 0
  ) {
    event.preventDefault();
    const last = modelValue[modelValue.length - 1];
    remove(last);
    draft.value = last;
    openPanel();
  } else if (event.key === "ArrowDown") {
    event.preventDefault();
    openPanel();
  }
}
</script>

<template>
  <div :class="['mar-field', { 'mar-field-fluid': fluid }]">
    <span v-if="label" class="mar-field-label">{{ label }}</span>
    <div
      ref="fieldEl"
      :class="[
        'mar-list-input',
        {
          'mar-list-input-invalid': invalid,
          'mar-list-input-disabled': disabled,
        },
      ]"
      @click="inputEl?.focus()"
    >
      <span
        v-for="value in modelValue"
        :key="value"
        class="mar-list-input-chip"
      >
        {{ value }}
        <button
          type="button"
          class="mar-list-input-remove"
          :disabled="disabled"
          @click="remove(value)"
        >
          ×
        </button>
      </span>
      <input
        ref="inputEl"
        class="mar-list-input-field"
        :value="draft"
        :placeholder="modelValue.length === 0 ? placeholder : ''"
        :disabled="disabled"
        @input="onInput"
        @keydown="onKeydown"
        @focus="openPanel"
        @blur="onBlur"
      />
    </div>
  </div>
</template>

<style scoped>
.mar-field {
  display: inline-flex;
  flex-direction: column;
  gap: 0.375em;
  position: relative;
}

.mar-field-fluid {
  display: flex;
  width: 100%;
}

.mar-field-label {
  padding-inline: 0.3333em;
  font-size: var(--mar-text-xs);
  font-weight: 500;
  color: var(--mar-text-muted-color);
}

.mar-list-input {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.1875em;
  width: 100%;
  min-height: var(--mar-field-min-height);
  padding: 0.125em 0.3125em;
  background: color-mix(in oklab, var(--mar-surface-0), transparent 30%);
  border: 1px solid var(--glass-border-strong);
  border-radius: calc(var(--mar-field-radius) * 0.9375);
  box-shadow: inset 0 1px 1px color-mix(in oklab, var(--mar-surface-950), transparent 94%);
  box-sizing: border-box;
  transition:
    border-color 0.2s cubic-bezier(0.32, 0.72, 0, 1),
    box-shadow 0.2s cubic-bezier(0.32, 0.72, 0, 1),
    background-color 0.2s cubic-bezier(0.32, 0.72, 0, 1);
}

.mar-list-input:hover:not(:focus-within):not(.mar-list-input-disabled) {
  background: color-mix(in oklab, var(--mar-surface-0), transparent 15%);
  border-color: color-mix(in oklab, var(--mar-surface-900), transparent 72%);
}

.mar-list-input:focus-within {
  background: color-mix(in oklab, var(--mar-surface-0), transparent 5%);
  border-color: color-mix(in oklab, var(--mar-primary-color), transparent 30%);
  box-shadow:
    0 0 0 0.25em color-mix(in oklab, var(--mar-primary-color), transparent 82%),
    0 0.375em 1.25em -0.75em color-mix(in oklab, var(--mar-primary-color), transparent 50%);
}

.mar-list-input-invalid,
.mar-list-input-invalid:hover:not(:focus-within) {
  border-color: color-mix(in oklab, var(--mar-danger-color), transparent 25%);
}

.mar-list-input-invalid:focus-within {
  border-color: var(--mar-danger-color);
  box-shadow: 0 0 0 0.25em color-mix(in oklab, var(--mar-danger-color), transparent 82%);
}

.mar-list-input-disabled {
  opacity: 0.55;
  background: color-mix(in oklab, var(--mar-surface-100), transparent 50%);
  box-shadow: none;
  cursor: not-allowed;
}

.mar-list-input-chip {
  display: inline-flex;
  align-items: center;
  gap: 0.2308em;
  padding: 0.0769em 0.4615em;
  background: var(--mar-highlight-background);
  color: var(--mar-highlight-color);
  border-radius: 0.4615em;
  font-size: var(--mar-text-sm);
  line-height: 1.8462em;
}

.mar-list-input-remove {
  border: none;
  background: transparent;
  color: inherit;
  cursor: pointer;
  padding: 0;
  font-size: var(--mar-text-md);
  line-height: 1;
}

.mar-list-input-remove:disabled {
  cursor: not-allowed;
}

.mar-list-input-field {
  flex: 1;
  min-width: 4.2667em;
  border: none;
  background: transparent;
  color: var(--mar-text-color);
  font-size: var(--mar-field-font-size);
  line-height: 1.4;
  font-family: inherit;
  outline: none;
  padding: 0.2667em 0.4em;
}

.mar-list-input-field::placeholder {
  color: var(--mar-surface-500);
}

@media (prefers-reduced-motion: reduce) {
  .mar-list-input {
    transition: none;
  }
}
</style>
