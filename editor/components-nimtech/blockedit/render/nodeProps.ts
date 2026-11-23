import type { BlockId, MarBlock } from "../model/types";
import type { BlockEngine } from "../engine/BlockEngine";
import { specByType } from "../serialize/domSpec";

export const blockTag = (block: MarBlock): string => {
  if (block.kind === "heading") return `h${Number(block.options.level) || 1}`;
  return specByType.get(block.kind)?.tag ?? "div";
};

export const isBlockSelected = (engine: BlockEngine, id: BlockId): boolean => {
  const selection = engine.selection.value;
  if (!selection) return false;
  if (selection.kind === "node") return selection.blockId === id;
  if (selection.kind === "blocks") return selection.ids.includes(id);
  return false;
};

export const blockClass = (engine: BlockEngine, id: BlockId): string =>
  isBlockSelected(engine, id)
    ? "mar-block-edit-block mar-block-selected"
    : "mar-block-edit-block";

export const blockAttrs = (
  block: MarBlock,
  className: string,
): Record<string, string> => {
  const spec = specByType.get(block.kind);
  const out: Record<string, string> = {
    "data-block-id": block.id,
    class: className,
  };
  if (!block.inherits) {
    out["data-ff"] = block.fontFamily;
    out["data-fs"] = block.fontSize;
    out["data-lh"] = block.lineHeight;
  }
  if (!spec) return out;
  if (spec.dataType) out["data-type"] = spec.dataType;
  for (const attr of spec.attrs) {
    const rendered = attr.render(block.options[attr.name]);
    if (rendered) Object.assign(out, rendered);
  }
  return out;
};

export interface HeadingNumbering {
  enabled: boolean;
  startLevel: number;
  startId: string | null;
}

export const headingMeta = (
  numbering: HeadingNumbering,
  blocks: MarBlock[],
): { hidden: Set<string>; numbers: Map<string, string> } => {
  const { enabled, startLevel, startId } = numbering;
  const counters = [0, 0, 0, 0, 0, 0, 0];
  let hidingFromLevel: number | null = null;
  let active = startId === null;
  const hidden = new Set<string>();
  const numbers = new Map<string, string>();
  for (const block of blocks) {
    if (block.kind === "heading") {
      const level = Number(block.options.level ?? 1);
      if (hidingFromLevel !== null && level <= hidingFromLevel) hidingFromLevel = null;
      const isHidden = hidingFromLevel !== null;
      if (isHidden) hidden.add(block.id);
      else if (block.options.collapsed) hidingFromLevel = level;
      if (block.id === startId) active = true;
      if (enabled && active && !isHidden) {
        counters[level] = (counters[level] ?? 0) + 1;
        for (let l = level + 1; l <= 6; l += 1) counters[l] = 0;
        if (level >= startLevel) {
          const parts: number[] = [];
          for (let l = startLevel; l <= level; l += 1) parts.push(counters[l] ?? 0);
          numbers.set(block.id, `${parts.join(".")}. `);
        }
      }
    } else if (hidingFromLevel !== null) {
      hidden.add(block.id);
    }
  }
  return { hidden, numbers };
};

export const READONLY_LINK_TYPES = new Set([
  "audio",
  "video",
  "pdf",
  "file",
  "bookmark",
  "linkPreview",
  "embed",
  "pageBlock",
]);

export const readonlyMeta = (
  block: MarBlock,
): { icon: string; label: string; href: string } => {
  const s = (k: string): string => String(block.options[k] ?? "");
  switch (block.kind) {
    case "audio":
      return { icon: "music", label: s("name") || "Audio", href: s("src") };
    case "video":
      return { icon: "video", label: s("name") || "Video", href: s("src") };
    case "pdf":
      return { icon: "file", label: s("name") || "PDF", href: s("src") };
    case "file":
      return { icon: "file", label: s("name") || "File", href: s("url") };
    case "bookmark":
    case "linkPreview":
      return { icon: "globe", label: s("url") || "Link", href: s("url") };
    case "embed":
      return { icon: "code", label: s("url") || "Embed", href: s("url") };
    case "pageBlock":
      return { icon: s("icon") || "file", label: s("label") || "Page", href: "" };
    default:
      return { icon: "file", label: "", href: "" };
  }
};
