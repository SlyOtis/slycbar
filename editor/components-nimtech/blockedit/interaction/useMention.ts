import { onBeforeUnmount, type Ref } from "vue";
import { closeModal, openModal, notify, type ModalAnchorRect } from "@/composables/useModals";
import MarMentionCard from "@/components/MarMentionCard";
import MarBlockMore from "@/components/MarBlockMore";
import { deleteInlineRange, insertInlineAt } from "../ops/text";
import { refOp } from "../model/delta";
import { mentionDeclared } from "../serialize/htmlSerialize";
import { offsetAtNode, offsetBeforeElement } from "../selection/domMap";
import type { BlockEngine } from "../engine/BlockEngine";

const CARD_ID = "be-mention-card";
const MORE_ID = "be-mention-more";

const caretRangeAt = (x: number, y: number): Range | null => {
  const d = document as Document & {
    caretRangeFromPoint?: (x: number, y: number) => Range | null;
    caretPositionFromPoint?: (
      x: number,
      y: number,
    ) => { offsetNode: Node; offset: number } | null;
  };
  if (d.caretRangeFromPoint) return d.caretRangeFromPoint(x, y);
  const pos = d.caretPositionFromPoint?.(x, y);
  if (!pos) return null;
  const range = document.createRange();
  range.setStart(pos.offsetNode, pos.offset);
  range.collapse(true);
  return range;
};

interface MentionData {
  id: string;
  type: string;
  href: string;
  label: string;
  icon: string;
  preview: string;
  image: string;
}

export const useMention = (engine: BlockEngine, rootRef: Ref<HTMLElement | null>) => {
  let closeTimer: number | null = null;
  let cardEl: HTMLElement | null = null;
  let cardId = "";
  let cardSeq = 0;
  let moreOpen = false;

  const elementAnchor = (el: HTMLElement, e: MouseEvent): ModalAnchorRect => {
    const inner = (e.target as HTMLElement | null)?.closest?.("img") ?? null;
    const target = inner && el.contains(inner) ? inner : el;
    const rects = Array.from(target.getClientRects());
    const hit = rects.find((r) => e.clientY >= r.top && e.clientY <= r.bottom);
    const rect = hit ?? target.getBoundingClientRect();
    if (rect.height > 48) {
      return {
        left: e.clientX,
        top: e.clientY,
        right: e.clientX,
        bottom: e.clientY,
        width: 0,
        height: 0,
      };
    }
    return {
      left: e.clientX,
      top: rect.top,
      right: e.clientX,
      bottom: rect.bottom,
      width: 0,
      height: rect.height,
    };
  };

  const mentionAt = (e: Event): HTMLElement | null =>
    (e.target as HTMLElement | null)?.closest?.('[data-type="mention"]') ?? null;

  const imageAt = (e: Event): HTMLElement | null => {
    const img = (e.target as HTMLElement | null)?.closest?.('img[data-type="inline-image"]');
    if (!(img instanceof HTMLElement)) return null;
    if (!img.closest(".mar-be-text")) return null;
    return img;
  };

  const linkAt = (e: Event): HTMLElement | null => {
    const a = (e.target as HTMLElement | null)?.closest?.("a");
    if (!a) return null;
    if (a.closest('[data-type="mention"]')) return null;
    if (!a.closest(".mar-be-text")) return null;
    if (a.querySelector('img[data-type="inline-image"]')) return null;
    const href = a.getAttribute("href") ?? "";
    if (!href || href.startsWith("#")) return null;
    return a;
  };

  const dataOf = (el: HTMLElement): MentionData => ({
    id: el.getAttribute("data-id") ?? "",
    type: el.getAttribute("data-mtype") ?? "",
    href: el.getAttribute("data-href") ?? "",
    label: el.getAttribute("data-label") ?? "",
    icon: el.getAttribute("data-icon") || "at",
    preview: el.getAttribute("data-preview") ?? "",
    image: el.getAttribute("data-image") ?? "",
  });

  const close = (): void => {
    if (moreOpen) return;
    if (cardId) closeModal(cardId);
    cardId = "";
    cardEl = null;
  };

  const cancelClose = (): void => {
    if (closeTimer !== null) {
      clearTimeout(closeTimer);
      closeTimer = null;
    }
  };

  const scheduleClose = (): void => {
    cancelClose();
    if (moreOpen) return;
    closeTimer = window.setTimeout(close, 140);
  };

  const startDrag = (ev: PointerEvent, d: MentionData): void => {
    const source = cardEl;
    if (!source) return;
    const srcBlockEl = source.closest("[data-block-id]") as HTMLElement | null;
    const srcId = srcBlockEl?.getAttribute("data-block-id");
    if (!srcBlockEl || !srcId) return;
    const srcOffset = offsetBeforeElement(srcBlockEl, source);
    moreOpen = false;
    close();
    const atom = refOp("mention", {
      id: d.id,
      label: d.label,
      icon: d.icon,
      type: d.type,
      href: d.href,
      preview: d.preview,
      image: d.image,
    });
    const onMove = (e: PointerEvent): void => {
      const range = caretRangeAt(e.clientX, e.clientY);
      if (!range) return;
      const sel = window.getSelection();
      sel?.removeAllRanges();
      sel?.addRange(range);
    };
    const onUp = (e: PointerEvent): void => {
      document.removeEventListener("pointermove", onMove);
      document.removeEventListener("pointerup", onUp);
      const range = caretRangeAt(e.clientX, e.clientY);
      if (!range) return;
      const node =
        range.startContainer.nodeType === 1
          ? (range.startContainer as Element)
          : range.startContainer.parentElement;
      const tgtBlockEl = node?.closest("[data-block-id]") as HTMLElement | null;
      const tgtId = tgtBlockEl?.getAttribute("data-block-id");
      if (!tgtBlockEl || !tgtId) return;
      const tgtOffset = offsetAtNode(tgtBlockEl, range.startContainer, range.startOffset);
      engine.dispatch((doc) => {
        const del = deleteInlineRange(doc, srcId, srcOffset, srcOffset + 1);
        let to = tgtOffset;
        if (tgtId === srcId && to > srcOffset) to -= 1;
        return insertInlineAt(del.doc, tgtId, to, [atom]);
      });
    };
    ev.preventDefault();
    document.addEventListener("pointermove", onMove);
    document.addEventListener("pointerup", onUp);
  };

  const navigate = (d: MentionData): void => {
    if (!d.href) return;
    if (d.id) {
      engine.config.onOpenMention?.({ id: d.id, type: d.type, href: d.href });
    } else if (typeof window !== "undefined") {
      window.open(d.href, "_blank", "noopener");
    }
  };

  const onClick = (e: MouseEvent): void => {
    const el = mentionAt(e);
    if (!el) return;
    close();
    const data = dataOf(el);
    if (!mentionDeclared(data.type, engine.config.mentionTypes)) return;
    navigate(data);
  };

  const openLink = (el: HTMLElement, anchorRect: ModalAnchorRect): void => {
    const href = el.getAttribute("href") ?? el.closest("a")?.getAttribute("href") ?? "";
    const base: MentionData = {
      id: "",
      type: "Link",
      href,
      label: href,
      icon: "link",
      preview: "",
      image: "",
    };
    open(el, base, false, anchorRect);
    const resolve = engine.config.resolveLinkPreview;
    if (!resolve) return;
    void resolve(href).then((p) => {
      if (cardEl !== el) return;
      open(el, {
        ...base,
        label: String(p.title ?? href),
        preview: String(p.description ?? ""),
        image: String(p.imageUrl ?? ""),
        type: String(p.siteName ?? p.provider ?? "Link"),
      }, false, anchorRect);
    });
  };

  const open = (el: HTMLElement, d: MentionData, draggable: boolean, anchorRect: ModalAnchorRect): void => {
    if (cardEl !== el) {
      if (cardId) closeModal(cardId);
      cardSeq += 1;
      cardId = `${CARD_ID}-${cardSeq}`;
    }
    cardEl = el;
    void openModal({
      id: cardId,
      kind: "popup",
      component: MarMentionCard,
      anchor: { target: anchorRect },
      placement: { side: "top", align: "start", offset: 8 },
      backdrop: "none",
      props: {
        image: d.image,
        title: d.label,
        description: d.preview,
        type: d.type,
        icon: d.icon,
        clickable: !!d.href,
        onEnter: cancelClose,
        onLeave: scheduleClose,
        onNavigate: () => {
          close();
          navigate(d);
        },
        onMore: (anchor: HTMLElement) => {
          moreOpen = true;
          cancelClose();
          void openModal({
            id: MORE_ID,
            kind: "dropdown",
            component: MarBlockMore,
            anchor: { target: anchor },
            placement: { side: "bottom", align: "end", offset: 4 },
            backdrop: "invisible",
            props: {
              options: [
                { title: "Open", icon: "open-in-new", description: d.href, run: () => navigate(d) },
                {
                  title: "Copy link",
                  icon: "copy",
                  description: "Copy URL to clipboard",
                  run: () => {
                    if (d.href && typeof navigator !== "undefined") {
                      void navigator.clipboard?.writeText(d.href);
                      notify("success", "Copied", d.href, 2000);
                    }
                  },
                },
              ],
            },
            on: {
              close: () => {
                closeModal(MORE_ID);
                moreOpen = false;
                scheduleClose();
              },
            },
          });
        },
        onDragStart: draggable ? (ev: PointerEvent) => startDrag(ev, d) : undefined,
      },
    });
  };

  const onOver = (e: MouseEvent): void => {
    const mention = mentionAt(e);
    if (mention) {
      const d = dataOf(mention);
      if (!d.preview && !d.image) return;
      cancelClose();
      if (mention === cardEl) return;
      const inert = !mentionDeclared(d.type, engine.config.mentionTypes);
      open(
        mention,
        inert ? { ...d, href: "" } : d,
        engine.editable.value,
        elementAnchor(mention, e),
      );
      return;
    }
    const image = imageAt(e);
    if (image) {
      cancelClose();
      if (image === cardEl) return;
      openLink(image, elementAnchor(image, e));
      return;
    }
    const link = linkAt(e);
    if (link) {
      cancelClose();
      if (link === cardEl) return;
      openLink(link, elementAnchor(link, e));
    }
  };

  const onOut = (e: MouseEvent): void => {
    if (!mentionAt(e) && !linkAt(e) && !imageAt(e)) return;
    scheduleClose();
  };

  const bind = (): void => {
    const root = rootRef.value;
    if (!root) return;
    root.addEventListener("click", onClick);
    root.addEventListener("mouseover", onOver);
    root.addEventListener("mouseout", onOut);
  };

  onBeforeUnmount(() => {
    const root = rootRef.value;
    root?.removeEventListener("click", onClick);
    root?.removeEventListener("mouseover", onOver);
    root?.removeEventListener("mouseout", onOut);
    cancelClose();
    if (cardId) closeModal(cardId);
  });

  return { bind };
};
