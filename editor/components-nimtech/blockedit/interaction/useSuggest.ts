import { onBeforeUnmount, reactive, type Ref } from "vue";
import { closeModal, openModal } from "@/composables/useModals";
import MarBlockEditorSlashMenu from "@/components/MarBlockEditorSlashMenu";
import type { BlockEngine } from "../engine/BlockEngine";
import type { MentionItem, SlashCommand } from "../engine/config";
import { textBeforeCaret } from "../selection/domMap";
import { deleteInlineRange, insertInlineAt } from "../ops/text";
import { refOp, textOp } from "../model/delta";
import { getBlock } from "../model/tree";

const NO_SUGGEST_TYPES = new Set(["codeBlock"]);

const SUGGEST_ID = "be-suggest";

interface SuggestItem {
  title: string;
  icon: string;
  description?: string;
}

export const useSuggest = (
  engine: BlockEngine,
  rootRef: Ref<HTMLElement | null>,
) => {
  const state = reactive<{
    items: SuggestItem[];
    selectedIndex: number;
    loading: boolean;
  }>({ items: [], selectedIndex: 0, loading: false });

  let open = false;
  let mode: "/" | "@" = "/";
  let blockId = "";
  let triggerStart = 0;
  let queryLen = 0;
  let mentionResults: MentionItem[] = [];
  let slashResults: SlashCommand[] = [];

  const caretRect = (): DOMRect | null => {
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount) return null;
    const r = sel.getRangeAt(0).getBoundingClientRect();
    if (r.width === 0 && r.height === 0) return null;
    return r;
  };

  const close = (): void => {
    if (!open) return;
    open = false;
    closeModal(SUGGEST_ID);
  };

  const openMenu = (): void => {
    if (open) return;
    open = true;
    void openModal({
      id: SUGGEST_ID,
      kind: "dropdown",
      component: MarBlockEditorSlashMenu,
      anchor: { target: () => caretRect() },
      placement: { side: "bottom", align: "start", offset: 4 },
      backdrop: "invisible",
      dismissOnEscape: true,
      props: { state },
      on: {
        select: (i: unknown) => choose(i as number),
        "update:selectedIndex": (i: unknown) => {
          state.selectedIndex = i as number;
        },
      },
    });
  };

  const choose = (index: number): void => {
    const from = triggerStart;
    const to = triggerStart + 1 + queryLen;
    const id = blockId;
    if (mode === "/") {
      const cmd = slashResults[index];
      close();
      engine.dispatch((doc) => deleteInlineRange(doc, id, from, to));
      cmd?.run({ engine, blockId: id });
      return;
    }
    const mention = mentionResults[index];
    close();
    if (!mention) return;
    engine.dispatch((doc) => {
      const del = deleteInlineRange(doc, id, from, to);
      return insertInlineAt(del.doc, id, from, [
        refOp("mention", {
          id: mention.id,
          label: mention.label,
          icon: mention.icon ?? "",
          type: mention.type ?? "",
          href: mention.href ?? "",
          preview: mention.preview ?? "",
          image: mention.image ?? "",
        }),
        textOp(" "),
      ]);
    });
  };

  const fillSlash = (query: string): void => {
    const q = query.toLowerCase().trim();
    const all = engine.config.slashCommands ?? [];
    const filtered = q
      ? all.filter(
          (c) =>
            c.title.toLowerCase().includes(q) ||
            (c.keywords ?? []).some((k) => k.toLowerCase().includes(q)),
        )
      : all;
    slashResults = filtered;
    state.items = filtered.map((c) => ({
      title: c.title,
      icon: c.icon ?? "",
      description: c.description,
    }));
    state.selectedIndex = 0;
  };

  const runMention = async (query: string): Promise<void> => {
    if (!engine.config.searchMentions) {
      close();
      return;
    }
    state.loading = true;
    openMenu();
    mentionResults = await engine.config.searchMentions(query);
    state.items = mentionResults.map((m) => ({
      title: m.label,
      icon: m.icon ?? "",
      description: m.preview,
    }));
    state.selectedIndex = 0;
    state.loading = false;
  };

  const onInput = (): void => {
    const root = rootRef.value;
    if (!root) return;
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount) {
      close();
      return;
    }
    const anchorNode = sel.anchorNode;
    const host =
      anchorNode instanceof Element ? anchorNode : anchorNode?.parentElement;
    const el = host?.closest("[data-block-id]") as HTMLElement | null;
    if (!el || !root.contains(el)) {
      close();
      return;
    }
    const focusedId = el.getAttribute("data-block-id") ?? "";
    const focusedBlock = getBlock(engine.doc.value, focusedId);
    if (focusedBlock && NO_SUGGEST_TYPES.has(focusedBlock.kind)) {
      close();
      return;
    }
    const before = textBeforeCaret(el);
    const match = /(^|\s)([/@])(\S*)$/.exec(before);
    if (!match) {
      close();
      return;
    }
    mode = match[2] as "/" | "@";
    const query = match[3] ?? "";
    blockId = el.getAttribute("data-block-id") ?? "";
    queryLen = query.length;
    triggerStart = before.length - query.length - 1;
    if (mode === "/") {
      fillSlash(query);
      openMenu();
    } else {
      void runMention(query);
    }
  };

  const wrap = (n: number): number => {
    const len = Math.max(1, state.items.length);
    return ((n % len) + len) % len;
  };

  const onKeydown = (e: KeyboardEvent): void => {
    if (!open) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      state.selectedIndex = wrap(state.selectedIndex + 1);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      state.selectedIndex = wrap(state.selectedIndex - 1);
    } else if (e.key === "Enter") {
      e.preventDefault();
      choose(state.selectedIndex);
    } else if (e.key === "Escape") {
      e.preventDefault();
      close();
    }
  };

  const bind = (): void => {
    const root = rootRef.value;
    if (!root) return;
    root.addEventListener("input", onInput);
    root.addEventListener("keydown", onKeydown, true);
  };

  onBeforeUnmount(() => {
    const root = rootRef.value;
    root?.removeEventListener("input", onInput);
    root?.removeEventListener("keydown", onKeydown, true);
    close();
  });

  return { bind, close };
};
