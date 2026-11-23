<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, useId, watch } from "vue";
import MarIcon from "../MarIcon";
import MarCheckboxInput from "../MarCheckboxInput";
import MarInputNumber from "../MarInputNumber";
import MarLoadingSpinner from "../MarLoadingSpinner";
import { openModal, type ModalHandle } from "@/composables/useModals.ts";
import type { MarDropdownOption } from "@/types/dropdown.types";
import { resolveDropdownOptions } from "@/utils/dropdown";

const {
  options,
  modelValue = null,
  searchable = true,
  searchPlaceholder = "Search…",
  showClear = false,
  selectMin,
  selectMax,
  emptyAction,
  emptyActionLabel = "Add new",
  search = undefined,
  manualFilter = false,
  hasMore = false,
} = defineProps<{
  /** Options to list, either bare strings used as both label and value or full option objects. */
  options: Array<string | MarDropdownOption>;
  /** Current selection, a string marking the selected option in single mode or an array holding the checked set in select mode. */
  modelValue?: string | string[] | null;
  /** Shows the autofocused search input that filters options by label or description substring. */
  searchable?: boolean;
  /** Placeholder text for the search input. */
  searchPlaceholder?: string;
  /** Offers the head band clear that empties a single mode selection; ignored in select mode, where the head already carries clear all. */
  showClear?: boolean;
  /** Minimum number of checked values; its presence switches to checkbox rows that toggle membership instead of closing on selection. */
  selectMin?: number;
  /** Maximum number of checked values; its presence switches to checkbox rows that toggle membership instead of closing on selection. */
  selectMax?: number;
  /** Called with the trimmed search text when the search returns no matches, such as to create a missing tag; its presence adds a clickable action row below the empty state text naming that text. */
  emptyAction?: (query: string) => void;
  /** Label for the action row shown when emptyAction is set and the search returns no matches. */
  emptyActionLabel?: string;
  /** Search text, seeding the search input and following later changes; every keystroke emits update:search. */
  search?: string;
  /** Turns off the local label filter, so the host filters on its server from update:search and passes the matching options. */
  manualFilter?: boolean;
  /** Trails the list with a loading row that emits more once it scrolls into view, for the next page of options. */
  hasMore?: boolean;
}>();

const emit = defineEmits<{
  close: [value?: string | null];
  change: [value: string[]];
  count: [value: string, count: number];
  "update:search": [value: string];
  more: [];
}>();

const slots = defineSlots<{
  /** Controls drawn in the actions row under the list, such as a switch that narrows what the options pick. */
  footer?: () => unknown;
}>();

const resolved = computed<MarDropdownOption[]>(() => {
  const list = resolveDropdownOptions(options);
  if (!list.some((o) => o.group)) return list;
  const groups = [...new Set(list.map((o) => o.group ?? ""))];
  return groups.flatMap((group) => list.filter((o) => (o.group ?? "") === group));
});

const groupHeader = (i: number): string | null => {
  const group = filtered.value[i]?.group;
  return group && group !== filtered.value[i - 1]?.group ? group : null;
};

const singleValue = computed<string | null>(() =>
  typeof modelValue === "string" &&
  (modelValue !== "" || resolved.value.some((o) => o.value === ""))
    ? modelValue
    : null,
);

const isSelect = computed(
  () => selectMin !== undefined || selectMax !== undefined,
);

const values = computed<string[]>(() =>
  Array.isArray(modelValue) ? modelValue : [],
);

const selectedSet = computed(() => new Set(values.value));

const atFloor = computed(
  () =>
    selectMin !== undefined && selectMin > 0 && values.value.length <= selectMin,
);

const atCap = computed(
  () => selectMax !== undefined && values.value.length >= selectMax,
);

const rowDisabled = (opt: MarDropdownOption) =>
  Boolean(opt.disabled) ||
  (selectedSet.value.has(opt.value) ? atFloor.value : atCap.value);

const query = ref(search ?? "");

watch(
  () => search,
  (value) => {
    if (value !== undefined && value !== query.value) query.value = value;
  },
);
const panelEl = ref<HTMLElement | null>(null);
const searchEl = ref<HTMLInputElement | null>(null);
const listEl = ref<HTMLElement | null>(null);

const filtered = computed<MarDropdownOption[]>(() => {
  const q = query.value.trim().toLowerCase();
  if (!q || manualFilter) return resolved.value;
  return resolved.value.filter(
    (o) =>
      o.label.toLowerCase().includes(q) ||
      (o.description?.toLowerCase().includes(q) ?? false),
  );
});

const described = computed(() => resolved.value.some((o) => o.description));

const uid = useId();
const listId = `${uid}-list`;
const rowId = (index: number) => `${uid}-option-${index}`;

const enabledIdx = (start: number, dir: number): number => {
  for (let i = start; i >= 0 && i < filtered.value.length; i += dir) {
    if (!filtered.value[i].disabled) return i;
  }
  return -1;
};

const focusedIdx = ref(
  (() => {
    const at = filtered.value.findIndex((o) => o.value === singleValue.value);
    return at >= 0 ? at : enabledIdx(0, 1);
  })(),
);

const activeId = computed(() =>
  focusedIdx.value >= 0 && focusedIdx.value < filtered.value.length
    ? rowId(focusedIdx.value)
    : undefined,
);

const scrollFocusedIntoView = () => {
  nextTick(() => {
    const el = focusedIdx.value >= 0 ? document.getElementById(rowId(focusedIdx.value)) : null;
    el?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  });
};

const setFocused = (index: number) => {
  if (index < 0) return;
  focusedIdx.value = index;
  scrollFocusedIntoView();
};

const move = (dir: number) => {
  if (filtered.value.length === 0) return;
  const from = focusedIdx.value;
  const start =
    from < 0 ? (dir > 0 ? 0 : filtered.value.length - 1) : from + dir;
  setFocused(
    enabledIdx(Math.max(0, Math.min(filtered.value.length - 1, start)), dir),
  );
};

const jump = (target: number) => {
  if (filtered.value.length === 0) return;
  const clamped = Math.max(0, Math.min(filtered.value.length - 1, target));
  const forward = enabledIdx(clamped, 1);
  setFocused(forward >= 0 ? forward : enabledIdx(clamped, -1));
};

const pageStep = () => {
  const list = listEl.value;
  const row = list?.querySelector<HTMLElement>("[role=option]");
  if (!list || !row || row.offsetHeight === 0) return 1;
  return Math.max(1, Math.floor(list.clientHeight / row.offsetHeight));
};

const scope = computed<MarDropdownOption[]>(() =>
  filtered.value.filter((o) => !o.disabled),
);

const scopeValues = computed(() => scope.value.map((o) => o.value));

const selectedInScope = computed(() =>
  scopeValues.value.filter((v) => selectedSet.value.has(v)),
);

const allScopeSelected = computed(
  () =>
    scope.value.length > 0 &&
    selectedInScope.value.length === scope.value.length,
);

const someScopeSelected = computed(() => selectedInScope.value.length > 0);

const selectAllNext = computed(() =>
  Array.from(new Set([...values.value, ...scopeValues.value])),
);

const clearAllNext = computed(() =>
  values.value.filter((v) => !scopeValues.value.includes(v)),
);

const canSelectAll = computed(
  () =>
    scope.value.length > 0 &&
    !allScopeSelected.value &&
    (selectMax === undefined || selectAllNext.value.length <= selectMax),
);

const canClearAll = computed(
  () =>
    someScopeSelected.value &&
    (selectMin === undefined || clearAllNext.value.length >= selectMin),
);

const canToggleAll = computed(() =>
  allScopeSelected.value ? canClearAll.value : canSelectAll.value,
);

const searching = computed(() => query.value.trim() !== "");

const quickPicks = computed(() => resolved.value.filter((o) => o.quick));

const selectedLabel = computed(
  () => resolved.value.find((o) => o.value === singleValue.value)?.label ?? "",
);

const canClearSingle = computed(
  () => showClear && !isSelect.value && singleValue.value !== null,
);

const hasHeadRow = computed(() => isSelect.value || canClearSingle.value);

const hasHead = computed(() => hasHeadRow.value || quickPicks.value.length > 0);

const select = (opt: MarDropdownOption) => {
  if (opt.disabled) return;
  emit("close", opt.value);
};

const clearSingle = () => {
  emit("close", null);
};

const counts = ref<Record<string, number>>(
  Object.fromEntries(
    resolved.value
      .filter((o) => o.count !== undefined)
      .map((o) => [o.value, o.count as number]),
  ),
);

const countValue = (opt: MarDropdownOption): number =>
  counts.value[opt.value] ?? (opt.count as number);

const onCount = (opt: MarDropdownOption, next: number | null) => {
  if (next == null) return;
  counts.value = { ...counts.value, [opt.value]: next };
  emit("count", opt.value, next);
};

const toggle = (opt: MarDropdownOption) => {
  if (rowDisabled(opt)) return;
  const next = new Set(values.value);
  if (next.has(opt.value)) next.delete(opt.value);
  else next.add(opt.value);
  emit("change", Array.from(next));
};

const toggleAll = () => {
  if (!canToggleAll.value) return;
  emit("change", allScopeSelected.value ? clearAllNext.value : selectAllNext.value);
};

const onQuick = (opt: MarDropdownOption) => {
  if (isSelect.value) toggle(opt);
  else select(opt);
};

const quickActive = (opt: MarDropdownOption) =>
  isSelect.value
    ? selectedSet.value.has(opt.value)
    : opt.value === singleValue.value;

const onSearchInput = (e: Event) => {
  query.value = (e.target as HTMLInputElement).value;
  emit("update:search", query.value);
  focusedIdx.value = enabledIdx(0, 1);
  scrollFocusedIntoView();
};

const activate = () => {
  const opt = filtered.value[focusedIdx.value];
  if (!opt) return;
  if (isSelect.value) toggle(opt);
  else select(opt);
};

const tabStops = (): HTMLElement[] => {
  const root = panelEl.value;
  if (!root) return [];
  const stops = [
    ...root.querySelectorAll<HTMLElement>(
      ".mar-dropdown-panel-all input:not(:disabled), .mar-dropdown-panel-clear, .mar-dropdown-panel-quick-btn:not(:disabled)",
    ),
  ];
  if (searchEl.value) stops.push(searchEl.value);
  stops.push(
    ...root.querySelectorAll<HTMLElement>(
      ".mar-dropdown-panel-footer :is(input, button, [tabindex]):not(:disabled, [tabindex=\"-1\"])",
    ),
  );
  return stops;
};

const cycleTab = (back: boolean) => {
  const stops = tabStops();
  if (stops.length < 2) {
    emit("close");
    return;
  }
  const at = stops.indexOf(document.activeElement as HTMLElement);
  const next =
    at < 0
      ? back
        ? stops.length - 1
        : 0
      : (at + (back ? -1 : 1) + stops.length) % stops.length;
  stops[next].focus();
};

const inBand = (e: KeyboardEvent) =>
  (e.target as HTMLElement | null)?.closest(".mar-dropdown-panel-head, .mar-dropdown-panel-footer") != null;

const onKeydown = (e: KeyboardEvent) => {
  if (e.key === "Tab") {
    e.preventDefault();
    cycleTab(e.shiftKey);
  } else if (e.key === "ArrowDown") {
    e.preventDefault();
    move(1);
  } else if (e.key === "ArrowUp") {
    e.preventDefault();
    move(-1);
  } else if (e.key === "Home" && !searchable) {
    e.preventDefault();
    jump(0);
  } else if (e.key === "End" && !searchable) {
    e.preventDefault();
    jump(filtered.value.length - 1);
  } else if (e.key === "PageDown") {
    e.preventDefault();
    jump(Math.max(focusedIdx.value, 0) + pageStep());
  } else if (e.key === "PageUp") {
    e.preventDefault();
    jump(Math.max(focusedIdx.value, 0) - pageStep());
  } else if (e.key === "Enter" && !inBand(e)) {
    e.preventDefault();
    activate();
  } else if (e.key === " " && !searchable && !inBand(e)) {
    e.preventDefault();
    activate();
  }
};

const onEmptyClick = () => {
  emptyAction?.(query.value.trim());
  emit("close");
};

let tip: ModalHandle | null = null;

const closeTip = (): void => {
  tip?.close();
  tip = null;
};

const openTip = (opt: MarDropdownOption, e: MouseEvent | FocusEvent): void => {
  closeTip();
  if (!opt.tooltip) return;
  tip = openModal({
    kind: "tooltip",
    text: opt.tooltip,
    anchor: e.currentTarget as HTMLElement,
    placement: { side: "right" },
  });
};

const onOptionEnter = (
  opt: MarDropdownOption,
  index: number,
  e: MouseEvent,
): void => {
  focusedIdx.value = index;
  openTip(opt, e);
};

onUnmounted(closeTip);

const moreEl = ref<HTMLElement | null>(null);
let moreObserver: IntersectionObserver | null = null;
let moreAsked = false;

const watchMore = (el: HTMLElement | null) => {
  moreObserver?.disconnect();
  moreObserver = null;
  if (!el) return;
  moreObserver = new IntersectionObserver(
    (entries) => {
      if (!entries.some((entry) => entry.isIntersecting) || moreAsked) return;
      moreAsked = true;
      emit("more");
    },
    { root: listEl.value },
  );
  moreObserver.observe(el);
};

watch(moreEl, watchMore);

watch(
  () => [resolved.value.length, hasMore],
  () => {
    moreAsked = false;
    if (moreEl.value) watchMore(moreEl.value);
  },
);

onUnmounted(() => moreObserver?.disconnect());

onMounted(() => {
  nextTick(() => {
    if (searchable) searchEl.value?.focus();
    else panelEl.value?.focus();
    const el = focusedIdx.value >= 0 ? document.getElementById(rowId(focusedIdx.value)) : null;
    el?.scrollIntoView({ block: "nearest" });
  });
});
</script>

<template>
  <div
    ref="panelEl"
    :class="['mar-dropdown-panel', { 'mar-dropdown-panel-described': described }]"
    tabindex="-1"
    @keydown="onKeydown"
  >
    <div v-if="hasHead" class="mar-dropdown-panel-head">
      <div v-if="hasHeadRow" class="mar-dropdown-panel-head-row">
        <span class="mar-dropdown-panel-head-label">
          <span class="mar-dropdown-panel-head-mode">
            {{ isSelect && searching ? "In results" : "Selected" }}
          </span>
          <span class="mar-dropdown-panel-head-value">
            <template v-if="isSelect">
              {{ selectedInScope.length }} / {{ scope.length }}
            </template>
            <template v-else>{{ selectedLabel }}</template>
          </span>
        </span>
        <MarCheckboxInput
          v-if="isSelect"
          class="mar-dropdown-panel-all"
          :model-value="allScopeSelected"
          :indeterminate="someScopeSelected && !allScopeSelected"
          :disabled="!canToggleAll"
          :label="allScopeSelected ? 'Clear all' : 'Select all'"
          @update:model-value="toggleAll"
        />
        <button
          v-else
          type="button"
          class="mar-panel-text-btn mar-dropdown-panel-clear"
          @click="clearSingle"
        >
          Clear
        </button>
      </div>
      <div v-if="quickPicks.length" class="mar-dropdown-panel-quick">
        <button
          v-for="opt in quickPicks"
          :key="opt.value"
          type="button"
          class="mar-dropdown-panel-quick-btn"
          :class="{ 'is-active': quickActive(opt) }"
          :disabled="rowDisabled(opt)"
          @click="onQuick(opt)"
        >
          {{ opt.quickLabel ?? opt.label }}
        </button>
      </div>
    </div>
    <div v-if="searchable" class="mar-dropdown-panel-search">
      <input
        ref="searchEl"
        type="text"
        size="1"
        class="mar-dropdown-panel-search-input"
        role="combobox"
        aria-expanded="true"
        :aria-controls="listId"
        :aria-activedescendant="activeId"
        :value="query"
        :placeholder="searchPlaceholder"
        autocomplete="off"
        spellcheck="false"
        @input="onSearchInput"
      />
    </div>
    <div
      :id="listId"
      ref="listEl"
      class="mar-dropdown-panel-list"
      role="listbox"
      :aria-multiselectable="isSelect"
    >
      <template v-if="isSelect">
        <template v-for="(opt, i) in filtered" :key="opt.value">
        <div v-if="groupHeader(i)" class="mar-dropdown-panel-group" role="presentation"><span class="mar-dropdown-panel-group-label">{{ groupHeader(i) }}</span></div>
        <div
          :id="rowId(i)"
          :class="[
            'mar-dropdown-panel-check',
            { 'mar-dropdown-panel-option-focused': i === focusedIdx },
            { 'mar-dropdown-panel-row-described': opt.description },
          ]"
          role="option"
          :aria-selected="selectedSet.has(opt.value)"
          :aria-disabled="rowDisabled(opt)"
          @mouseenter="onOptionEnter(opt, i, $event)"
          @mouseleave="closeTip"
        >
          <MarCheckboxInput
            :model-value="selectedSet.has(opt.value)"
            :label="opt.label"
            :disabled="rowDisabled(opt)"
            @update:model-value="toggle(opt)"
          />
          <MarIcon v-if="opt.disabled" icon="lock" class="mar-dropdown-panel-lock" />
          <span v-if="opt.description" class="mar-dropdown-panel-check-detail">
            <span class="mar-dropdown-panel-description">{{ opt.description }}</span>
          </span>
        </div>
        </template>
      </template>
      <template v-else>
        <template v-for="(opt, i) in filtered" :key="opt.value">
        <div v-if="groupHeader(i)" class="mar-dropdown-panel-group" role="presentation"><span class="mar-dropdown-panel-group-label">{{ groupHeader(i) }}</span></div>
        <div
          :id="rowId(i)"
          :class="[
            'mar-dropdown-panel-option',
            { 'mar-dropdown-panel-option-selected': opt.value === singleValue },
            { 'mar-dropdown-panel-option-focused': i === focusedIdx },
            { 'mar-dropdown-panel-option-disabled': opt.disabled },
            { 'mar-dropdown-panel-row-described': opt.description },
          ]"
          role="option"
          tabindex="-1"
          :aria-selected="opt.value === singleValue"
          :aria-disabled="opt.disabled"
          @click="select(opt)"
          @mouseenter="onOptionEnter(opt, i, $event)"
          @mouseleave="closeTip"
        >
          <MarInputNumber
            v-if="opt.count !== undefined"
            class="mar-dropdown-panel-count"
            inline
            :model-value="countValue(opt)"
            :min="opt.countMin ?? 1"
            :max="opt.countMax"
            :disabled="opt.disabled"
            @click.stop
            @keydown.stop
            @update:model-value="onCount(opt, $event)"
          />
          <span v-if="opt.description" class="mar-dropdown-panel-option-text">
            <span>{{ opt.label }}</span>
            <span class="mar-dropdown-panel-description">{{ opt.description }}</span>
          </span>
          <span v-else>{{ opt.label }}</span>
        </div>
        </template>
      </template>
      <div v-if="hasMore" ref="moreEl" class="mar-dropdown-panel-more" aria-hidden="true">
        <MarLoadingSpinner mode="inline" label="" />
      </div>
      <div v-if="filtered.length === 0 && !hasMore" class="mar-dropdown-panel-empty">
        {{ query ? "No matches" : "No options" }}
      </div>
      <div
        v-if="filtered.length === 0 && query && emptyAction"
        class="mar-dropdown-panel-option mar-dropdown-panel-empty-action"
        @click="onEmptyClick"
      >
        <MarIcon icon="plus" />
        <span>{{ emptyActionLabel }}</span>
        <span class="mar-dropdown-panel-empty-query">{{ query.trim() }}</span>
      </div>
    </div>
    <div v-if="slots.footer" class="mar-dropdown-panel-actions mar-dropdown-panel-footer">
      <slot name="footer" />
    </div>
  </div>
</template>

<style scoped>
.mar-dropdown-panel {
  width: max-content;
  min-width: 100%;
  max-width: min(27.0769em, 90vw);
  outline: none;
}

.mar-dropdown-panel-described {
  min-inline-size: clamp(16em, 28em, 90vw);
  max-width: min(36em, 90vw);
}

.mar-dropdown-panel-option.mar-dropdown-panel-row-described,
.mar-dropdown-panel-check.mar-dropdown-panel-row-described {
  height: auto;
  min-height: var(--mar-panel-row);
  padding-block: 0.4615em;
  white-space: normal;
}

.mar-dropdown-panel-check.mar-dropdown-panel-row-described {
  flex-wrap: wrap;
  row-gap: 0.1538em;
}

.mar-dropdown-panel-option-text {
  display: flex;
  flex-direction: column;
  gap: 0.1538em;
  min-width: 0;
}

.mar-dropdown-panel-check-detail {
  flex: 1 0 100%;
  padding-inline-start: 1.5385em;
  min-width: 0;
}

.mar-dropdown-panel-description {
  font-size: var(--mar-text-xs);
  font-weight: 400;
  line-height: 1.35;
  color: var(--mar-panel-text-muted);
  overflow-wrap: anywhere;
}

.mar-dropdown-panel-option-selected .mar-dropdown-panel-description {
  color: inherit;
  opacity: 0.8;
}

.mar-dropdown-panel-head-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.9231em;
}

.mar-dropdown-panel-head-label {
  display: flex;
  align-items: baseline;
  gap: 0.4615em;
  min-width: 0;
  white-space: nowrap;
}

.mar-dropdown-panel-head-value {
  font-size: 0.8462em;
  font-variant-numeric: tabular-nums;
  text-transform: none;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mar-dropdown-panel-clear {
  flex: none;
  font-size: 0.8462em;
  color: inherit;
}

.mar-dropdown-panel-clear:hover:not(:disabled) {
  background: var(--mar-panel-primary-soft);
  color: inherit;
}

.mar-dropdown-panel-all {
  flex: none;
  font-size: 0.8462em;
  font-weight: 600;
  color: inherit;
}

.mar-dropdown-panel-all.mar-checkbox-disabled {
  opacity: 0.45;
}

.mar-dropdown-panel-quick {
  display: flex;
  flex-wrap: wrap;
  gap: 0.3077em;
}

.mar-dropdown-panel-search {
  padding: 0.4308em 0.4923em;
  border-bottom: 1px solid var(--mar-panel-line);
  background: var(--mar-panel-surface-subtle);
  flex-shrink: 0;
}

.mar-dropdown-panel-search-input {
  width: 100%;
  border: 1px solid var(--mar-panel-line-strong);
  border-radius: 6px;
  background: var(--mar-panel-surface);
  color: var(--mar-panel-text);
  font: inherit;
  font-size: 0.9231em;
  padding: 0.3333em 0.6em;
  outline: none;
  transition: border-color 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-dropdown-panel-search-input::placeholder {
  color: var(--mar-panel-text-faint);
}

.mar-dropdown-panel-search-input:focus {
  border-color: var(--mar-panel-primary);
}

.mar-dropdown-panel-list {
  overflow-x: hidden;
  max-height: calc(var(--mar-panel-row) * 0.9231 * var(--mar-panel-rows) + 0.6154em);
  padding: 0.3077em 0;
  scroll-snap-type: y mandatory;
  overscroll-behavior: contain;
}

.mar-dropdown-panel-option,
.mar-dropdown-panel-check {
  display: flex;
  align-items: center;
  gap: 0.5em;
  height: var(--mar-panel-row);
  padding: 0 1em;
  scroll-snap-align: start;
  scroll-snap-stop: normal;
  font-size: 0.9231em;
  font-weight: 500;
  color: var(--mar-panel-text);
  line-height: 1.2;
  white-space: nowrap;
  transition: background 0.1s ease;
}

.mar-dropdown-panel-check :deep(.mar-checkbox) {
  flex: 1 1 auto;
  min-width: 0;
}

.mar-dropdown-panel-check:not(.mar-dropdown-panel-row-described) :deep(.mar-checkbox-label) {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mar-dropdown-panel-option {
  cursor: pointer;
}

.mar-dropdown-panel-more {
  display: flex;
  align-items: center;
  justify-content: center;
  height: var(--mar-panel-row);
  font-size: 0.9231em;
  scroll-snap-align: start;
}

.mar-dropdown-panel-group {
  display: flex;
  align-items: flex-end;
  height: var(--mar-panel-row);
  padding: 0 1em 0.35em;
  scroll-snap-align: start;
  font-size: 0.9231em;
  user-select: none;
}

.mar-dropdown-panel-group-label {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.75em;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--mar-panel-text-muted);
}

.mar-dropdown-panel-option:hover,
.mar-dropdown-panel-check:hover {
  background: var(--mar-panel-surface-hover);
}

.mar-dropdown-panel-option-focused {
  background: var(--mar-panel-primary-softer);
}

.mar-dropdown-panel-option-selected {
  background: var(--mar-panel-primary-soft);
  color: var(--mar-panel-primary-on-soft);
  font-weight: 600;
}

.mar-dropdown-panel-option-selected.mar-dropdown-panel-option-focused {
  background: var(--mar-panel-primary-band);
}

.mar-dropdown-panel-option-disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.mar-dropdown-panel-option-disabled:hover {
  background: transparent;
}

.mar-dropdown-panel-count {
  flex: none;
  font-size: inherit;
}

.mar-dropdown-panel-check :deep(.mar-checkbox) {
  flex: 1;
  min-width: 0;
  font-size: 1em;
}

.mar-dropdown-panel-lock {
  color: var(--mar-panel-text-muted);
  font-size: 1.3333em;
}

.mar-dropdown-panel-empty {
  padding: 0.6667em;
  text-align: center;
  font-size: 0.9231em;
  color: var(--mar-panel-text-muted);
  scroll-snap-align: start;
}

.mar-dropdown-panel-empty-action {
  border-top: 1px solid var(--mar-panel-line);
  color: var(--mar-panel-primary);
  justify-content: center;
}

.mar-dropdown-panel-empty-action .mar-icon {
  font-size: 1.3333em;
}

.mar-dropdown-panel-empty-query {
  min-width: 0;
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
