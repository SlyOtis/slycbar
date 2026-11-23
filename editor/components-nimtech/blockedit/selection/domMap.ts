const isFiller = (el: HTMLElement): boolean =>
  el.tagName === "BR" && el.hasAttribute("data-filler");

const measureLength = (node: Node): number => {
  let total = 0;
  node.childNodes.forEach((child) => {
    if (child.nodeType === 3) {
      total += child.textContent?.length ?? 0;
    } else if (child.nodeType === 1) {
      const el = child as HTMLElement;
      if (isFiller(el)) return;
      if (el.tagName === "BR") total += 1;
      else if (el.getAttribute("data-type") === "mention") total += 1;
      else total += measureLength(el);
    }
  });
  return total;
};

const lengthBefore = (
  blockEl: HTMLElement,
  container: Node,
  offset: number,
): number => {
  const pre = document.createRange();
  pre.selectNodeContents(blockEl);
  pre.setEnd(container, offset);
  return measureLength(pre.cloneContents());
};

export const selectionRange = (
  blockEl: HTMLElement,
): { from: number; to: number } | null => {
  const sel = window.getSelection();
  if (!sel || sel.rangeCount === 0) return null;
  const range = sel.getRangeAt(0);
  if (
    !blockEl.contains(range.startContainer) ||
    !blockEl.contains(range.endContainer)
  )
    return null;
  const from = lengthBefore(blockEl, range.startContainer, range.startOffset);
  const to = lengthBefore(blockEl, range.endContainer, range.endOffset);
  if (from === to) return null;
  return { from: Math.min(from, to), to: Math.max(from, to) };
};

export const offsetAtNode = (
  blockEl: HTMLElement,
  container: Node,
  offset: number,
): number => lengthBefore(blockEl, container, offset);

export const offsetBeforeElement = (
  blockEl: HTMLElement,
  el: Element,
): number => {
  const pre = document.createRange();
  pre.selectNodeContents(blockEl);
  pre.setEndBefore(el);
  return measureLength(pre.cloneContents());
};

export const textBeforeCaret = (blockEl: HTMLElement): string => {
  const sel = window.getSelection();
  if (!sel || sel.rangeCount === 0) return "";
  const range = sel.getRangeAt(0);
  if (!blockEl.contains(range.endContainer)) return "";
  const pre = document.createRange();
  pre.selectNodeContents(blockEl);
  pre.setEnd(range.endContainer, range.endOffset);
  return pre.toString();
};

export const caretOffset = (blockEl: HTMLElement): number | null => {
  const sel = window.getSelection();
  if (!sel || sel.rangeCount === 0) return null;
  const range = sel.getRangeAt(0);
  if (!blockEl.contains(range.endContainer)) return null;
  const pre = document.createRange();
  pre.selectNodeContents(blockEl);
  pre.setEnd(range.endContainer, range.endOffset);
  return measureLength(pre.cloneContents());
};

export const locateOffset = (
  blockEl: HTMLElement,
  offset: number,
): { node: Node; offset: number } => {
  let remaining = offset;
  const walk = (node: Node): { node: Node; offset: number } | null => {
    for (const child of Array.from(node.childNodes)) {
      if (child.nodeType === 3) {
        const len = child.textContent?.length ?? 0;
        if (remaining <= len) return { node: child, offset: remaining };
        remaining -= len;
      } else if (child.nodeType === 1) {
        const el = child as HTMLElement;
        if (el.tagName === "BR" || el.getAttribute("data-type") === "mention") {
          if (remaining === 0) {
            const idx = Array.prototype.indexOf.call(node.childNodes, el);
            return { node, offset: idx };
          }
          if (!isFiller(el)) remaining -= 1;
        } else {
          const found = walk(el);
          if (found) return found;
        }
      }
    }
    return null;
  };
  return walk(blockEl) ?? { node: blockEl, offset: blockEl.childNodes.length };
};

export const setCaret = (blockEl: HTMLElement, offset: number): void => {
  const { node, offset: nodeOffset } = locateOffset(blockEl, offset);
  const range = document.createRange();
  range.setStart(node, Math.min(nodeOffset, (node.textContent?.length ?? nodeOffset)));
  range.collapse(true);
  const sel = window.getSelection();
  if (!sel) return;
  sel.removeAllRanges();
  sel.addRange(range);
};

export const setRange = (
  blockEl: HTMLElement,
  from: number,
  to: number,
): void => {
  const start = locateOffset(blockEl, from);
  const end = locateOffset(blockEl, to);
  const range = document.createRange();
  range.setStart(start.node, Math.min(start.offset, start.node.textContent?.length ?? start.offset));
  range.setEnd(end.node, Math.min(end.offset, end.node.textContent?.length ?? end.offset));
  const sel = window.getSelection();
  if (!sel) return;
  sel.removeAllRanges();
  sel.addRange(range);
};

export const clearNativeSelection = (): void => {
  window.getSelection()?.removeAllRanges();
};

const focusRect = (): DOMRect | null => {
  const sel = window.getSelection();
  if (!sel || !sel.focusNode) return null;
  const range = document.createRange();
  range.setStart(sel.focusNode, sel.focusOffset);
  range.collapse(true);
  return range.getBoundingClientRect();
};

export const caretAtEdge = (blockEl: HTMLElement, dir: -1 | 1): boolean => {
  const cr = focusRect();
  if (!cr) return false;
  const br = blockEl.getBoundingClientRect();
  const lineHeight = parseFloat(getComputedStyle(blockEl).lineHeight) || 20;
  if (cr.height === 0) return dir === 1 || caretOffset(blockEl) === 0;
  if (dir === -1) return cr.top - br.top < lineHeight * 0.75;
  return br.bottom - cr.bottom < lineHeight * 0.75;
};
