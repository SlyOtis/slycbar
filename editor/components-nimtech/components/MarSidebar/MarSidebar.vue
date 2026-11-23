<script lang="ts">
import { computed as moduleComputed, defineComponent, provide, shallowRef, type InjectionKey, type PropType } from "vue";

export interface MarSidebarSplitCollapsed {
  top?: boolean;
  bottom?: boolean;
}

export interface MarSidebarSplitRow {
  el: () => HTMLElement | null;
  header: () => HTMLElement | null;
  expanded: () => boolean | undefined;
  share: () => number | undefined;
  putExpanded: (value: boolean) => void;
  putShare: (value: number | undefined) => void;
}

export interface MarSidebarSplitPane {
  collapsed: () => boolean;
  toggle: () => void;
  row: () => number;
  place: () => void;
}

export interface MarSidebarSplit {
  postRow: (row: MarSidebarSplitRow) => MarSidebarSplitPane;
  deleteRow: (row: MarSidebarSplitRow) => void;
}

export const MAR_SIDEBAR_SPLIT: InjectionKey<MarSidebarSplit | null> = Symbol("MarSidebarSplit");

export const MAR_SIDEBAR_MENU: InjectionKey<boolean> = Symbol("MarSidebarMenu");

const MarSidebarPane = defineComponent({
  props: { split: { type: Object as PropType<MarSidebarSplit>, required: true } },
  setup(props, { slots }) {
    provide(MAR_SIDEBAR_SPLIT, props.split);
    return () => slots.default?.();
  },
});

const MarSidebarMenu = defineComponent({
  setup(_, { slots }) {
    provide(MAR_SIDEBAR_MENU, true);
    return () => slots.default?.();
  },
});

export interface MarSidebarCycleEntry {
  el: () => Element | null;
  side: () => "left" | "right";
  index?: () => number;
  getCollapsed: () => boolean;
  close: () => void;
  open: () => void;
}

type DocState = Document & {
  __marSidebarRegistry?: MarSidebarCycleEntry[];
  __marSidebarCyclePhase?: "closing" | "opening";
  __marSidebarKeydown?: (e: KeyboardEvent) => void;
};

const registryVersion = shallowRef(0);

export const putSidebarChange = () => {
  registryVersion.value += 1;
};

const getRegistry = (): MarSidebarCycleEntry[] => {
  if (typeof document === "undefined") return [];
  const doc = document as DocState;
  if (!doc.__marSidebarRegistry) doc.__marSidebarRegistry = [];
  return doc.__marSidebarRegistry;
};

const getCyclePhase = (): "closing" | "opening" => {
  if (typeof document === "undefined") return "closing";
  return (document as DocState).__marSidebarCyclePhase ?? "closing";
};

const setCyclePhase = (phase: "closing" | "opening") => {
  if (typeof document === "undefined") return;
  (document as DocState).__marSidebarCyclePhase = phase;
};

const ordered = (registry: MarSidebarCycleEntry[]): MarSidebarCycleEntry[] =>
  registry
    .filter((e) => e.el()?.isConnected)
    .sort((a, b) =>
      (a.el() as Element).compareDocumentPosition(b.el() as Element) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1,
    );

const onGlobalKeydown = (e: KeyboardEvent) => {
  const isCycle =
    (e.ctrlKey || e.metaKey) && e.shiftKey && (e.key === "s" || e.key === "S");
  if (!isCycle) return;
  const registry = ordered(getRegistry());
  if (registry.length === 0) return;

  e.preventDefault();
  e.stopImmediatePropagation();

  const opened = registry.filter((r) => !r.getCollapsed());
  const closed = registry.filter((r) => r.getCollapsed());
  const phase = getCyclePhase();

  if (phase === "closing") {
    if (opened.length > 0) {
      opened[opened.length - 1].close();
      if (opened.length === 1) setCyclePhase("opening");
    } else {
      setCyclePhase("opening");
      closed[0]?.open();
    }
  } else {
    if (closed.length > 0) {
      closed[0].open();
      if (closed.length === 1) setCyclePhase("closing");
    } else {
      setCyclePhase("closing");
      opened[opened.length - 1]?.close();
    }
  }
};

export const postSidebarCycle = (entry: MarSidebarCycleEntry) => {
  if (typeof document === "undefined") return;
  const registry = getRegistry();
  if (!registry.includes(entry)) registry.push(entry);
  putSidebarChange();
  const doc = document as DocState;
  if (doc.__marSidebarKeydown) return;
  doc.__marSidebarKeydown = onGlobalKeydown;
  doc.addEventListener("keydown", onGlobalKeydown);
};

export const useSidebarToggle = () => {
  const entry = moduleComputed(() => {
    void registryVersion.value;
    return ordered(getRegistry()).find(
      (e) => e.side() === "left" && e.index?.() !== 0 && !!e.el()?.classList.contains("mar-sidebar"),
    ) ?? null;
  });
  const collapsed = moduleComputed(() => {
    void registryVersion.value;
    return entry.value?.getCollapsed() ?? true;
  });
  const toggle = () => {
    const e = entry.value;
    if (!e) return;
    if (e.getCollapsed()) e.open();
    else e.close();
  };
  return { entry, present: moduleComputed(() => !!entry.value), collapsed, toggle };
};

export const deleteSidebarCycle = (entry: MarSidebarCycleEntry) => {
  if (typeof document === "undefined") return;
  const registry = getRegistry();
  const i = registry.indexOf(entry);
  if (i >= 0) registry.splice(i, 1);
  putSidebarChange();
  if (registry.length > 0) return;
  const doc = document as DocState;
  if (!doc.__marSidebarKeydown) return;
  doc.removeEventListener("keydown", doc.__marSidebarKeydown);
  delete doc.__marSidebarKeydown;
};
</script>

<script setup lang="ts">
import {
  onActivated,
  onBeforeUnmount,
  onDeactivated,
  onMounted,
  reactive,
  ref,
  computed,
  useId,
  watch,
  type VNode,
} from "vue";
import { useViewport } from "@/composables/useViewport";
import MarGridResize from "../MarGridResize";
import MarIcon from "../MarIcon";
import MarIconBtn from "../MarIconBtn";

export type MarSidebarSide = "left" | "right";

const walkIndex = (el: Element): number => {
  let count = 0;
  let current: Element | null = el;
  while (current) {
    let sibling = current.previousElementSibling;
    while (sibling) {
      if (sibling.classList.contains("mar-sidebar")) count += 1;
      count += sibling.querySelectorAll(".mar-sidebar").length;
      sibling = sibling.previousElementSibling;
    }
    current = current.parentElement;
  }
  return count + 1;
};

const props = withDefaults(
  defineProps<{
    /** Controlled collapse state published into the sidebar CSS variables. */
    collapsed?: boolean;
    /** Pane width as a CSS length; capped to 85vw while the pane is a mobile drawer. */
    width?: string;
    /** Edge the pane hugs and which border it draws. */
    side?: MarSidebarSide;
    /**
     * Explicit slot in the sidebar registry and CSS variable namespace; derived from DOM order when omitted.
     * @minimum 1
     */
    index?: number;
    /**
     * Share of the nav height the first row holds while the `split` slot is given and the nav has two rows; unset, each row takes what its content needs.
     * @minimum 0
     * @maximum 1
     */
    split?: number;
    /** Which split rows are collapsed to their header, top the first row and bottom the last. */
    splitCollapsed?: MarSidebarSplitCollapsed;
  }>(),
  {
    collapsed: false,
    width: "12em",
    side: "left",
    split: undefined,
    splitCollapsed: () => ({}),
  },
);

const emit = defineEmits<{
  close: [];
  open: [];
  "update:split": [value: number | undefined];
  "update:splitCollapsed": [value: MarSidebarSplitCollapsed];
}>();

defineSlots<{
  default?: () => VNode[];
  header?: () => VNode[];
  footer?: () => VNode[];
  split?: () => VNode[];
  menu?: () => VNode[];
  "menu-mark"?: () => VNode[];
}>();

const splitId = useId();
const splitTarget = `[data-mar-sidebar-split="${splitId}"]`;
const splitRatio = ref(props.split);

watch(
  () => props.split,
  (value) => {
    splitRatio.value = value;
  },
);

const splitCollapsed = ref<MarSidebarSplitCollapsed>({ ...props.splitCollapsed });

watch(
  () => props.splitCollapsed,
  (value) => {
    splitCollapsed.value = { ...value };
  },
);

const splitRows = shallowRef<MarSidebarSplitRow[]>([]);
const splitVersion = ref(0);
const splitHeld = reactive(new Map<MarSidebarSplitRow, { collapsed?: boolean; share?: number }>());

const putSplitCollapsed = (next: MarSidebarSplitCollapsed) => {
  if (!!next.top === !!splitCollapsed.value.top && !!next.bottom === !!splitCollapsed.value.bottom) return;
  splitCollapsed.value = { top: !!next.top, bottom: !!next.bottom };
  emit("update:splitCollapsed", splitCollapsed.value);
};

const splitOrder = (a: MarSidebarSplitRow, b: MarSidebarSplitRow) => {
  const one = a.el();
  const two = b.el();
  if (!one?.isConnected || !two?.isConnected) return 0;
  return one.compareDocumentPosition(two) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1;
};

const splitOrdered = computed(() => {
  void splitVersion.value;
  return [...splitRows.value].sort(splitOrder);
});

const getSplitEdge = (row: MarSidebarSplitRow): "top" | "bottom" | null => {
  const at = splitOrdered.value.indexOf(row);
  if (at === 0) return "top";
  if (at === splitOrdered.value.length - 1) return "bottom";
  return null;
};

const getSplitCollapsed = (row: MarSidebarSplitRow): boolean => {
  const bound = row.expanded();
  if (bound !== undefined) return !bound;
  const edge = getSplitEdge(row);
  return edge ? !!splitCollapsed.value[edge] : !!splitHeld.get(row)?.collapsed;
};

const getSplitShare = (row: MarSidebarSplitRow): number | undefined => {
  const bound = row.share();
  if (bound !== undefined) return bound;
  const rows = splitOrdered.value;
  if (rows.length === 2 && splitRatio.value !== undefined) return rows[0] === row ? splitRatio.value : 1 - splitRatio.value;
  return splitHeld.get(row)?.share;
};

const putSplitRow = (row: MarSidebarSplitRow, collapsed: boolean) => {
  splitHeld.set(row, { ...splitHeld.get(row), collapsed });
  row.putExpanded(!collapsed);
  const edge = getSplitEdge(row);
  if (edge) putSplitCollapsed({ ...splitCollapsed.value, [edge]: collapsed });
};

const putSplitShare = (row: MarSidebarSplitRow, share: number | undefined) => {
  if (share === getSplitShare(row)) return;
  splitHeld.set(row, { ...splitHeld.get(row), share });
  row.putShare(share);
};

const splitNav: MarSidebarSplit = {
  postRow: (row) => {
    splitRows.value = [...splitRows.value, row];
    return {
      collapsed: () => getSplitCollapsed(row),
      toggle: () => putSplitRow(row, !getSplitCollapsed(row)),
      row: () => splitOrdered.value.indexOf(row) + 1,
      place: () => {
        splitVersion.value += 1;
      },
    };
  },
  deleteRow: (row) => {
    splitRows.value = splitRows.value.filter((one) => one !== row);
    splitHeld.delete(row);
  },
};

const splitTemplate = computed(() =>
  splitOrdered.value
    .map((row) => {
      if (getSplitCollapsed(row)) return "auto";
      const share = getSplitShare(row);
      return `minmax(var(--mar-sidebar-split-min), ${share === undefined ? "auto" : `${share}fr`})`;
    })
    .join(" "),
);

let splitFrom = new Map<MarSidebarSplitRow, number | undefined>();

const onSplitStart = () => {
  splitFrom = new Map(splitOrdered.value.map((row) => [row, getSplitShare(row)]));
};

const getSplitRatio = (size: number, height: number) => Math.round((size / height) * 1000) / 1000;

const onSplit = (below: MarSidebarSplitRow, size: number) => {
  const nav = document.querySelector<HTMLElement>(splitTarget);
  if (!nav || nav.clientHeight <= 0) return;
  const rows = splitOrdered.value;
  const at = rows.indexOf(below);
  if (at < 1) return;
  const above = rows[at - 1];
  const box = nav.getBoundingClientRect();
  const height = nav.clientHeight;
  const open = rows.filter((row) => !getSplitCollapsed(row));
  const top = (row: MarSidebarSplitRow) => (row.el()?.getBoundingClientRect().top ?? box.top) - box.top;
  const end = (row: MarSidebarSplitRow) =>
    row === open[open.length - 1] || row === rows[rows.length - 1] ? height : (row.el()?.getBoundingClientRect().bottom ?? box.top) - box.top;
  const heights = new Map(open.map((row) => [row, end(row) - top(row)]));
  heights.set(above, size - top(above));
  heights.set(below, end(below) - size);
  for (const row of [above, below]) {
    const shut = (heights.get(row) ?? 0) <= (row.header()?.offsetHeight ?? 0);
    if (shut !== getSplitCollapsed(row)) putSplitRow(row, shut);
    if (!shut) continue;
    heights.delete(row);
    putSplitShare(row, splitFrom.get(row));
  }
  if (rows.length === 2) {
    const [first, second] = rows;
    const ratio = heights.has(first) && heights.has(second) ? getSplitRatio(heights.get(first) ?? 0, (heights.get(first) ?? 0) + (heights.get(second) ?? 0)) : splitFrom.get(first);
    if (ratio !== splitRatio.value) {
      splitRatio.value = ratio;
      emit("update:split", ratio);
    }
  }
  for (const [row, value] of heights) putSplitShare(row, getSplitRatio(value, height));
};

const rootEl = ref<HTMLElement | null>(null);
const resolvedIndex = ref(0);

const { mobile } = useViewport();

const paneWidth = computed(() => (mobile.value ? "100%" : props.width));

const onDrawerNavigate = (event: Event) => {
  const url = (event as Event & { destination?: { url: string } }).destination?.url;
  if (url && new URL(url).pathname === location.pathname) return;
  emit("close");
};

const onDrawerKey = (event: KeyboardEvent) => {
  if (event.key === "Escape") emit("close");
};

const getNavigation = () => (window as Window & { navigation?: EventTarget }).navigation;

const putDrawerListeners = (on: boolean) => {
  if (typeof window === "undefined") return;
  const target = getNavigation() ?? window;
  const type = getNavigation() ? "navigate" : "popstate";
  if (on) {
    target.addEventListener(type, onDrawerNavigate);
    window.addEventListener("keydown", onDrawerKey);
    return;
  }
  target.removeEventListener(type, onDrawerNavigate);
  window.removeEventListener("keydown", onDrawerKey);
};

watch(
  () => mobile.value && !props.collapsed,
  (open) => putDrawerListeners(open),
  { immediate: true },
);

onBeforeUnmount(() => putDrawerListeners(false));

const publishVars = () => {
  if (typeof document === "undefined" || resolvedIndex.value === 0) return;
  if (!rootEl.value?.isConnected) return;
  document.documentElement.style.setProperty(
    `--mar-sidebar-${resolvedIndex.value}-max`,
    paneWidth.value,
  );
  document.documentElement.style.setProperty(
    `--mar-sidebar-${resolvedIndex.value}-size`,
    props.collapsed || mobile.value ? "0px" : paneWidth.value,
  );
  document.documentElement.style.setProperty(
    `--mar-sidebar-${resolvedIndex.value}-side`,
    props.side,
  );
};

const unpublishVars = () => {
  if (typeof document === "undefined" || resolvedIndex.value === 0) return;
  document.documentElement.style.removeProperty(
    `--mar-sidebar-${resolvedIndex.value}-max`,
  );
  document.documentElement.style.removeProperty(
    `--mar-sidebar-${resolvedIndex.value}-size`,
  );
  document.documentElement.style.removeProperty(
    `--mar-sidebar-${resolvedIndex.value}-side`,
  );
};

const cycle: MarSidebarCycleEntry = {
  el: () => rootEl.value,
  side: () => props.side,
  index: () => resolvedIndex.value,
  getCollapsed: () => props.collapsed,
  close: () => emit("close"),
  open: () => emit("open"),
};

const { entry: shellEntry } = useSidebarToggle();
const toggleShown = computed(() => !mobile.value && props.collapsed && shellEntry.value === cycle);

const claimIndex = () => {
  if (props.index === undefined && !rootEl.value?.isConnected) return;
  const next =
    props.index !== undefined ? props.index : walkIndex(rootEl.value as Element);
  if (resolvedIndex.value !== 0 && resolvedIndex.value !== next) unpublishVars();
  resolvedIndex.value = next;
  publishVars();
};

onMounted(() => {
  claimIndex();
  postSidebarCycle(cycle);
});

onActivated(() => {
  claimIndex();
  postSidebarCycle(cycle);
});

onDeactivated(() => {
  unpublishVars();
  deleteSidebarCycle(cycle);
});

watch(
  () => [props.collapsed, paneWidth.value, props.side] as const,
  () => {
    publishVars();
    putSidebarChange();
  },
);

onBeforeUnmount(() => {
  unpublishVars();
  deleteSidebarCycle(cycle);
});
</script>

<template>
  <div
    ref="rootEl"
    :class="[
      'mar-sidebar',
      side === 'right' ? 'mar-sidebar-right' : 'mar-sidebar-left',
      { 'mar-sidebar-drawer': mobile, 'mar-sidebar-drawer-menu': mobile && !!$slots.menu, 'mar-sidebar-open': !collapsed },
    ]"
    :data-sidebar="resolvedIndex"
  >
    <div
      v-if="mobile"
      class="mar-sidebar-scrim"
      @click="emit('close')"
    ></div>
    <button
      v-if="mobile"
      type="button"
      class="mar-sidebar-menu"
      :aria-label="collapsed ? 'Open the menu' : 'Close the menu'"
      :aria-expanded="!collapsed"
      @click="collapsed ? emit('open') : emit('close')"
    >
      <span v-if="collapsed && $slots['menu-mark']" class="mar-sidebar-menu-mark">
        <slot name="menu-mark" />
      </span>
      <MarIcon v-else :icon="collapsed ? 'menu' : 'cross'" />
    </button>
    <MarIconBtn
      v-if="toggleShown"
      class="mar-sidebar-toggle"
      icon="sidebar"
      tooltip="Show the sidebar"
      @click="emit('open')"
    />
    <aside class="mar-sidebar-pane" :style="{ width: mobile ? undefined : paneWidth }">
      <nav v-if="mobile && $slots.menu" class="mar-sidebar-nav mar-sidebar-menu-list">
        <MarSidebarMenu>
          <slot name="menu" />
        </MarSidebarMenu>
      </nav>
      <template v-else>
        <div v-if="$slots.header" class="mar-sidebar-header">
          <slot name="header" />
        </div>
        <nav
          v-if="$slots.split"
          class="mar-sidebar-nav mar-sidebar-nav-split"
          :data-mar-sidebar-split="splitId"
          :style="{ gridTemplateRows: splitTemplate }"
        >
          <div class="mar-sidebar-nav-pane">
            <MarSidebarPane :split="splitNav">
              <slot />
            </MarSidebarPane>
          </div>
          <div class="mar-sidebar-split-pane">
            <MarSidebarPane :split="splitNav">
              <slot name="split" />
            </MarSidebarPane>
          </div>
          <div
            v-for="(row, at) in splitOrdered.slice(1)"
            :key="at"
            class="mar-sidebar-split-seam"
            :style="{ gridRow: at + 2 }"
          >
            <MarGridResize
              align="top"
              :target="splitTarget"
              variable="--mar-sidebar-split-size"
              @pointerdown="onSplitStart"
              @resize="onSplit(row, $event)"
            />
          </div>
        </nav>
        <nav v-else class="mar-sidebar-nav">
          <slot />
        </nav>
        <div v-if="$slots.footer" class="mar-sidebar-footer">
          <slot name="footer" />
        </div>
      </template>
    </aside>
  </div>
</template>

<style scoped>
.mar-sidebar {
  position: relative;
  overflow: hidden;
  width: 100%;
  height: 100%;
  font-size: var(--mar-text-base);
}

.mar-sidebar-pane {
  position: absolute;
  top: 0;
  bottom: 0;
  display: flex;
  flex-direction: column;
  background: var(--mar-sidebar-bg);
  overflow-x: hidden;
}

.mar-sidebar-left .mar-sidebar-pane {
  right: 0;
}

.mar-sidebar-right .mar-sidebar-pane {
  left: 0;
}

.mar-sidebar-drawer {
  position: fixed;
  inset: 0;
  width: auto;
  height: auto;
  z-index: 900;
  pointer-events: none;
  overflow: visible;
}

.mar-sidebar-scrim {
  position: absolute;
  inset: 0;
  background: var(--mar-overlay-backdrop);
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-sidebar-drawer.mar-sidebar-open {
  pointer-events: auto;
}

.mar-sidebar-drawer.mar-sidebar-open .mar-sidebar-scrim {
  opacity: 1;
  pointer-events: auto;
}

.mar-sidebar-drawer .mar-sidebar-pane {
  inset-block: calc(4em + env(safe-area-inset-top, 0px)) auto;
  inset-inline: calc(0.75em + env(safe-area-inset-left, 0px)) calc(0.75em + env(safe-area-inset-right, 0px));
  block-size: 85dvh;
  max-block-size: calc(100dvh - 4.75em - env(safe-area-inset-top, 0px) - env(safe-area-inset-bottom, 0px));
  border-radius: 1.25em;
  box-shadow: var(--glass-shadow);
  transform: scale(0.08);
  transform-origin: 1.375em -1.875em;
  opacity: 0;
  visibility: hidden;
  transition:
    transform 0.24s cubic-bezier(0.4, 0, 1, 1),
    opacity 0.2s ease 0.04s,
    visibility 0s linear 0.24s;
  will-change: transform;
}

.mar-sidebar-drawer.mar-sidebar-open .mar-sidebar-pane {
  transform: none;
  opacity: 1;
  visibility: visible;
  transition:
    transform 0.3s cubic-bezier(0.2, 0.9, 0.3, 1),
    opacity 0.2s ease,
    visibility 0s;
}

.mar-sidebar-drawer-menu .mar-sidebar-pane {
  block-size: auto;
  border: 1px solid var(--glass-border);
  background: var(--glass-sheen), var(--glass-surface-overlay);
  -webkit-backdrop-filter: blur(var(--glass-blur-strong)) saturate(var(--glass-saturate));
  backdrop-filter: blur(var(--glass-blur-strong)) saturate(var(--glass-saturate));
  padding-block: 0.25em;
}

.mar-sidebar-menu {
  position: fixed;
  inset-block-start: calc(0.75em + env(safe-area-inset-top, 0px));
  inset-inline-start: calc(0.75em + env(safe-area-inset-left, 0px));
  z-index: 1;
  display: grid;
  place-items: center;
  inline-size: 2.75em;
  block-size: 2.75em;
  padding: 0;
  border: 1px solid var(--glass-border);
  border-radius: 50%;
  background: var(--glass-sheen), var(--glass-surface-raised);
  box-shadow: var(--glass-shadow);
  -webkit-backdrop-filter: blur(var(--glass-blur-strong)) saturate(var(--glass-saturate));
  backdrop-filter: blur(var(--glass-blur-strong)) saturate(var(--glass-saturate));
  color: var(--mar-text-color);
  font-size: var(--mar-text-base);
  cursor: pointer;
  pointer-events: auto;
}

.mar-sidebar-toggle {
  position: fixed;
  inset-block-start: 0.5em;
  inset-inline-start: 0.5em;
  z-index: 2;
}

.mar-sidebar-menu-mark {
  display: flex;
  align-items: center;
  justify-content: center;
  inline-size: 55%;
  block-size: 55%;
  overflow: hidden;
}

.mar-sidebar-menu-mark > :slotted(img),
.mar-sidebar-menu-mark > :slotted(svg) {
  inline-size: 100%;
  block-size: 100%;
  margin: 0;
  padding: 0;
  object-fit: contain;
}

.mar-sidebar-menu:focus-visible {
  outline: none;
  box-shadow: inset 0 0 0 2px var(--mar-primary-color), var(--glass-shadow);
}

.mar-sidebar-header {
  display: flex;
  align-items: center;
  gap: 0.5em;
  padding: 0.625em 0.75em;
  border-bottom: 1px solid var(--mar-sidebar-border);
  min-height: 2.5em;
  flex: 0 0 auto;
}

.mar-sidebar-nav {
  display: flex;
  flex-direction: column;
  overflow-y: auto;
  overflow-x: hidden;
  flex: 1 1 auto;
  min-height: 0;
  scrollbar-width: thin;
  scrollbar-color: var(--mar-surface-400) transparent;
}

.mar-sidebar-nav:not(.mar-sidebar-nav-split) {
  padding-block: 0.5em;
}

.mar-sidebar-nav-split {
  --mar-sidebar-split-min: 2.5em;
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  align-content: start;
  padding-block: 0.5em;
  overflow: hidden;
}

.mar-sidebar-nav-pane,
.mar-sidebar-split-pane {
  display: contents;
}

.mar-sidebar-split-seam {
  position: relative;
  grid-column: 1;
  align-self: start;
  block-size: 0;
  z-index: 3;
}

.mar-sidebar-nav::-webkit-scrollbar {
  width: 0.375em;
}

.mar-sidebar-nav::-webkit-scrollbar-track {
  background: transparent;
}

.mar-sidebar-nav::-webkit-scrollbar-thumb {
  background: var(--mar-surface-400);
  border-radius: 9999px;
}

.mar-sidebar-nav:hover::-webkit-scrollbar-thumb {
  background: var(--mar-surface-500);
}

.mar-sidebar-footer {
  display: flex;
  flex-direction: column;
  padding-block: 0.5em calc(0.5em + env(safe-area-inset-bottom, 0px));
  border-top: 1px solid var(--mar-sidebar-border);
  flex: 0 0 auto;
}
</style>
