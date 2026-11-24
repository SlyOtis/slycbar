<script setup lang="ts">
import { computed, reactive, ref } from "vue";
import MarIcon from "../MarIcon";
import MarBlockMore from "../MarBlockMore";
import MarDropdown from "../MarDropdown";
import MarListGroup from "../MarListGroup";
import MarFileExplorerTile from "./MarFileExplorerTile.vue";
import {
  closeModal,
  openModal,
  submenuPlacement,
  type ModalAnchorRect,
} from "@/composables/useModals";
import { useViewport } from "@/composables/useViewport";
import type { BlockOption } from "@/blockedit/interaction/blockOptions.ts";
import type { MarPresenceUser } from "../MarPresence";
import type { IconType } from "@/types/icon.types";
import { getFileIcon } from "@/utils/fileIcon";
import type {
  MarFileGroupBy,
  MarFileItem,
  MarFileMoveTarget,
} from "./marFileExplorer.types";

interface FileGroup {
  key: string;
  label: string;
  order: number;
  items: MarFileItem[];
}

const {
  items,
  selectedIds = new Set<string>(),
  groupBy = "none",
  presence = {},
  showTags = false,
  showAdd = false,
  addLabel = "Add",
  addIcon = "plus",
  itemOptions = undefined,
  moveTargets = [],
  moveLabel = "Move",
  moveSearchPlaceholder = "Search folders",
  selectable = false,
  selectLabel = "Select",
  deselectLabel = "Deselect",
  loading = false,
} = defineProps<{
  /** Items to display as tiles in the grid. */
  items: MarFileItem[];
  /** Draws placeholder tiles until the first items arrive. */
  loading?: boolean;
  /** Reveals the item tags as chips while the tile is hovered. */
  showTags?: boolean;
  /** Renders the add tile as the first tile of the grid, which emits add and is never an item. */
  showAdd?: boolean;
  /** Label under the glyph of the add tile. */
  addLabel?: string;
  /** Glyph of the add tile. */
  addIcon?: IconType;
  /** Ids rendered with the selection outline, owned by the consumer. */
  selectedIds?: Set<string>;
  /** Grouping mode splitting the grid into labeled sections by kind, type, modified bucket, first letter, or tag. */
  groupBy?: MarFileGroupBy;
  /** Map from item id to users shown as stacked avatars on the tile. */
  presence?: Record<string, MarPresenceUser[]>;
  /** Transforms the default context menu options per item and returns the final list. */
  itemOptions?: (item: MarFileItem, defaults: BlockOption[]) => BlockOption[];
  /** Folders the Move entry pops out beside itself as a searchable submenu; empty leaves Move emitting with no target for the host to resolve. */
  moveTargets?: MarFileMoveTarget[];
  /** Text of the Move entry in the item menu. */
  moveLabel?: string;
  /** Placeholder of the destination search field. */
  moveSearchPlaceholder?: string;
  /** Turns the selection surface on, the tick over each icon and the pick entry in the item menu. */
  selectable?: boolean;
  /** Text of the pick entry in the item menu of an unselected item. */
  selectLabel?: string;
  /** Text of the pick entry in the item menu of a selected item. */
  deselectLabel?: string;
}>();

const emit = defineEmits<{
  add: [];
  open: [item: MarFileItem];
  select: [item: MarFileItem, event?: MouseEvent];
  selectend: [];
  hover: [item: MarFileItem, event: MouseEvent];
  hoverend: [];
  download: [item: MarFileItem];
  rename: [item: MarFileItem, name: string];
  move: [item: MarFileItem, targetId: string | null];
}>();

const isSelected = (id: string) => selectedIds.has(id);

const presenceFor = (id: string): MarPresenceUser[] => presence[id] ?? [];

const thumbLoaded = reactive(new Set<string>());
const thumbFailed = reactive(new Set<string>());
const thumbVersions = reactive(new Map<string, number>());

const onThumbLoad = (item: MarFileItem) => {
  thumbLoaded.add(item.id);
  thumbFailed.delete(item.id);
};

const onThumbError = (item: MarFileItem) => {
  thumbLoaded.delete(item.id);
  thumbFailed.add(item.id);
};

const thumbSrc = (item: MarFileItem): string => {
  const url = item.thumbnailUrl ?? "";
  const v = thumbVersions.get(item.id);
  if (!v) return url;
  return `${url}${url.includes("?") ? "&" : "?"}reload=${v}`;
};

const reloadThumb = (item: MarFileItem) => {
  thumbLoaded.delete(item.id);
  thumbFailed.delete(item.id);
  thumbVersions.set(item.id, (thumbVersions.get(item.id) ?? 0) + 1);
};

const iconName = (item: MarFileItem): IconType =>
  item.kind === "folder" ? "folder" : getFileIcon(item.name, item.mimeType);

const typeLabel = (item: MarFileItem): { key: string; label: string; order: number } => {
  if (item.kind === "folder") return { key: "folder", label: "Folders", order: 0 };
  switch (iconName(item)) {
    case "file-image":
    case "file-svg":
      return { key: "image", label: "Images", order: 1 };
    case "file-video":
      return { key: "video", label: "Videos", order: 2 };
    case "file-audio":
      return { key: "audio", label: "Audio", order: 3 };
    case "file-pdf":
    case "file-word":
    case "file-text":
      return { key: "doc", label: "Documents", order: 4 };
    case "file-sheet":
    case "file-csv":
      return { key: "sheet", label: "Spreadsheets", order: 5 };
    case "file-slides":
      return { key: "slides", label: "Presentations", order: 6 };
    case "file-archive":
      return { key: "archive", label: "Archives", order: 7 };
    case "file-code":
      return { key: "code", label: "Code", order: 8 };
    case "file-font":
      return { key: "font", label: "Fonts", order: 9 };
    case "palette":
      return { key: "drawing", label: "Whiteboards", order: 10 };
    default:
      return { key: "other", label: "Other", order: 11 };
  }
};

const startOfDay = (d: Date): number =>
  new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();

const modifiedBucket = (item: MarFileItem): { key: string; label: string; order: number } => {
  if (!item.updatedAt) return { key: "nodate", label: "No date", order: 5 };
  const t = new Date(item.updatedAt).getTime();
  if (Number.isNaN(t)) return { key: "nodate", label: "No date", order: 5 };
  const today = startOfDay(new Date());
  const day = 86400000;
  if (t >= today) return { key: "today", label: "Today", order: 0 };
  if (t >= today - 7 * day) return { key: "week", label: "This week", order: 1 };
  if (t >= today - 30 * day) return { key: "month", label: "This month", order: 2 };
  return { key: "earlier", label: "Earlier", order: 3 };
};

const nameBucket = (item: MarFileItem): { key: string; label: string; order: number } => {
  const ch = (item.name.trim()[0] ?? "#").toUpperCase();
  const isLetter = ch >= "A" && ch <= "Z";
  return {
    key: isLetter ? ch : "#",
    label: isLetter ? ch : "#",
    order: isLetter ? ch.charCodeAt(0) : 999,
  };
};

const bucketOf = (item: MarFileItem): { key: string; label: string; order: number } => {
  if (groupBy === "kind") {
    return item.kind === "folder"
      ? { key: "folder", label: "Folders", order: 0 }
      : { key: "file", label: "Files", order: 1 };
  }
  if (groupBy === "type") return typeLabel(item);
  if (groupBy === "modified") return modifiedBucket(item);
  return nameBucket(item);
};

const tagBuckets = (
  item: MarFileItem,
): { key: string; label: string; order: number }[] => {
  const tags = item.tags ?? [];
  if (!tags.length) return [{ key: "untagged", label: "No tags", order: 1 }];
  return tags.map((t) => ({ key: `tag:${t}`, label: t, order: 0 }));
};

const groups = computed<FileGroup[] | null>(() => {
  if (groupBy === "none") return null;
  const map = new Map<string, FileGroup>();
  for (const item of items) {
    const buckets = groupBy === "tag" ? tagBuckets(item) : [bucketOf(item)];
    for (const b of buckets) {
      let g = map.get(b.key);
      if (!g) {
        g = { key: b.key, label: b.label, order: b.order, items: [] };
        map.set(b.key, g);
      }
      g.items.push(item);
    }
  }
  return [...map.values()].sort((a, b) => a.order - b.order || a.label.localeCompare(b.label));
});

const ungroupedItems = computed<MarFileItem[]>(() => (groups.value ? [] : items));

const onAdd = () => {
  emit("add");
};

const { mobile } = useViewport();

const picking = computed(() => selectable && !mobile.value && selectedIds.size > 0);

const onExplorerLeave = () => {
  emit("hoverend");
};

const onEscape = () => {
  if (picking.value) emit("selectend");
};

const onBackgroundClick = (event: MouseEvent) => {
  if (!picking.value) return;
  const target = event.target as HTMLElement | null;
  if (target?.closest(".mar-file-explorer-item, .mar-file-explorer-add")) return;
  emit("selectend");
};

const onPick = (item: MarFileItem, event?: MouseEvent) => {
  emit("select", item, event);
};

const onOpen = (event: MouseEvent, item: MarFileItem) => {
  if (picking.value) return onPick(item, event);
  emit("open", item);
};

const draggingId = ref<string | null>(null);
const dropTargetId = ref<string | null>(null);

const resetDrag = () => {
  draggingId.value = null;
  dropTargetId.value = null;
};

const onDragStart = (event: DragEvent, item: MarFileItem) => {
  draggingId.value = item.id;
  if (!event.dataTransfer) return;
  event.dataTransfer.effectAllowed = "move";
  event.dataTransfer.setData("text/plain", item.id);
};

const dropAllowed = (item: MarFileItem): boolean =>
  !!draggingId.value && item.kind === "folder" && item.id !== draggingId.value;

const onDragOver = (event: DragEvent, item: MarFileItem) => {
  if (!dropAllowed(item)) return;
  event.preventDefault();
  if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
  dropTargetId.value = item.id;
};

const onDragLeave = (item: MarFileItem) => {
  if (dropTargetId.value === item.id) dropTargetId.value = null;
};

const onDrop = (event: DragEvent, item: MarFileItem) => {
  if (!dropAllowed(item)) return resetDrag();
  event.preventDefault();
  const source = items.find((i) => i.id === draggingId.value);
  resetDrag();
  if (!source) return;
  emit("move", source, item.id);
};

const onEnter = (e: MouseEvent, item: MarFileItem) => {
  if (renamingId.value) return;
  emit("hover", item, e);
};

const MENU_ID = "mar-file-explorer-more";

const renamingId = ref<string | null>(null);

const startRename = (item: MarFileItem) => {
  renamingId.value = item.id;
  emit("hoverend");
};

const commitRename = (item: MarFileItem, name: string) => {
  if (renamingId.value !== item.id) return;
  renamingId.value = null;
  emit("rename", item, name);
};

const cancelRename = () => {
  renamingId.value = null;
};

const MOVE_ID = "mar-file-explorer-move";

const targetsFor = (item: MarFileItem) =>
  moveTargets.filter((target) => target.id !== item.id);

const moveOption = (item: MarFileItem): BlockOption | null =>
  item.root
    ? null
    : {
        title: moveLabel,
        icon: "folder-open",
        submenu: targetsFor(item).length > 0,
        run: () => emit("move", item, null),
      };

const menuOptions = (item: MarFileItem, move: BlockOption | null): BlockOption[] => {
  const defaults: BlockOption[] = [
    {
      title: "Open",
      icon: item.kind === "folder" ? "folder-open" : "eye",
      run: () => emit("open", item),
    },
  ];
  if (selectable) {
    defaults.push({
      title: isSelected(item.id) ? deselectLabel : selectLabel,
      icon: "check",
      run: () => onPick(item),
    });
  }
  if (item.kind === "file" && item.url) {
    defaults.push({
      title: "Download",
      icon: "download",
      run: () => emit("download", item),
    });
  }
  if (item.thumbnailUrl && thumbFailed.has(item.id)) {
    defaults.push({
      title: "Reload thumbnail",
      icon: "refresh",
      run: () => reloadThumb(item),
    });
  }
  defaults.push({
    title: "Rename",
    icon: "pencil",
    run: () => startRename(item),
  });
  if (move) defaults.push(move);
  return itemOptions ? itemOptions(item, defaults) : defaults;
};

const openMove = (item: MarFileItem, anchor: ModalAnchorRect) => {
  void openModal({
    id: MOVE_ID,
    kind: "dropdown",
    component: MarDropdown,
    anchor: { target: anchor },
    placement: submenuPlacement,
    backdrop: "invisible",
    props: {
      options: targetsFor(item).map((target) => ({
        label: target.label,
        value: target.id,
      })),
      searchable: true,
      searchPlaceholder: moveSearchPlaceholder,
    },
    on: {
      close: (value?: unknown) => {
        closeModal(MOVE_ID);
        closeModal(MENU_ID);
        if (typeof value === "string" && value) emit("move", item, value);
      },
    },
  });
};

const onMore = (e: MouseEvent, item: MarFileItem) => {
  const move = moveOption(item);
  const options = menuOptions(item, move);
  if (!options.length) return;
  void openModal({
    id: MENU_ID,
    kind: "dropdown",
    component: MarBlockMore,
    anchor: { target: e.currentTarget as HTMLElement },
    placement: { side: "bottom", align: "end", offset: 4 },
    backdrop: "invisible",
    dismissOnEscape: false,
    props: { options },
    on: {
      close: () => closeModal(MENU_ID),
      submenu: (option?: unknown, anchor?: unknown) => {
        if (option !== move) return;
        openMove(item, anchor as ModalAnchorRect);
      },
    },
  });
};
</script>

<template>
  <div
    class="mar-file-explorer"
    tabindex="-1"
    @click="onBackgroundClick"
    @keydown.esc="onEscape"
    @mouseleave="onExplorerLeave"
    @dragend="resetDrag"
  >
    <div v-if="loading" class="mar-file-explorer-grid" aria-busy="true">
      <div
        v-for="n in 12"
        :key="`skeleton-${n}`"
        class="mar-file-explorer-skeleton"
        aria-hidden="true"
      >
        <div class="mar-skeleton mar-file-explorer-skeleton-area" />
        <div class="mar-skeleton mar-file-explorer-skeleton-label" />
      </div>
    </div>
    <div
      v-else-if="showAdd || !groups"
      :class="[
        'mar-file-explorer-grid',
        { 'mar-file-explorer-grid-add': showAdd && groups },
      ]"
    >
      <button
        v-if="showAdd"
        type="button"
        class="mar-file-explorer-add"
        @click="onAdd"
      >
        <div class="mar-file-explorer-add-area">
          <MarIcon :icon="addIcon" class="mar-file-explorer-add-icon" />
        </div>
        <span class="mar-file-explorer-add-label">{{ addLabel }}</span>
      </button>
      <MarFileExplorerTile
        v-for="item in ungroupedItems"
        :key="item.id"
        :item="item"
        :icon="iconName(item)"
        :selected="isSelected(item.id)"
        :selectable="selectable"
        :touch="mobile"
        :show-tags="showTags"
        :presence="presenceFor(item.id)"
        :renaming="renamingId === item.id"
        :dragging="draggingId === item.id"
        :drop-target="dropTargetId === item.id"
        :thumb-src="thumbSrc(item)"
        :thumb-loaded="thumbLoaded.has(item.id)"
        :thumb-failed="thumbFailed.has(item.id)"
        @open="onOpen($event, item)"
        @pick="onPick(item, $event)"
        @more="onMore($event, item)"
        @enter="onEnter($event, item)"
        @leave="emit('hoverend')"
        @dragstart="onDragStart($event, item)"
        @dragover="onDragOver($event, item)"
        @dragleave="onDragLeave(item)"
        @drop="onDrop($event, item)"
        @dragend="resetDrag"
        @thumbload="onThumbLoad(item)"
        @thumberror="onThumbError(item)"
        @rename="commitRename(item, $event)"
        @renamecancel="cancelRename"
      />
    </div>
    <template v-if="groups && !loading">
      <MarListGroup
        v-for="group in groups"
        :key="group.key"
        class="mar-file-explorer-group"
        :label="`${group.label} \u00b7 ${group.items.length}`"
      >
        <div class="mar-file-explorer-grid mar-file-explorer-grid-grouped">
          <MarFileExplorerTile
            v-for="item in group.items"
            :key="item.id"
            :item="item"
            :icon="iconName(item)"
            :selected="isSelected(item.id)"
            :selectable="selectable"
            :touch="mobile"
            :show-tags="showTags"
            :presence="presenceFor(item.id)"
            :renaming="renamingId === item.id"
            :dragging="draggingId === item.id"
            :drop-target="dropTargetId === item.id"
            :thumb-src="thumbSrc(item)"
            :thumb-loaded="thumbLoaded.has(item.id)"
            :thumb-failed="thumbFailed.has(item.id)"
            @open="onOpen($event, item)"
            @pick="onPick(item, $event)"
            @more="onMore($event, item)"
            @enter="onEnter($event, item)"
            @leave="emit('hoverend')"
            @dragstart="onDragStart($event, item)"
            @dragover="onDragOver($event, item)"
            @dragleave="onDragLeave(item)"
            @drop="onDrop($event, item)"
            @dragend="resetDrag"
            @thumbload="onThumbLoad(item)"
            @thumberror="onThumbError(item)"
            @rename="commitRename(item, $event)"
            @renamecancel="cancelRename"
          />
        </div>
      </MarListGroup>
    </template>
  </div>
</template>

<style scoped>
.mar-file-explorer {
  --mar-file-cell-size: 10em;
  font-size: 0.75em;
  color: var(--mar-text-color);
  user-select: none;
}

.mar-file-explorer-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(var(--mar-file-cell-size), 1fr));
  gap: 0.6667em;
  padding: 1.3333em;
}

.mar-file-explorer-group {
  padding: 0.8333em 1.3333em;
}

.mar-file-explorer-grid-grouped {
  padding: 0.6667em 0 0.3333em;
}

.mar-file-explorer-grid-add {
  padding-bottom: 0;
}

.mar-file-explorer-add {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5em;
  border-radius: var(--mar-content-border-radius);
  padding: 1em 0.6667em;
  border: 2px solid transparent;
  cursor: pointer;
  user-select: none;
  background: transparent;
  color: inherit;
  font: inherit;
}

.mar-file-explorer-skeleton {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.4167em;
}

.mar-file-explorer-skeleton-area {
  width: calc(var(--mar-file-cell-size) * 8 / 15);
  height: calc(var(--mar-file-cell-size) * 8 / 15);
  border-radius: 0.8333em;
}

.mar-file-explorer-skeleton-label {
  height: 0.6667em;
  width: 70%;
}

.mar-file-explorer-skeleton:nth-child(even) .mar-file-explorer-skeleton-label {
  width: 50%;
}

.mar-file-explorer-add-area {
  position: relative;
  box-sizing: border-box;
  display: flex;
  align-items: center;
  justify-content: center;
  width: calc(var(--mar-file-cell-size) * 8 / 15);
  height: calc(var(--mar-file-cell-size) * 8 / 15);
  border: 2px dashed var(--mar-surface-300);
  border-radius: 0.8333em;
  color: var(--mar-surface-500);
}

.mar-file-explorer-add:hover .mar-file-explorer-add-area {
  border-color: var(--mar-primary-color);
  color: var(--mar-primary-color);
}

.mar-file-explorer-add-label {
  display: -webkit-box;
  overflow: hidden;
  max-width: 100%;
  color: var(--mar-surface-800);
  font-weight: 500;
  line-height: 1.3;
  text-align: center;
  word-break: break-word;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
}

.mar-file-explorer-add:focus-visible {
  outline: 2px solid var(--mar-primary-color);
  outline-offset: 0.1667em;
}

.mar-file-explorer-add-icon {
  width: 37.5%;
  height: 37.5%;
}

</style>
