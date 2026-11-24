<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from "vue";
import { NodeViewWrapper } from "@/blockedit/render/views/nodeViewBridge.ts";
import MarIcon from "../MarIcon";
import MarBlockEditorSlashMenu from "../MarBlockEditorSlashMenu";
import { closeModal, openModal } from "@/composables/useModals.ts";
import type { IconType } from "@/types/icon.types";

interface PageRef {
  assetId: string;
  label?: string;
  icon?: string;
}

const props = defineProps<{
  /** Editor node whose options carry the assetId, label, and icon of the linked page. */
  node: {
    options: {
      assetId?: string;
      label?: string;
      icon?: IconType;
    };
    textContent?: string;
  };
  /** Editor context whose isEditable flag gates the title input. */
  editor: { isEditable: boolean };
  /** Draws the selection border on the row. */
  selected: boolean;
  /** Editor callback persisting attr changes onto the node. */
  updateAttributes: (attrs: Record<string, unknown>) => void;
  /** Extension options wiring page open, rename, search, and creation to the consumer. */
  extension: {
    options: {
      onOpen: (assetId: string) => void;
      onRename: (assetId: string, label: string) => void;
      searchPages?: (query: string) => Promise<PageRef[]>;
      createPageBlock?: (
        name: string,
      ) => Promise<PageRef | null> | PageRef | null;
    };
  };
}>();

const editable = computed(() => props.editor?.isEditable ?? true);

const assetId = computed(() => props.node.options.assetId ?? "");

const label = computed(() => props.node.options.label ?? "");

const icon = computed<IconType>(() => props.node.options.icon ?? "file");

const linked = computed(() => !!assetId.value);

const inputEl = ref<HTMLInputElement | null>(null);

const MENU_ID =
  typeof crypto !== "undefined" && crypto.randomUUID
    ? `mar-page-block-${crypto.randomUUID()}`
    : `mar-page-block-${Math.floor(performance.now())}`;

const menuState = reactive<{
  items: { title: string; icon: string; description?: string }[];
  selectedIndex: number;
  loading: boolean;
}>({ items: [], selectedIndex: -1, loading: false });

let results: PageRef[] = [];
let menuOpen = false;
let token = 0;

const openMenu = (): void => {
  if (menuOpen) return;
  menuOpen = true;
  void openModal({
    id: MENU_ID,
    kind: "dropdown",
    component: MarBlockEditorSlashMenu,
    anchor: { target: () => inputEl.value },
    placement: {
      side: "bottom",
      align: "start",
      offset: 6,
      matchAnchorMinWidth: true,
    },
    backdrop: "invisible",
    dismissOnEscape: true,
    props: { state: menuState },
    on: {
      select: (i: unknown) => pick(i as number),
      "update:selectedIndex": (i: unknown) => {
        menuState.selectedIndex = i as number;
      },
    },
  });
};

const closeMenu = (): void => {
  if (!menuOpen) return;
  menuOpen = false;
  closeModal(MENU_ID);
};

const runSearch = async (query: string): Promise<void> => {
  const search = props.extension.options.searchPages;
  if (!search) {
    results = [];
    return;
  }
  const current = ++token;
  menuState.loading = true;
  openMenu();
  const found = await search(query);
  if (current !== token) return;
  results = found;
  menuState.items = found.map((p) => ({
    title: p.label || "Untitled page",
    icon: p.icon || "file",
    description: "",
  }));
  menuState.selectedIndex = -1;
  menuState.loading = false;
  if (!found.length) closeMenu();
};

const onInput = (e: Event): void => {
  const value = (e.target as HTMLInputElement).value;
  props.updateAttributes({ label: value });
  if (linked.value) {
    props.extension.options.onRename(assetId.value, value);
    return;
  }
  void runSearch(value.trim());
};

const pick = (index: number): void => {
  const ref = results[index];
  if (!ref) return;
  closeMenu();
  props.updateAttributes({
    assetId: ref.assetId,
    label: ref.label ?? "",
    icon: ref.icon ?? "file",
  });
};

const createNew = async (): Promise<void> => {
  const title = (inputEl.value?.value ?? label.value).trim();
  closeMenu();
  if (!title) return;
  const create = props.extension.options.createPageBlock;
  if (!create) return;
  const ref = await Promise.resolve(create(title));
  if (!ref) return;
  props.updateAttributes({
    assetId: ref.assetId,
    label: ref.label ?? title,
    icon: ref.icon ?? "file",
  });
  props.extension.options.onOpen(ref.assetId);
};

const move = (delta: number): void => {
  const len = menuState.items.length;
  if (!len) return;
  const i = menuState.selectedIndex;
  menuState.selectedIndex =
    i < 0 ? (delta > 0 ? 0 : len - 1) : (i + delta + len) % len;
};

const onKeydown = (e: KeyboardEvent): void => {
  if (menuOpen && menuState.items.length) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      move(1);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      move(-1);
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (menuState.selectedIndex >= 0) pick(menuState.selectedIndex);
      else void createNew();
    } else if (e.key === "Escape") {
      e.preventDefault();
      closeMenu();
    }
    return;
  }
  if (e.key === "Enter") {
    e.preventDefault();
    void createNew();
  } else if (e.key === "Escape") {
    closeMenu();
  }
};

const open = (): void => {
  if (assetId.value) props.extension.options.onOpen(assetId.value);
};

onMounted(() => {
  if (editable.value && !linked.value) inputEl.value?.focus();
});

watch(linked, (isLinked) => {
  if (!isLinked && editable.value) {
    void nextTick(() => inputEl.value?.focus());
  }
});

onBeforeUnmount(() => closeMenu());
</script>

<template>
  <NodeViewWrapper
    :class="['mar-subpage', { 'mar-subpage-selected': selected }]"
    contenteditable="false"
  >
    <div class="mar-subpage-row">
      <span class="mar-subpage-icon" @click="open">
        <MarIcon :icon="icon" />
      </span>
      <input
        v-if="editable && !linked"
        ref="inputEl"
        class="mar-subpage-input"
        :value="label"
        placeholder="Untitled page"
        @input="onInput"
        @keydown="onKeydown"
      />
      <span v-else class="mar-subpage-label" @click="open">
        {{ label || "Untitled page" }}
      </span>
      <span v-if="linked" class="mar-subpage-chevron" @click="open">
        <MarIcon icon="chevron-right" />
      </span>
    </div>
  </NodeViewWrapper>
</template>

<style scoped>
.mar-subpage {
  margin: 0.25em 0;
}

.mar-subpage-row {
  display: flex;
  align-items: center;
  gap: 0.5em;
  width: 100%;
  padding: 0.375em 0.5em;
  border: 1px solid transparent;
  border-radius: 6px;
  transition: background 0.15s cubic-bezier(0.4, 0, 0.2, 1),
    border-color 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}

.mar-subpage-row:hover {
  background: var(--mar-surface-100);
  border-color: var(--mar-content-border-color);
}

.mar-subpage-selected .mar-subpage-row {
  border-color: var(--mar-surface-400);
}

.mar-subpage-icon {
  color: var(--mar-surface-500);
  flex-shrink: 0;
  display: inline-flex;
  cursor: pointer;
}

.mar-subpage-label {
  flex: 1;
  min-width: 0;
  font-weight: 500;
  font-size: 0.875em;
  color: var(--mar-text-color);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  text-decoration: underline;
  text-decoration-color: var(--mar-surface-300);
  text-underline-offset: 0.2143em;
  cursor: pointer;
}

.mar-subpage-input {
  flex: 1;
  min-width: 0;
  border: none;
  background: transparent;
  outline: none;
  font-family: inherit;
  font-size: 0.875em;
  font-weight: 500;
  color: var(--mar-text-color);
  padding: 0;
}

.mar-subpage-chevron {
  color: var(--mar-surface-400);
  flex-shrink: 0;
  display: inline-flex;
  cursor: pointer;
}
</style>
