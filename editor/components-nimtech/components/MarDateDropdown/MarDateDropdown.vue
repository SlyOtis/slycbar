<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, ref, watch } from "vue";
import MarIcon from "@/components/MarIcon";
import { openModal, type ModalHandle } from "@/composables/useModals.ts";
import { formatDate, useDateFormat } from "@/composables/useDateFormat";
import { getDateWeek } from "@/utils/dateFormat";
import {
  MAR_DATE_LABELS,
  type MarDateLabels,
  type MarDateMode,
  type MarDatePreset,
  type MarDateRange,
} from "../MarDateInput/marDate.types";

const props = withDefaults(
  defineProps<{
    /** Single date or range selection, or week, where any day picked selects the whole week it falls in. */
    mode?: MarDateMode;
    /**
     * Initial draft selection whose time parts seed the time inputs.
     * @mock mockDate
     */
    selected?: Date | MarDateRange | null;
    /**
     * Month the calendar opens on when it differs from the selection.
     * @mock mockDate
     */
    startDate?: Date | null;
    /**
     * Days before this date are disabled.
     * @mock mockDate
     */
    minDate?: Date | null;
    /**
     * Days after this date are disabled.
     * @mock mockDate
     */
    maxDate?: Date | null;
    /**
     * First day of the week, 0 for Sunday and 1 for Monday.
     * @minimum 0
     * @maximum 6
     */
    firstDayOfWeek?: number;
    /** Texts of the panel, each key falling back to its English default. */
    labels?: Partial<MarDateLabels>;
    /** Shows hour and minute inputs and stamps times onto the confirmed dates. */
    withTime?: boolean;
    /** Hides the clear action so the draft cannot be emptied. */
    required?: boolean;
    /** Suggestions above the action row, each a label and a date or range, or a function of today returning one; picking one applies it as confirm does. */
    presets?: MarDatePreset[];
  }>(),
  {
    mode: "single",
    selected: null,
    startDate: null,
    minDate: null,
    maxDate: null,
    firstDayOfWeek: 1,
    labels: () => ({}),
    withTime: false,
    required: false,
    presets: () => [],
  }
);

const emit = defineEmits<{
  (e: "close", payload?: Date | MarDateRange | null): void;
  (e: "pick", payload: Date | MarDateRange | null): void;
}>();

const text = computed<Required<MarDateLabels>>(() => ({ ...MAR_DATE_LABELS, ...props.labels }));

const startOfDay = (d: Date): Date => {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
};

const sameDay = (a: Date | null, b: Date | null): boolean => {
  if (!a || !b) return false;
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
};

const isBetween = (d: Date, a: Date, b: Date): boolean => {
  const t = d.getTime();
  return t > a.getTime() && t < b.getTime();
};

const today = startOfDay(new Date());

const clampMonth = (d: Date): Date => {
  const month = new Date(d.getFullYear(), d.getMonth(), 1);
  if (props.minDate && month < new Date(props.minDate.getFullYear(), props.minDate.getMonth(), 1)) {
    return new Date(props.minDate.getFullYear(), props.minDate.getMonth(), 1);
  }
  if (props.maxDate && month > new Date(props.maxDate.getFullYear(), props.maxDate.getMonth(), 1)) {
    return new Date(props.maxDate.getFullYear(), props.maxDate.getMonth(), 1);
  }
  return month;
};

const initialAnchor = (): Date => {
  if (props.startDate) return startOfDay(props.startDate);
  if (props.mode === "single" && props.selected instanceof Date) {
    return startOfDay(props.selected);
  }
  if (props.mode !== "single" && props.selected && !(props.selected instanceof Date)) {
    if (props.selected.start) return startOfDay(props.selected.start);
    if (props.selected.end) return startOfDay(props.selected.end);
  }
  return today;
};

const anchor = ref(clampMonth(initialAnchor()));
const cursorYear = computed(() => anchor.value.getFullYear());
const cursorMonth = computed(() => anchor.value.getMonth());

const draftSingle = ref<Date | null>(
  props.mode === "single" && props.selected instanceof Date
    ? startOfDay(props.selected)
    : null
);
const draftRange = ref<MarDateRange>(
  props.mode !== "single" && props.selected && !(props.selected instanceof Date)
    ? {
        start: props.selected.start ? startOfDay(props.selected.start) : null,
        end: props.selected.end ? startOfDay(props.selected.end) : null,
      }
    : { start: null, end: null }
);

const pad2 = (n: number): string => String(n).padStart(2, "0");

const initialStartTime = (): { h: number; m: number } => {
  if (props.mode === "single" && props.selected instanceof Date) {
    return { h: props.selected.getHours(), m: props.selected.getMinutes() };
  }
  if (props.mode !== "single" && props.selected && !(props.selected instanceof Date) && props.selected.start) {
    return { h: props.selected.start.getHours(), m: props.selected.start.getMinutes() };
  }
  return { h: 0, m: 0 };
};

const initialEndTime = (): { h: number; m: number } => {
  if (props.mode !== "single" && props.selected && !(props.selected instanceof Date) && props.selected.end) {
    return { h: props.selected.end.getHours(), m: props.selected.end.getMinutes() };
  }
  return { h: 0, m: 0 };
};

const startTime = ref(initialStartTime());
const endTime = ref(initialEndTime());

const startHourText = ref(pad2(startTime.value.h));
const startMinuteText = ref(pad2(startTime.value.m));
const endHourText = ref(pad2(endTime.value.h));
const endMinuteText = ref(pad2(endTime.value.m));

const startHourEl = ref<HTMLInputElement | null>(null);
const startMinuteEl = ref<HTMLInputElement | null>(null);
const endHourEl = ref<HTMLInputElement | null>(null);
const endMinuteEl = ref<HTMLInputElement | null>(null);

const clampHour = (n: number): number => Math.max(0, Math.min(23, n));
const clampMinute = (n: number): number => Math.max(0, Math.min(59, n));

const selectAll = (el: HTMLInputElement | null) => {
  if (!el) return;
  nextTick(() => el.select());
};

type Side = "start" | "end";
type Field = "h" | "m";

const getTimeRef = (side: Side) => (side === "start" ? startTime : endTime);
const getTextRef = (side: Side, field: Field) => {
  if (side === "start") return field === "h" ? startHourText : startMinuteText;
  return field === "h" ? endHourText : endMinuteText;
};
const getEl = (side: Side, field: Field): HTMLInputElement | null => {
  if (side === "start") return field === "h" ? startHourEl.value : startMinuteEl.value;
  return field === "h" ? endHourEl.value : endMinuteEl.value;
};

const onTimeInput = (e: Event, side: Side, field: Field) => {
  const el = e.target as HTMLInputElement;
  const raw = el.value.replace(/[^0-9]/g, "").slice(0, 2);
  const textRef = getTextRef(side, field);
  textRef.value = raw;
  el.value = raw;
  if (raw === "") return;
  const n = field === "h" ? clampHour(Number(raw)) : clampMinute(Number(raw));
  const store = getTimeRef(side);
  store.value = { ...store.value, [field]: n };
  if (raw.length === 2 && field === "h") {
    const nextEl = getEl(side, "m");
    if (nextEl) {
      nextEl.focus();
      selectAll(nextEl);
    }
  }
};

const onTimeBlur = (side: Side, field: Field) => {
  const store = getTimeRef(side);
  const textRef = getTextRef(side, field);
  textRef.value = pad2(store.value[field]);
};

const stepTime = (side: Side, field: Field, delta: number) => {
  const store = getTimeRef(side);
  const textRef = getTextRef(side, field);
  if (field === "h") {
    const next = clampHour(store.value.h + delta);
    store.value = { ...store.value, h: next };
    textRef.value = pad2(next);
  } else {
    let next = store.value.m + delta;
    if (next < 0) next += 60;
    if (next > 59) next -= 60;
    store.value = { ...store.value, m: next };
    textRef.value = pad2(next);
  }
};

const bumpTime = (side: Side, field: Field, dir: 1 | -1) => {
  const store = getTimeRef(side);
  const hourText = getTextRef(side, "h");
  const minText = getTextRef(side, "m");
  const deltaMin = field === "h" ? dir * 60 : dir * 15;
  let total = store.value.h * 60 + store.value.m + deltaMin;
  const dayMin = 24 * 60;
  total = ((total % dayMin) + dayMin) % dayMin;
  const h = Math.floor(total / 60);
  const m = total % 60;
  store.value = { h, m };
  hourText.value = pad2(h);
  minText.value = pad2(m);
};

const onTimeKey = (e: KeyboardEvent, side: Side, field: Field) => {
  const el = getEl(side, field);
  const prevEl = field === "m" ? getEl(side, "h") : null;
  const nextEl = field === "h" ? getEl(side, "m") : null;
  if (e.key === "ArrowUp") {
    e.preventDefault();
    stepTime(side, field, 1);
    selectAll(el);
  } else if (e.key === "ArrowDown") {
    e.preventDefault();
    stepTime(side, field, -1);
    selectAll(el);
  } else if (e.key === "ArrowRight" || e.key === ":") {
    if (nextEl) {
      e.preventDefault();
      nextEl.focus();
      selectAll(nextEl);
    }
  } else if (e.key === "ArrowLeft" && (e.target as HTMLInputElement).selectionStart === 0) {
    if (prevEl) {
      e.preventDefault();
      prevEl.focus();
      selectAll(prevEl);
    }
  } else if (e.key === "Backspace" && getTextRef(side, field).value === "" && prevEl) {
    e.preventDefault();
    prevEl.focus();
    selectAll(prevEl);
  } else if (e.key === "Enter") {
    e.preventDefault();
    onConfirm();
  }
};

const hoverDate = ref<Date | null>(null);

const yearListOpen = ref(false);

const dateFormat = useDateFormat();

const monthLabel = computed(() => formatDate(anchor.value, dateFormat.value.month, dateFormat.value));

const weekdayLabels = computed<string[]>(() => {
  const labels: string[] = [];
  const base = new Date(2024, 0, 7);
  for (let i = 0; i < 7; i++) {
    const d = new Date(base);
    d.setDate(base.getDate() + ((props.firstDayOfWeek + i) % 7));
    labels.push(formatDate(d, "EEEEE", dateFormat.value));
  }
  return labels;
});

interface DayCell {
  date: Date;
  inMonth: boolean;
  disabled: boolean;
  isToday: boolean;
  isSelected: boolean;
  isRangeStart: boolean;
  isRangeEnd: boolean;
  isInRange: boolean;
}

const minMs = computed(() => (props.minDate ? startOfDay(props.minDate).getTime() : null));
const maxMs = computed(() => (props.maxDate ? startOfDay(props.maxDate).getTime() : null));

const isDisabled = (d: Date): boolean => {
  const t = d.getTime();
  if (minMs.value !== null && t < minMs.value) return true;
  if (maxMs.value !== null && t > maxMs.value) return true;
  return false;
};

const effectiveRange = computed<{ start: Date | null; end: Date | null }>(() => {
  if (props.mode === "single") return { start: null, end: null };
  const r = draftRange.value;
  if (props.mode === "week" && hoverDate.value) return getDateWeek(hoverDate.value, props.firstDayOfWeek);
  if (r.start && !r.end && hoverDate.value && hoverDate.value.getTime() >= r.start.getTime()) {
    return { start: r.start, end: hoverDate.value };
  }
  return r;
});

const grid = computed<DayCell[]>(() => {
  const year = cursorYear.value;
  const month = cursorMonth.value;
  const firstOfMonth = new Date(year, month, 1);
  const firstDow = firstOfMonth.getDay();
  const offset = (firstDow - props.firstDayOfWeek + 7) % 7;
  const gridStart = new Date(year, month, 1 - offset);
  const cells: DayCell[] = [];
  const rangeVal = effectiveRange.value;
  for (let i = 0; i < 42; i++) {
    const d = new Date(gridStart);
    d.setDate(gridStart.getDate() + i);
    d.setHours(0, 0, 0, 0);
    const inMonth = d.getMonth() === month;
    let isSelected = false;
    let isRangeStart = false;
    let isRangeEnd = false;
    let isInRange = false;
    if (props.mode === "single") {
      isSelected = sameDay(draftSingle.value, d);
    } else if (rangeVal.start || rangeVal.end) {
      isRangeStart = sameDay(rangeVal.start, d);
      isRangeEnd = sameDay(rangeVal.end, d);
      isSelected = isRangeStart || isRangeEnd;
      if (rangeVal.start && rangeVal.end && isBetween(d, rangeVal.start, rangeVal.end)) {
        isInRange = true;
      }
    }
    cells.push({
      date: d,
      inMonth,
      disabled: isDisabled(d),
      isToday: sameDay(today, d),
      isSelected,
      isRangeStart,
      isRangeEnd,
      isInRange,
    });
  }
  return cells;
});

const edgeText = (d: Date, time: { h: number; m: number }): string => {
  const day = formatDate(d, dateFormat.value.date, dateFormat.value);
  if (!props.withTime) return day;
  const at = new Date(d.getFullYear(), d.getMonth(), d.getDate(), time.h, time.m);
  return `${day} ${formatDate(at, dateFormat.value.time, dateFormat.value)}`;
};

const headerText = computed(() => {
  if (props.mode === "single") {
    const d = draftSingle.value;
    if (!d) return text.value.selectDate;
    return edgeText(d, startTime.value);
  }
  const r = draftRange.value;
  if (r.start && !r.end) return `${edgeText(r.start, startTime.value)} – …`;
  if (r.start && r.end) return `${edgeText(r.start, startTime.value)} – ${edgeText(r.end, endTime.value)}`;
  return text.value.selectRange;
});

const canPrevMonth = computed(
  () =>
    !props.minDate ||
    new Date(cursorYear.value, cursorMonth.value, 1) > new Date(props.minDate.getFullYear(), props.minDate.getMonth(), 1),
);

const canNextMonth = computed(
  () =>
    !props.maxDate ||
    new Date(cursorYear.value, cursorMonth.value, 1) < new Date(props.maxDate.getFullYear(), props.maxDate.getMonth(), 1),
);

const goPrevMonth = () => {
  if (!canPrevMonth.value) return;
  anchor.value = new Date(cursorYear.value, cursorMonth.value - 1, 1);
};

const goNextMonth = () => {
  if (!canNextMonth.value) return;
  anchor.value = new Date(cursorYear.value, cursorMonth.value + 1, 1);
};

const onDayClick = (cell: DayCell) => {
  if (cell.disabled) return;
  if (props.mode === "single") {
    draftSingle.value = cell.date;
    return;
  }
  if (props.mode === "week") {
    draftRange.value = getDateWeek(cell.date, props.firstDayOfWeek);
    return;
  }
  const r = draftRange.value;
  if (!r.start || (r.start && r.end)) {
    draftRange.value = { start: cell.date, end: null };
    return;
  }
  if (cell.date.getTime() < r.start.getTime()) {
    draftRange.value = { start: cell.date, end: null };
    return;
  }
  draftRange.value = { start: r.start, end: cell.date };
};

const onDayHover = (cell: DayCell) => {
  if (cell.disabled) return;
  hoverDate.value = cell.date;
};

const onGridLeave = () => {
  hoverDate.value = null;
};

const canConfirm = computed(() => {
  if (props.mode === "single") return draftSingle.value !== null;
  return draftRange.value.start !== null && draftRange.value.end !== null;
});

const onCancel = () => {
  emit("close");
};

const applyTime = (d: Date | null, t: { h: number; m: number }): Date | null => {
  if (!d) return null;
  const out = new Date(d);
  out.setHours(t.h, t.m, 0, 0);
  return out;
};

const drafted = computed<Date | MarDateRange | null>(() => {
  if (props.mode === "single") {
    const d = draftSingle.value;
    return props.withTime ? applyTime(d, startTime.value) : d;
  }
  const r = draftRange.value;
  return {
    start: props.withTime ? applyTime(r.start, startTime.value) : r.start,
    end: props.withTime ? applyTime(r.end, endTime.value) : r.end,
  };
});

const stamp = (value: Date | MarDateRange | null): string => {
  if (!value) return "";
  if (value instanceof Date) return String(value.getTime());
  return `${value.start?.getTime() ?? ""}:${value.end?.getTime() ?? ""}`;
};

let seenSelected = stamp(props.selected ?? null);

watch(drafted, (value, before) => {
  if (stamp(value) === stamp(before)) return;
  if (stamp(value) === stamp(props.selected ?? null)) return;
  emit("pick", value);
});

const seedDraft = (value: Date | MarDateRange | null) => {
  const start = value instanceof Date ? value : (value?.start ?? null);
  const end = value instanceof Date ? null : (value?.end ?? null);
  if (props.mode === "single") draftSingle.value = start ? startOfDay(start) : null;
  else {
    draftRange.value = {
      start: start ? startOfDay(start) : null,
      end: end ? startOfDay(end) : null,
    };
  }
  if (start) {
    startTime.value = { h: start.getHours(), m: start.getMinutes() };
    startHourText.value = pad2(start.getHours());
    startMinuteText.value = pad2(start.getMinutes());
  }
  if (end) {
    endTime.value = { h: end.getHours(), m: end.getMinutes() };
    endHourText.value = pad2(end.getHours());
    endMinuteText.value = pad2(end.getMinutes());
  }
};

watch(
  () => props.selected,
  (value) => {
    const incoming = stamp(value ?? null);
    if (incoming === seenSelected) return;
    seenSelected = incoming;
    if (incoming === stamp(drafted.value)) return;
    seedDraft(value ?? null);
  },
);

watch(
  () => props.startDate,
  (value) => {
    if (value) anchor.value = clampMonth(value);
  },
);

const onConfirm = () => {
  if (!canConfirm.value) return;
  if (props.mode === "single" && !draftSingle.value) return;
  emit("close", drafted.value);
};

const resolvePreset = (preset: MarDatePreset): Date | MarDateRange =>
  typeof preset.value === "function" ? preset.value(today) : preset.value;

const presetActive = (preset: MarDatePreset): boolean => {
  const value = resolvePreset(preset);
  if (value instanceof Date) return props.mode === "single" && sameDay(value, draftSingle.value);
  if (props.mode === "single") return false;
  return sameDay(value.start, draftRange.value.start) && sameDay(value.end, draftRange.value.end);
};

const onPreset = (preset: MarDatePreset) => {
  const value = resolvePreset(preset);
  seedDraft(value);
  const start = value instanceof Date ? value : value.start;
  if (start) anchor.value = clampMonth(start);
};

const fitsWeek = (value: Date | MarDateRange): boolean => {
  if (value instanceof Date || !value.start || !value.end) return false;
  const week = getDateWeek(value.start, props.firstDayOfWeek);
  return sameDay(week.start, value.start) && sameDay(week.end, value.end);
};

const shownPresets = computed<MarDatePreset[]>(() =>
  props.mode === "week" ? props.presets.filter((preset) => fitsWeek(resolvePreset(preset))) : props.presets,
);

const onClearDraft = () => {
  if (props.mode === "single") {
    draftSingle.value = null;
  } else {
    draftRange.value = { start: null, end: null };
  }
};

const onToday = () => {
  anchor.value = clampMonth(today);
  if (isDisabled(today)) return;
  if (props.mode === "single") {
    draftSingle.value = today;
  } else if (props.mode === "week") {
    draftRange.value = getDateWeek(today, props.firstDayOfWeek);
  } else {
    draftRange.value = { start: today, end: null };
  }
};

const yearList = computed<number[]>(() => {
  const center = cursorYear.value;
  const half = 30;
  const first = props.minDate ? props.minDate.getFullYear() : Math.min(center, props.maxDate?.getFullYear() ?? center) - half;
  const last = props.maxDate ? props.maxDate.getFullYear() : Math.max(center, first) + half;
  const out: number[] = [];
  for (let i = first; i <= last; i++) out.push(i);
  return out;
});

const yearListEl = ref<HTMLDivElement | null>(null);

watch(yearListOpen, async (v) => {
  if (!v) return;
  await nextTick();
  const el = yearListEl.value;
  if (!el) return;
  const active = el.querySelector<HTMLElement>(".mar-date-dropdown-year-btn.is-active");
  if (active) {
    el.scrollTo({ top: Math.max(0, active.offsetTop - el.clientHeight / 2 + active.offsetHeight / 2), behavior: "auto" });
  }
});

const onSelectYear = (y: number) => {
  anchor.value = clampMonth(new Date(y, cursorMonth.value, 1));
  yearListOpen.value = false;
};

const headValueEl = ref<HTMLElement | null>(null);
let headTip: ModalHandle | null = null;

const onHeadValueEnter = () => {
  const el = headValueEl.value;
  if (!el || el.scrollWidth <= el.clientWidth + 1) return;
  headTip = openModal({
    kind: "tooltip",
    text: headerText.value,
    anchor: el,
    placement: { side: "bottom" },
  });
};

const onHeadValueLeave = () => {
  headTip?.close();
  headTip = null;
};

onBeforeUnmount(onHeadValueLeave);

</script>

<template>
  <div class="mar-date-dropdown-panel">
    <div class="mar-date-dropdown-head">
      <div class="mar-date-dropdown-head-label">
        <span class="mar-date-dropdown-head-mode">
          {{ mode === "single" ? text.date : mode === "week" ? text.week : text.range }}
        </span>
        <span
          ref="headValueEl"
          class="mar-date-dropdown-head-value"
          @mouseenter="onHeadValueEnter"
          @mouseleave="onHeadValueLeave"
        >{{ headerText }}</span>
      </div>
    </div>

    <div class="mar-date-dropdown-body">
      <div class="mar-date-dropdown-nav">
        <button
          type="button"
          class="mar-date-dropdown-monthbtn"
          :aria-expanded="yearListOpen"
          @click="yearListOpen = !yearListOpen"
        >
          <span class="mar-date-dropdown-monthbtn-text">{{ monthLabel }}</span>
          <span
            class="mar-date-dropdown-monthbtn-chev"
            :data-open="yearListOpen ? '1' : null"
            aria-hidden="true"
          >
            ›
          </span>
        </button>
        <div class="mar-date-dropdown-nav-spacer" />
        <button
          type="button"
          class="mar-date-dropdown-iconbtn"
          :aria-label="text.previousMonth"
          :disabled="!canPrevMonth"
          @click="goPrevMonth"
        >
          <MarIcon icon="chevron-left" />
        </button>
        <button
          type="button"
          class="mar-date-dropdown-iconbtn"
          :aria-label="text.nextMonth"
          :disabled="!canNextMonth"
          @click="goNextMonth"
        >
          <MarIcon icon="chevron-right" />
        </button>
      </div>

      <div v-if="!yearListOpen" class="mar-date-dropdown-grid-wrap">
      <div class="mar-date-dropdown-weekdays">
        <div
          v-for="(label, i) in weekdayLabels"
          :key="i"
          class="mar-date-dropdown-weekday"
        >
          {{ label }}
        </div>
      </div>
      <div class="mar-date-dropdown-grid" @mouseleave="onGridLeave">
        <button
          v-for="(cell, i) in grid"
          :key="i"
          type="button"
          class="mar-date-dropdown-day"
          :class="{
            'is-out': !cell.inMonth,
            'is-disabled': cell.disabled,
            'is-today': cell.isToday,
            'is-selected': cell.isSelected,
            'is-range-start': cell.isRangeStart,
            'is-range-end': cell.isRangeEnd,
            'is-in-range': cell.isInRange,
          }"
          :disabled="cell.disabled"
          :data-date="cell.date.toISOString().slice(0, 10)"
          @click="onDayClick(cell)"
          @mouseenter="onDayHover(cell)"
        >
          <span class="mar-date-dropdown-day-bg" aria-hidden="true" />
          <span class="mar-date-dropdown-day-num">{{ cell.date.getDate() }}</span>
        </button>
      </div>
    </div>

    <div v-else class="mar-date-dropdown-yearlist" ref="yearListEl">
      <button
        v-for="y in yearList"
        :key="y"
        type="button"
        class="mar-date-dropdown-year-btn"
        :class="{ 'is-active': y === cursorYear }"
        @click="onSelectYear(y)"
      >
        {{ y }}
      </button>
    </div>

    </div>

    <div v-if="withTime && !yearListOpen" class="mar-date-dropdown-time">
      <div class="mar-date-dropdown-time-row">
        <span class="mar-date-dropdown-time-label">{{ mode === "single" ? text.time : text.start }}</span>
        <div class="mar-date-dropdown-time-inputs">
          <div class="mar-date-dropdown-time-seg-group">
            <input
              ref="startHourEl"
              type="text"
              inputmode="numeric"
              autocomplete="off"
              maxlength="2"
              class="mar-date-dropdown-time-seg"
              :aria-label="text.hour"
              :value="startHourText"
              @input="(e) => onTimeInput(e, 'start', 'h')"
              @keydown="(e) => onTimeKey(e, 'start', 'h')"
              @focus="selectAll(startHourEl)"
              @blur="onTimeBlur('start', 'h')"
            />
            <div class="mar-date-dropdown-time-stepper">
              <button
                type="button"
                class="mar-date-dropdown-time-stepbtn"
                :aria-label="text.hourUp"
                @click="bumpTime('start', 'h', 1)"
              >
                <MarIcon icon="chevron-up" :width="12" :height="12" />
              </button>
              <button
                type="button"
                class="mar-date-dropdown-time-stepbtn"
                :aria-label="text.hourDown"
                @click="bumpTime('start', 'h', -1)"
              >
                <MarIcon icon="chevron-down" :width="12" :height="12" />
              </button>
            </div>
          </div>
          <span class="mar-date-dropdown-time-colon">:</span>
          <div class="mar-date-dropdown-time-seg-group">
            <input
              ref="startMinuteEl"
              type="text"
              inputmode="numeric"
              autocomplete="off"
              maxlength="2"
              class="mar-date-dropdown-time-seg"
              :aria-label="text.minute"
              :value="startMinuteText"
              @input="(e) => onTimeInput(e, 'start', 'm')"
              @keydown="(e) => onTimeKey(e, 'start', 'm')"
              @focus="selectAll(startMinuteEl)"
              @blur="onTimeBlur('start', 'm')"
            />
            <div class="mar-date-dropdown-time-stepper">
              <button
                type="button"
                class="mar-date-dropdown-time-stepbtn"
                :aria-label="text.minuteUp"
                @click="bumpTime('start', 'm', 1)"
              >
                <MarIcon icon="chevron-up" :width="12" :height="12" />
              </button>
              <button
                type="button"
                class="mar-date-dropdown-time-stepbtn"
                :aria-label="text.minuteDown"
                @click="bumpTime('start', 'm', -1)"
              >
                <MarIcon icon="chevron-down" :width="12" :height="12" />
              </button>
            </div>
          </div>
        </div>
      </div>
      <div v-if="mode !== 'single'" class="mar-date-dropdown-time-row">
        <span class="mar-date-dropdown-time-label">{{ text.end }}</span>
        <div class="mar-date-dropdown-time-inputs">
          <div class="mar-date-dropdown-time-seg-group">
            <input
              ref="endHourEl"
              type="text"
              inputmode="numeric"
              autocomplete="off"
              maxlength="2"
              class="mar-date-dropdown-time-seg"
              :aria-label="text.endHour"
              :value="endHourText"
              @input="(e) => onTimeInput(e, 'end', 'h')"
              @keydown="(e) => onTimeKey(e, 'end', 'h')"
              @focus="selectAll(endHourEl)"
              @blur="onTimeBlur('end', 'h')"
            />
            <div class="mar-date-dropdown-time-stepper">
              <button
                type="button"
                class="mar-date-dropdown-time-stepbtn"
                :aria-label="text.endHourUp"
                @click="bumpTime('end', 'h', 1)"
              >
                <MarIcon icon="chevron-up" :width="12" :height="12" />
              </button>
              <button
                type="button"
                class="mar-date-dropdown-time-stepbtn"
                :aria-label="text.endHourDown"
                @click="bumpTime('end', 'h', -1)"
              >
                <MarIcon icon="chevron-down" :width="12" :height="12" />
              </button>
            </div>
          </div>
          <span class="mar-date-dropdown-time-colon">:</span>
          <div class="mar-date-dropdown-time-seg-group">
            <input
              ref="endMinuteEl"
              type="text"
              inputmode="numeric"
              autocomplete="off"
              maxlength="2"
              class="mar-date-dropdown-time-seg"
              :aria-label="text.endMinute"
              :value="endMinuteText"
              @input="(e) => onTimeInput(e, 'end', 'm')"
              @keydown="(e) => onTimeKey(e, 'end', 'm')"
              @focus="selectAll(endMinuteEl)"
              @blur="onTimeBlur('end', 'm')"
            />
            <div class="mar-date-dropdown-time-stepper">
              <button
                type="button"
                class="mar-date-dropdown-time-stepbtn"
                :aria-label="text.endMinuteUp"
                @click="bumpTime('end', 'm', 1)"
              >
                <MarIcon icon="chevron-up" :width="12" :height="12" />
              </button>
              <button
                type="button"
                class="mar-date-dropdown-time-stepbtn"
                :aria-label="text.endMinuteDown"
                @click="bumpTime('end', 'm', -1)"
              >
                <MarIcon icon="chevron-down" :width="12" :height="12" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div v-if="shownPresets.length" class="mar-date-dropdown-presets">
      <button
        v-for="preset in shownPresets"
        :key="preset.label"
        type="button"
        class="mar-date-dropdown-preset"
        :class="{ 'is-active': presetActive(preset) }"
        :aria-pressed="presetActive(preset)"
        @click="onPreset(preset)"
      >
        {{ preset.label }}
      </button>
    </div>

    <div class="mar-date-dropdown-actions">
      <button
        type="button"
        class="mar-panel-text-btn"
        :disabled="isDisabled(today)"
        @click="onToday"
      >
        {{ text.today }}
      </button>
      <button
        v-if="!required"
        type="button"
        class="mar-panel-text-btn"
        @click="onClearDraft"
      >
        {{ text.clear }}
      </button>
      <div class="mar-date-dropdown-actions-spacer" />
      <button
        type="button"
        class="mar-panel-text-btn"
        @click="onCancel"
      >
        {{ text.cancel }}
      </button>
      <button
        type="button"
        class="mar-panel-confirm-btn"
        :disabled="!canConfirm"
        @click="onConfirm"
      >
        {{ text.confirm }}
      </button>
    </div>
  </div>
</template>

