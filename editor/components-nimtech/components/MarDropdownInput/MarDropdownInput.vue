<script setup lang="ts">
import { computed, inject, ref, toRef, useId } from "vue";
import { openModal } from "@/composables/useModals.ts";
import MarIcon from "@/components/MarIcon";
import MarIconBtn from "@/components/MarIconBtn";
import MarButton from "@/components/MarButton";
import MarDropdown, {
  type MarDropdownOption,
} from "../MarDropdown";
import type { MarInlineTextInputNavigate } from "../MarInlineTextInput";
import { MAR_INLINE_INPUT_FIELD } from "../MarInlineInput";
import { resolveDropdownOptions } from "@/utils/dropdown";

export type { MarDropdownOption } from "../MarDropdown";

const {
  modelValue = null,
  defaultValue = null,
  options,
  label = "",
  placeholder = "",
  disabled = false,
  invalid = false,
  error = "",
  required = false,
  showClear = false,
  searchable = true,
  searchPlaceholder = "Search…",
  inline = false,
  button = false,
  filter = false,
  icon = "",
  selectMin,
  selectMax,
  emptyAction,
  emptyActionLabel,
  search = undefined,
  manualFilter = false,
  hasMore = false,
} = defineProps<{
  /** Selected value in single mode or selected values array in select mode. */
  modelValue?: string | string[] | null;
  /** The value the field starts from, such as the default columns of a column picker; the icon and filter triggers show active only while the model differs from it, and with none given an empty model is the default. */
  defaultValue?: string | string[] | null;
  /** Options to offer, either bare strings used as both label and value or full option objects. */
  options: Array<string | MarDropdownOption>;
  /** Label rendered above the field in the form style, and the filter name in filter mode; ignored in the inline, button and icon modes. */
  label?: string;
  /** Text shown when nothing is selected, also the button label in button mode and the tooltip title in icon mode. */
  placeholder?: string;
  /** Blocks opening the panel and dims the trigger. */
  disabled?: boolean;
  /** Paints the trigger border red in the form style; ignored in the inline, button and icon modes. */
  invalid?: boolean;
  /** Error text under the field, painting the border red. */
  error?: string;
  /** Appends a red asterisk to the label. */
  required?: boolean;
  /** Offers the panel head clear that empties the field; ignored in select mode, where the panel head already carries clear all. */
  showClear?: boolean;
  /** Passed to the panel to show its search input. */
  searchable?: boolean;
  /** Placeholder for the panel search input. */
  searchPlaceholder?: string;
  /** Inline style: the trigger renders exactly like the read value it replaces, with no box, border, padding or height change, and the chevron sits inside that footprint. Always on inside a MarInlineInput row. */
  inline?: boolean;
  /** Renders the trigger as a small secondary button with a chevron. */
  button?: boolean;
  /** Renders the trigger as a filter segment of a MarToggleGroup actions strip: the label as text, the selected value or count, and a chevron. */
  filter?: boolean;
  /** Renders the trigger as a ghost circle button with this icon, taking precedence over the filter and button modes. */
  icon?: string;
  /** Minimum number of selected values; its presence switches to select mode with chips and a string array model. */
  selectMin?: number;
  /** Maximum number of selected values; its presence switches to select mode with chips and a string array model. */
  selectMax?: number;
  /** Called with the trimmed search text when the search returns no matches, such as to create a missing tag; passed to the panel to show a clickable action row below the empty state. */
  emptyAction?: (query: string) => void;
  /** Label for the empty action row in the panel. */
  emptyActionLabel?: string;
  /** Search text of the panel, seeding its search input and following later changes; bind with v-model:search to read every keystroke. */
  search?: string;
  /** Turns off the panel's local label filter, so the host filters on its server from update:search and passes the matching options. */
  manualFilter?: boolean;
  /** Trails the panel list with a loading row that emits more once it scrolls into view, for the next page of options. */
  hasMore?: boolean;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string | string[] | null];
  change: [value: string | string[] | null];
  count: [value: string, count: number];
  close: [];
  navigate: [value: MarInlineTextInputNavigate];
  back: [];
  "update:search": [value: string];
  more: [];
}>();

const isSelect = computed(
  () => selectMin !== undefined || selectMax !== undefined,
);

const resolved = computed<MarDropdownOption[]>(() => resolveDropdownOptions(options));

const selected = computed<MarDropdownOption | null>(() =>
  typeof modelValue === "string"
    ? resolved.value.find((o) => o.value === modelValue) ?? null
    : null,
);

const values = computed<string[]>(() =>
  Array.isArray(modelValue) ? modelValue : [],
);

const selectedSet = computed(() => new Set(values.value));

const selectedLabels = computed(() =>
  resolved.value
    .filter((o) => selectedSet.value.has(o.value))
    .map((o) => o.label),
);

const hasValue = computed(() =>
  isSelect.value ? values.value.length > 0 : selected.value !== null,
);

const changed = computed(() => {
  if (isSelect.value) {
    const base = new Set(Array.isArray(defaultValue) ? defaultValue : []);
    return values.value.length !== base.size || values.value.some((v) => !base.has(v));
  }
  const base = typeof defaultValue === "string" ? defaultValue : null;
  return (selected.value?.value ?? null) !== base;
});

const filterValue = computed(() =>
  isSelect.value
    ? values.value.length
      ? String(values.value.length)
      : ""
    : selected.value?.label ?? "",
);

const field = inject(MAR_INLINE_INPUT_FIELD, null);

const isFilter = computed(() => filter && !icon);

const isInline = computed(() => (inline || !!field) && !button && !icon && !filter);

const decorated = computed(() => !isInline.value && !button && !icon && !filter);

const labelId = useId();
const labelledBy = computed(() => (decorated.value && label ? labelId : field?.labelId));

const rootClasses = computed(() => [
  "mar-dropdown",
  {
    "mar-dropdown-inline": isInline.value,
    "mar-dropdown-fluid": decorated.value,
    "mar-ifta-label": decorated.value && !!label,
  },
]);

const triggerEl = ref<HTMLDivElement | null>(null);
const circleEl = ref<{ $el?: HTMLElement } | null>(null);
const buttonEl = ref<{ $el?: HTMLElement } | null>(null);
const filterEl = ref<HTMLButtonElement | null>(null);
const isOpen = ref(false);

const openPanel = async () => {
  if (disabled || isOpen.value) return;
  const anchorEl = icon
    ? circleEl.value?.$el ?? null
    : isFilter.value
      ? filterEl.value
      : button
        ? buttonEl.value?.$el ?? null
        : triggerEl.value;
  if (!anchorEl) return;
  isOpen.value = true;
  const result = await openModal<string | null | undefined>({
    kind: "dropdown",
    component: MarDropdown,
    anchor: { target: anchorEl },
    placement: {
      side: "bottom",
      align: "start",
      offset: 4,
      matchAnchorMinWidth: true,
    },
    backdrop: "invisible",
    props: {
      options: toRef(() => options),
      modelValue: toRef(() => modelValue),
      searchable,
      searchPlaceholder,
      showClear,
      selectMin,
      selectMax,
      emptyAction,
      emptyActionLabel,
      search: toRef(() => search),
      manualFilter,
      hasMore: toRef(() => hasMore),
    },
    on: {
      "update:search": (value: unknown) => emit("update:search", value as string),
      more: () => emit("more"),
      count: (value: unknown, next: unknown) => {
        emit("count", value as string, next as number);
      },
      ...(isSelect.value
        ? {
            change: (next: unknown) => {
              emit("update:modelValue", next as string[]);
              emit("change", next as string[]);
            },
          }
        : {}),
    },
  });
  isOpen.value = false;
  if (isSelect.value || result === undefined) {
    emit("close");
    return;
  }
  emit("update:modelValue", result);
  emit("change", result);
  emit("close");
};

const clear = () => {
  const cleared = isSelect.value ? [] : null;
  emit("update:modelValue", cleared);
  emit("change", cleared);
};

const onKeydown = (e: KeyboardEvent) => {
  if (isOpen.value || disabled) return;
  if (e.key === "Enter") {
    if (e.isComposing) return;
    if (e.shiftKey || e.metaKey || e.ctrlKey) return;
    e.preventDefault();
    openPanel();
    return;
  }
  if (e.key === " " || e.key === "ArrowDown") {
    e.preventDefault();
    openPanel();
    return;
  }
  if (e.key === "Backspace") {
    e.preventDefault();
    if (hasValue.value) {
      clear();
      return;
    }
    emit("back");
    return;
  }
  if (e.key === "ArrowUp") {
    e.preventDefault();
    emit("navigate", "up");
    return;
  }
  if (e.key === "ArrowLeft") {
    e.preventDefault();
    emit("navigate", "prev");
    return;
  }
  if (e.key === "ArrowRight") {
    e.preventDefault();
    emit("navigate", "next");
  }
};

const focus = () => {
  const el =
    triggerEl.value ?? circleEl.value?.$el ?? filterEl.value ?? buttonEl.value?.$el ?? null;
  el?.focus();
};

defineExpose({ focus });
</script>

<template>
  <div
    :class="rootClasses"
    :data-open="isOpen ? '1' : '0'"
    :data-disabled="disabled ? '1' : '0'"
  >
    <MarIconBtn
      v-if="icon"
      ref="circleEl"
      class="mar-dropdown-icon-trigger"
      :icon="icon"
      :active="changed"
      :tooltip="placeholder"
      :disabled="disabled"
      @click="openPanel"
    />
    <button
      v-else-if="isFilter"
      ref="filterEl"
      type="button"
      class="mar-dropdown-filter-trigger"
      :data-active="changed ? '1' : null"
      :aria-expanded="isOpen"
      :disabled="disabled"
      @click="openPanel"
    >
      <span class="mar-dropdown-filter-label">{{ label || placeholder }}{{ filterValue ? (isSelect ? " ·" : ":") : "" }}</span>
      <span v-if="filterValue" class="mar-dropdown-filter-value" :title="isSelect ? selectedLabels.join(', ') : filterValue">{{ filterValue }}</span>
      <MarIcon
        icon="chevron-down"
        class="mar-dropdown-chevron"
        :data-open="isOpen ? '1' : '0'"
      />
    </button>
    <MarButton
      v-else-if="button"
      ref="buttonEl"
      class="mar-dropdown-button-trigger"
      severity="secondary"
      :disabled="disabled"
      @click="openPanel"
    >
      <span>{{ placeholder }}</span>
      <MarIcon icon="chevron-down" class="mar-dropdown-button-chevron" />
    </MarButton>
    <div
      v-else
      ref="triggerEl"
      :class="[
        'mar-dropdown-trigger',
        {
          'mar-dropdown-trigger-invalid': invalid || !!error,
        },
      ]"
      tabindex="0"
      role="combobox"
      :aria-labelledby="labelledBy"
      :aria-expanded="isOpen"
      @click="openPanel"
      @keydown="onKeydown"
    >
      <span v-if="isSelect && values.length" class="mar-dropdown-chips">
        <span
          v-for="chip in selectedLabels"
          :key="chip"
          class="mar-dropdown-chip"
        >
          {{ chip }}
        </span>
      </span>
      <span v-else-if="selected" class="mar-dropdown-value">{{ selected.label }}</span>
      <span v-else class="mar-dropdown-placeholder">{{ placeholder }}</span>
      <span class="mar-dropdown-actions">
        <MarIcon
          icon="chevron-down"
          class="mar-dropdown-chevron"
          :data-open="isOpen ? '1' : '0'"
        />
      </span>
    </div>
    <label v-if="decorated && label" :id="labelId" class="mar-ifta-label-text">
      {{ label }}
      <span v-if="required" class="mar-ifta-label-required">*</span>
    </label>
    <small v-if="decorated && error" class="mar-ifta-label-error-text">{{ error }}</small>
  </div>
</template>

<style scoped>
.mar-dropdown {
  position: relative;
  display: inline-flex;
}

.mar-dropdown-fluid {
  display: flex;
  width: 100%;
}

.mar-dropdown.mar-ifta-label {
  display: flex;
  flex-direction: column;
  width: 100%;
}

.mar-dropdown-trigger {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5333em;
  width: 100%;
  padding: var(--mar-field-pad-y) 0.8em var(--mar-field-pad-y) var(--mar-field-pad-x);
  border: 1px solid var(--glass-border-strong);
  border-radius: var(--mar-field-radius);
  background: color-mix(in oklab, var(--mar-surface-0), transparent 30%);
  box-shadow: inset 0 1px 1px color-mix(in oklab, var(--mar-surface-950), transparent 94%);
  color: var(--mar-text-color);
  font-family: inherit;
  font-size: var(--mar-field-font-size);
  line-height: 1.4;
  font-weight: 500;
  cursor: pointer;
  outline: none;
  min-height: var(--mar-field-min-height);
  box-sizing: border-box;
  transition:
    border-color 0.2s cubic-bezier(0.32, 0.72, 0, 1),
    box-shadow 0.2s cubic-bezier(0.32, 0.72, 0, 1),
    background-color 0.2s cubic-bezier(0.32, 0.72, 0, 1);
  user-select: none;
}

.mar-dropdown-trigger:hover:not(:focus) {
  background: color-mix(in oklab, var(--mar-surface-0), transparent 15%);
  border-color: color-mix(in oklab, var(--mar-surface-900), transparent 72%);
}

.mar-dropdown-trigger:focus {
  background: color-mix(in oklab, var(--mar-surface-0), transparent 5%);
  border-color: color-mix(in oklab, var(--mar-primary-color), transparent 30%);
  box-shadow:
    0 0 0 0.2667em color-mix(in oklab, var(--mar-primary-color), transparent 82%),
    0 0.4em 1.3333em -0.8em color-mix(in oklab, var(--mar-primary-color), transparent 50%);
}

.mar-dropdown-trigger-invalid,
.mar-dropdown-trigger-invalid:hover:not(:focus) {
  border-color: color-mix(in oklab, var(--mar-danger-color), transparent 25%);
}

.mar-dropdown-trigger-invalid:focus {
  border-color: var(--mar-danger-color);
  box-shadow: 0 0 0 0.2667em color-mix(in oklab, var(--mar-danger-color), transparent 82%);
}

.mar-dropdown-inline {
  display: inline-flex;
  width: auto;
}

.mar-dropdown-inline .mar-dropdown-trigger {
  width: auto;
  padding: 0;
  border: none;
  background: transparent;
  box-shadow: none;
  font-size: var(--mar-field-font-size);
  font-weight: 400;
  line-height: 1.4;
  min-height: 0;
  gap: 0.3em;
  justify-content: flex-start;
}

.mar-dropdown-inline .mar-dropdown-value,
.mar-dropdown-inline .mar-dropdown-placeholder {
  flex: 0 0 auto;
}

.mar-dropdown-inline .mar-dropdown-chips {
  gap: 0.2308em;
}

.mar-dropdown-inline .mar-dropdown-chip {
  font-size: var(--mar-text-2xs);
}

.mar-dropdown-inline .mar-dropdown-actions {
  gap: 0.3077em;
}

.mar-dropdown-inline .mar-dropdown-chevron {
  width: 0.8462em;
  height: 0.8462em;
}

.mar-dropdown-inline .mar-dropdown-trigger:hover,
.mar-dropdown-inline .mar-dropdown-trigger:hover:not(:focus),
.mar-dropdown-inline .mar-dropdown-trigger:focus {
  border: none;
  background: transparent;
  box-shadow: none;
}

.mar-dropdown[data-disabled="1"] .mar-dropdown-trigger {
  opacity: 0.55;
  box-shadow: none;
  cursor: not-allowed;
}

.mar-dropdown-value {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex: 1;
}

.mar-dropdown-placeholder {
  color: var(--mar-surface-400);
  flex: 1;
}

.mar-dropdown-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.2em;
  flex: 1;
  min-width: 0;
}

.mar-dropdown-chip {
  display: inline-flex;
  align-items: center;
  padding: 0 0.5455em;
  background: var(--mar-highlight-background);
  color: var(--mar-highlight-color);
  border-radius: 9999px;
  font-size: var(--mar-text-2xs);
  font-weight: 500;
}

.mar-dropdown-actions {
  display: flex;
  align-items: center;
  gap: 0.2667em;
  flex-shrink: 0;
}

.mar-dropdown-filter-trigger {
  display: inline-flex;
  align-items: center;
  flex: 1 1 auto;
  gap: 0.375em;
  min-width: 0;
  max-width: 100%;
  height: 1.75em;
  padding: 0 0.625em;
  border: none;
  border-radius: 9999px;
  background: transparent;
  color: var(--mar-text-muted-color);
  font-family: inherit;
  font-size: var(--mar-text-sm);
  font-weight: 500;
  line-height: 1;
  white-space: nowrap;
  cursor: pointer;
  outline: none;
  user-select: none;
  transition:
    background 0.15s cubic-bezier(0.4, 0, 0.2, 1),
    color 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-dropdown-filter-trigger:hover:not(:disabled) {
  background: var(--mar-surface-100);
  color: var(--mar-text-color);
}

.mar-dropdown-filter-trigger:focus-visible {
  box-shadow: inset 0 0 0 2px var(--mar-primary-color);
}

.mar-dropdown-filter-trigger[data-active="1"] {
  color: var(--mar-text-color);
}

.mar-dropdown-filter-trigger:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.mar-dropdown-filter-label {
  flex: 0 0 auto;
}

.mar-dropdown-filter-value {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  font-weight: 600;
}

.mar-dropdown-filter-trigger .mar-dropdown-chevron {
  flex-shrink: 0;
  margin-inline-start: auto;
}

.mar-dropdown-button-chevron {
  font-size: var(--mar-text-base);
}

.mar-dropdown-chevron {
  width: 0.7333em;
  height: 0.7333em;
  color: var(--mar-surface-500);
  transition: transform 0.2s cubic-bezier(0.32, 0.72, 0, 1);
}

.mar-dropdown-chevron[data-open="1"] {
  transform: rotate(180deg);
}

@media (prefers-reduced-motion: reduce) {
  .mar-dropdown-trigger,
  .mar-dropdown-filter-trigger,
  .mar-dropdown-chevron {
    transition: none;
  }
}
</style>
