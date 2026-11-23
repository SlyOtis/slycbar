import type { BlockEngine } from "../engine/BlockEngine";
import type {
  BlockId,
  EditMode,
  FontFamily,
  FontSize,
  LineHeight,
  MarBlock,
  MarDocument,
  ReadMode,
} from "../model/types";
import { ancestorContentLocked, childBlocks, getBlock, insertBlock, isBlockLocked, isContentLocked, locate, putBlocks, removeBlock, sharedText, updateBlock, type SharedText } from "../model/tree";
import { contentShapeOf, getMediaOptions, makeBlock } from "../model/schema";
import type { MarMediaKind } from "../../types/media.types";
import { deltaText } from "../model/delta";
import { setBlockKind } from "../ops/blocks";
import { setListType } from "../ops/lists";
import { useRecorderSession } from "@/composables/useRecorder";
import { getCoordinates } from "@/components/MarMap/geocode";
import { openModal, type ModalAnchorRect } from "@/composables/useModals";
import type { MarDateValue } from "@/components/MarDateInput/marDate.types";

export interface BlockOptionChoice {
  title: string;
  icon?: string;
  description?: string;
  active?: boolean;
  run: () => void;
}

export interface BlockOptionInput {
  value: string;
  placeholder?: string;
  action?: string;
  apply: (value: string) => void | Promise<void>;
}

export interface BlockOption {
  title: string;
  icon: string;
  description?: string;
  shared?: boolean;
  run?: (anchor?: ModalAnchorRect) => void;
  choices?: BlockOptionChoice[];
  input?: BlockOptionInput;
  submenu?: boolean;
}

const capitalize = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);
const alignIcon = (a: string): string =>
  a === "center"
    ? "align-center"
    : a === "right"
      ? "align-right"
      : a === "justify"
        ? "arrows-horizontal"
        : "align-left";

const ALIGNS = ["left", "center", "right"];
const paraAligns = ["left", "center", "right", "justify"];
const paraWidths = ["full", "narrow"];
const paraWraps = ["wrap", "balance", "nowrap"];
const lineHeights = ["tight", "normal", "relaxed", "loose"];
const fontSizes = ["sm", "md", "lg", "xl"];
const paraPadTops = ["none", "sm", "md", "lg"];
const OBJECT_FITS = ["cover", "contain", "fill", "none", "scale-down"];
const LANGUAGES = [
  "plaintext", "javascript", "typescript", "python", "go", "rust", "java",
  "c", "cpp", "csharp", "ruby", "php", "html", "css", "scss", "json", "yaml",
  "markdown", "bash", "sql", "graphql", "mermaid",
];
const calloutVariants = ["info", "success", "warn", "danger", "neutral"];
const calloutIcons: Record<string, string> = {
  info: "info",
  success: "circle-check",
  warn: "triangle-alert",
  danger: "circle-error",
  neutral: "bookmark",
};
const TOC_PLACEMENTS = ["inline", "left", "right"];
const TOC_PLACEMENT_META: Record<string, { icon?: string; desc?: string }> = {
  inline: { icon: "list", desc: "In the flow of the page" },
  left: { icon: "sidebar", desc: "Legend on the left side of the page" },
  right: { icon: "sidebar", desc: "Legend on the right side of the page" },
};
const countdownModes = ["stacked", "inline"];
const countdownBackgrounds = [
  "none",
  "surface-50",
  "surface-100",
  "surface-200",
  "surface-900",
  "surface-950",
  "primary-100",
  "primary-500",
  "primary-700",
  "blue-700",
  "green-700",
  "red-700",
  "purple-700",
  "orange-700",
];

const themeColorLabel = (value: string): string => {
  if (value === "none") return "None";
  const [family, step] = value.split("-");
  return `${capitalize(family ?? "")} ${step ?? ""}`.trim();
};
const quoteVariants = ["default", "primary", "muted"];
const quoteSizes = ["sm", "md", "lg"];
const orderedListStyles = ["decimal", "lower-alpha", "lower-roman"];
const audioLayouts = ["large", "full", "card", "slim", "compact", "meta", "mini"];

type ChoiceMeta = Record<string, { icon?: string; desc?: string }>;
const ALIGN_META: ChoiceMeta = {
  left: { icon: "align-left", desc: "Align left" },
  center: { icon: "align-center", desc: "Center" },
  right: { icon: "align-right", desc: "Align right" },
};
const PARA_ALIGN_META: ChoiceMeta = {
  left: { icon: "align-left", desc: "Align left" },
  center: { icon: "align-center", desc: "Center" },
  right: { icon: "align-right", desc: "Align right" },
  justify: { icon: "arrows-horizontal", desc: "Fill the line" },
};
const PARA_WIDTH_META: ChoiceMeta = {
  full: { icon: "full-width", desc: "Full width" },
  narrow: { icon: "shrink", desc: "Reading column" },
};
const PARA_WRAP_META: ChoiceMeta = {
  wrap: { icon: "menu", desc: "Normal wrap" },
  balance: { icon: "menu", desc: "Balanced lines" },
  nowrap: { icon: "arrows-horizontal", desc: "Single line" },
};
const LINE_HEIGHT_META: ChoiceMeta = {
  tight: { icon: "text-height", desc: "Tight" },
  normal: { icon: "text-height", desc: "Normal" },
  relaxed: { icon: "text-height", desc: "Relaxed" },
  loose: { icon: "text-height", desc: "Loose" },
};
const FONT_SIZE_META: ChoiceMeta = {
  sm: { icon: "text-height" },
  md: { icon: "text-height" },
  lg: { icon: "text-height" },
  xl: { icon: "text-height" },
};
const PARA_PT_META: ChoiceMeta = {
  none: { icon: "minus" },
  sm: { icon: "arrow-up" },
  md: { icon: "arrow-up" },
  lg: { icon: "arrow-up" },
};
const fontSizeLabel: Record<string, string> = {
  sm: "Small",
  md: "Default",
  lg: "Large",
  xl: "Extra large",
};
const paraPadLabel: Record<string, string> = {
  none: "None",
  sm: "Small",
  md: "Medium",
  lg: "Large",
};
const FIT_META: ChoiceMeta = {
  cover: { icon: "expand", desc: "Fill, may crop" },
  contain: { icon: "expand", desc: "Fit inside" },
  fill: { icon: "expand", desc: "Stretch to fill" },
  none: { icon: "expand", desc: "Original size" },
  "scale-down": { icon: "expand", desc: "Shrink to fit" },
};
const CALLOUT_META: ChoiceMeta = {
  info: { icon: "info", desc: "Information" },
  success: { icon: "circle-check", desc: "Success" },
  warn: { icon: "triangle-alert", desc: "Warning" },
  danger: { icon: "circle-error", desc: "Error" },
  neutral: { icon: "bookmark", desc: "Neutral" },
};
const COUNTDOWN_MODE_META: ChoiceMeta = {
  stacked: { icon: "menu", desc: "Title above the clock" },
  inline: { icon: "arrows-horizontal", desc: "Title beside the clock" },
};
const COUNTDOWN_BG_META: ChoiceMeta = { none: { icon: "minus", desc: "No background" } };
const QUOTE_VARIANT_META: ChoiceMeta = {
  default: { icon: "palette", desc: "Default" },
  primary: { icon: "palette", desc: "Accent color" },
  muted: { icon: "palette", desc: "Muted" },
};
const QUOTE_SIZE_META: ChoiceMeta = {
  sm: { icon: "text-height", desc: "Small" },
  md: { icon: "text-height", desc: "Medium" },
  lg: { icon: "text-height", desc: "Large" },
};
const ORDERED_META: ChoiceMeta = {
  decimal: { icon: "sort", desc: "1, 2, 3" },
  "lower-alpha": { icon: "sort", desc: "a, b, c" },
  "lower-roman": { icon: "sort", desc: "i, ii, iii" },
};
const AUDIO_META: ChoiceMeta = {
  large: { icon: "music", desc: "Large player" },
  full: { icon: "music", desc: "Full width" },
  card: { icon: "id-card", desc: "Compact card" },
  slim: { icon: "menu", desc: "Single row" },
  compact: { icon: "menu", desc: "Minimal controls" },
  meta: { icon: "info", desc: "Title and time" },
  mini: { icon: "music", desc: "Tiny inline" },
};
const DISPLAY_META: ChoiceMeta = {
  card: { icon: "id-card", desc: "Large preview card" },
  inline: { icon: "menu", desc: "Small inline row" },
};
const editModes = ["open", "lockBlock", "lockContent", "locked"];
const editModeLabel: Record<string, string> = {
  open: "Fully editable",
  lockBlock: "Lock block",
  lockContent: "Lock content",
  locked: "Fully locked",
};
const EDIT_MODE_META: ChoiceMeta = {
  open: { icon: "unlock", desc: "Move, edit and delete freely" },
  lockBlock: { icon: "lock", desc: "Fixed in place, content editable" },
  lockContent: { icon: "lock", desc: "Movable, content read only" },
  locked: { icon: "lock", desc: "Fixed and read only" },
};
const fontFamilies: FontFamily[] = [
  "sans",
  "serif",
  "mono",
  "rounded",
  "inter",
  "source-serif",
  "jetbrains-mono",
  "nunito",
];
const fontFamilyLabel: Record<string, string> = {
  sans: "Sans",
  serif: "Serif",
  mono: "Mono",
  rounded: "Rounded",
  inter: "Inter",
  "source-serif": "Source Serif",
  "jetbrains-mono": "JetBrains Mono",
  nunito: "Nunito",
};
const FONT_FAMILY_META: ChoiceMeta = {
  sans: { icon: "file-font", desc: "System sans" },
  serif: { icon: "file-font", desc: "System serif" },
  mono: { icon: "file-font", desc: "System monospace" },
  rounded: { icon: "file-font", desc: "System rounded" },
  inter: { icon: "file-font", desc: "Inter, bundled" },
  "source-serif": { icon: "file-font", desc: "Source Serif 4, bundled" },
  "jetbrains-mono": { icon: "file-font", desc: "JetBrains Mono, bundled" },
  nunito: { icon: "file-font", desc: "Nunito, bundled" },
};
const alignValues: Record<string, string[]> = {
  paragraph: paraAligns,
};
const readModes = ["document", "section"];
const readModeLabel: Record<string, string> = {
  document: "Whole document",
  section: "One section",
};
const READ_MODE_META: ChoiceMeta = {
  document: { icon: "file", desc: "Read the document as one page" },
  section: { icon: "list", desc: "Reveal one section at a time" },
};

const commonOptions = (
  blocks: MarBlock[],
): { values: Record<string, unknown>; mixed: Set<string> } => {
  const first = blocks[0]?.options ?? {};
  const values: Record<string, unknown> = { ...first };
  const mixed = new Set<string>();
  if (blocks.length < 2) return { values, mixed };
  for (const key of Object.keys(first)) {
    const shape = typeof first[key];
    if (!blocks.every((b) => key in b.options && typeof b.options[key] === shape)) {
      delete values[key];
      continue;
    }
    if (blocks.every((b) => b.options[key] === first[key])) continue;
    mixed.add(key);
    if (shape !== "boolean") values[key] = "";
  }
  return { values, mixed };
};

export const getBlockOptions = (
  engine: BlockEngine,
  blockIds: BlockId[],
): BlockOption[] => {
  const blocks = blockIds
    .map((id) => getBlock(engine.doc.value, id))
    .filter((b): b is MarBlock => b !== null);
  const block = blocks[0];
  if (!block) return [];
  const ids = blocks.map((b) => b.id);
  const blockId = block.id;
  const many = blocks.length > 1;
  const merged = commonOptions(blocks);
  const a = merged.values;
  const common = <T,>(read: (b: MarBlock) => T): T | null => {
    const first = read(block);
    return blocks.every((b) => read(b) === first) ? first : null;
  };
  const flag = (key: string, value: boolean): boolean | null =>
    merged.mixed.has(key) ? null : value;
  const everyKind = (kinds: string[]): boolean =>
    blocks.every((b) => kinds.includes(b.kind));
  const removeLabel = many ? `Remove these ${blocks.length} blocks` : "Remove this block";
  const authoring = engine.doc.value.type === "template";
  const deleteAll = (): void =>
    engine.dispatch((doc) => {
      let next = doc;
      for (const id of ids) next = removeBlock(next, id);
      return { doc: next, selection: null };
    });
  const structurallyLocked = (b: MarBlock): boolean =>
    isBlockLocked(b) || ancestorContentLocked(engine.doc.value, b.id);
  if (
    !authoring &&
    blocks.some((b) => isContentLocked(b) || ancestorContentLocked(engine.doc.value, b.id))
  ) {
    if (blocks.some(structurallyLocked)) return [];
    return [
      {
        title: "Delete",
        icon: "trash",
        description: removeLabel,
        run: deleteAll,
      },
    ];
  }
  const options: BlockOption[] = [];
  const updateAll = (fn: (b: MarBlock) => MarBlock): void =>
    engine.dispatch((doc) => {
      let next = doc;
      for (const id of ids) next = updateBlock(next, id, fn);
      return { doc: next };
    });
  const dispatchAll = (fn: (doc: MarDocument, id: BlockId) => MarDocument): void =>
    engine.dispatch((doc) => {
      let next = doc;
      for (const id of ids) next = fn(next, id);
      return { doc: next };
    });
  const setOption = (patch: Record<string, unknown>): void =>
    updateAll((b) => ({ ...b, options: { ...b.options, ...patch } }));
  const blockText = (): string =>
    Array.isArray(block.content) ? deltaText(block.content) : "";

  const pick = (
    title: string,
    icon: string,
    values: string[],
    current: string,
    apply: (value: string) => void,
    label?: (value: string) => string,
    meta?: Record<string, { icon?: string; desc?: string }>,
  ): BlockOption => ({
    title,
    icon,
    description: meta?.[current]?.desc ?? (label ? label(current) : capitalize(current)),
    choices: values.map((value) => ({
      title: label ? label(value) : capitalize(value),
      icon: meta?.[value]?.icon ?? icon,
      description: meta?.[value]?.desc,
      active: value === current,
      run: () => apply(value),
    })),
  });

  const toggle = (
    title: string,
    icon: string,
    value: boolean | null,
    onLabel: string,
    offLabel: string,
    set: (next: boolean) => void,
  ): BlockOption => ({
    title,
    icon,
    description: value === null ? "" : value ? onLabel : offLabel,
    choices: [
      { title: onLabel, icon: "circle-check", active: value === true, run: () => set(true) },
      { title: offLabel, icon: "minus", active: value === false, run: () => set(false) },
    ],
  });

  const field = (
    title: string,
    icon: string,
    description: string,
    value: string,
    placeholder: string,
    apply: (value: string) => void | Promise<void>,
  ): BlockOption => ({ title, icon, description, input: { value, placeholder, apply } });

  const coordinatesField = (lat: number, lng: number): BlockOption =>
    field("Set coordinates", "map-pin", lat || lng ? `${lat}, ${lng}` : "Latitude and longitude", lat || lng ? `${lat}, ${lng}` : "", "59.9139, 10.7522", (next) => {
      const [nlat, nlng] = next.split(",").map((s) => Number(s.trim()));
      if (nlat !== undefined && nlng !== undefined && !Number.isNaN(nlat) && !Number.isNaN(nlng)) setOption({ lat: nlat, lng: nlng, address: "" });
    });

  const addressField = (current: string, description: string): BlockOption =>
    field("Set address", "search", current || description, current, "Karl Johans gate 1, Oslo", async (next) => {
      if (!next) return;
      const hit = await getCoordinates(next);
      if (hit) setOption({ address: next, lat: hit.lat, lng: hit.lng });
    });

  const mediaField = (
    kind: MarMediaKind,
    title: string,
    current: string,
    key: string,
  ): BlockOption => {
    const request = engine.config.requestMedia;
    const description = current || `No ${kind === "pdf" ? "PDF" : kind} set`;
    if (request) {
      return {
        title,
        icon: "upload",
        description,
        run: async () => {
          const next = await request(kind, current);
          if (next) setOption(getMediaOptions(kind, next));
        },
      };
    }
    return field(title, "link", description, current, "https://", (next) => {
      if (next) setOption({ [key]: next });
    });
  };

  const text = {
    fontFamily: common((b) => sharedText(engine.doc.value, b.id).fontFamily) ?? "",
    fontSize: common((b) => sharedText(engine.doc.value, b.id).fontSize) ?? "",
    lineHeight: common((b) => sharedText(engine.doc.value, b.id).lineHeight) ?? "",
  };
  const setText = (patch: Partial<SharedText>): void =>
    updateAll((b) => ({ ...b, ...patch, inherits: false }));
  const setRecord = (patch: Partial<Pick<MarBlock, "edit" | "read" | "inherits">>): void =>
    updateAll((b) => ({ ...b, ...patch }));

  options.push(
    toggle(
      "Inherits",
      "sitemap",
      common((b) => b.inherits),
      "Text from the parent",
      "Text set here",
      (next) => setRecord({ inherits: next }),
    ),
    pick("Font", "file-font", fontFamilies, text.fontFamily, (v) => setText({ fontFamily: v as FontFamily }), (v) => fontFamilyLabel[v] ?? capitalize(v), FONT_FAMILY_META),
    pick("Font size", "text-height", fontSizes, text.fontSize, (v) => setText({ fontSize: v as FontSize }), (v) => fontSizeLabel[v] ?? capitalize(v), FONT_SIZE_META),
    pick("Line height", "text-height", lineHeights, text.lineHeight, (v) => setText({ lineHeight: v as LineHeight }), undefined, LINE_HEIGHT_META),
  );

  if ("align" in a) {
    const align = String(a.align ?? "left");
    const values = common((b) => alignValues[b.kind] ?? ALIGNS) ?? ALIGNS;
    const meta = values === paraAligns ? PARA_ALIGN_META : ALIGN_META;
    options.push(pick("Align", alignIcon(align), values, align, (v) => setOption({ align: v }), undefined, meta));
  }
  if ("width" in a) {
    options.push(pick("Width", "full-width", paraWidths, String(a.width ?? "full"), (v) => setOption({ width: v }), undefined, PARA_WIDTH_META));
  }
  if ("padTop" in a) {
    options.push(pick("Padding top", "arrow-up", paraPadTops, String(a.padTop ?? "none"), (v) => setOption({ padTop: v }), (v) => paraPadLabel[v] ?? capitalize(v), PARA_PT_META));
  }
  if (typeof a.background === "boolean") {
    options.push(toggle("Background", "square", flag("background", a.background), "On", "Off", (next) => setOption({ background: next })));
  } else if ("background" in a) {
    options.push(pick("Background", "palette", countdownBackgrounds, String(a.background ?? "none"), (v) => setOption({ background: v }), themeColorLabel, COUNTDOWN_BG_META));
  }
  if (everyKind(["section"])) {
    options.push(
      pick("Read mode", "book", readModes, common((b) => b.read) ?? "", (v) => setRecord({ read: v as ReadMode }), (v) => readModeLabel[v] ?? v, READ_MODE_META),
    );
  }
  if (authoring) {
    options.push(
      pick("Edit mode", "lock", editModes, common((b) => b.edit) ?? "", (v) => setRecord({ edit: v as EditMode }), (v) => editModeLabel[v] ?? v, EDIT_MODE_META),
    );
  }
  for (const option of options) option.shared = true;
  const sharedCount = options.length;
  const trimKind = (): void => {
    if (!many) return;
    const kind = options.splice(sharedCount);
    options.push(...kind.filter((option) => option.choices?.length));
  };

  if (everyKind(["listItem", "taskItem"])) {
    const listOf = (b: MarBlock): MarBlock | null => {
      const parentId = locate(engine.doc.value, b.id)?.parentId ?? null;
      return parentId ? getBlock(engine.doc.value, parentId) : null;
    };
    const parentKind = common((b) => listOf(b)?.kind ?? "") ?? "";
    const listStyle = common((b) => String(listOf(b)?.options.listStyle ?? "decimal")) ?? "";
    const convert = (kind: string, style?: string): void =>
      dispatchAll((doc, id) => setListType(doc, id, kind, style).doc);
    options.push({
      title: "List type",
      icon: "list",
      description: "Convert from here down",
      choices: [
        { title: "Bulleted", icon: "list", description: "Bullet points", active: parentKind === "bulletList", run: () => convert("bulletList") },
        { title: "Numbered", icon: "list", description: "Numbered list", active: parentKind === "orderedList", run: () => convert("orderedList") },
        { title: "Task", icon: "check-square", description: "Checkboxes", active: parentKind === "taskList", run: () => convert("taskList") },
      ],
    });
    if (parentKind === "orderedList") {
      options.push(
        pick(
          "Format",
          "sort",
          orderedListStyles,
          listStyle,
          (v) => convert("orderedList", v),
          (v) => v,
          ORDERED_META,
        ),
      );
    }
    trimKind();
    options.push({
      title: "Delete",
      icon: "trash",
      description: many ? `Remove these ${blocks.length} items` : "Remove this item",
      run: deleteAll,
    });
    return options;
  }

  switch (everyKind([block.kind]) ? block.kind : "") {
    case "paragraph": {
      options.push(
        pick("Wrap", "menu", paraWraps, String(a.wrap ?? "wrap"), (v) => setOption({ wrap: v }), (v) => (v === "nowrap" ? "No wrap" : capitalize(v)), PARA_WRAP_META),
      );
      break;
    }
    case "codeBlock": {
      if (a.language !== "mermaid") {
        options.push(
          pick("Language", "code", LANGUAGES, String(a.language ?? "plaintext"), (v) => setOption({ language: v }), (v) => v),
        );
      }
      options.push(
        toggle("Line numbers", "hashtag", flag("lineNumbers", a.lineNumbers !== false), "Shown", "Hidden", (next) => setOption({ lineNumbers: next })),
        toggle("Overflow", "arrows-horizontal", flag("lineWrap", a.lineWrap !== true), "Scroll", "Wrap", (next) => setOption({ lineWrap: !next })),
      );
      options.push({
        title: "Copy code",
        icon: "copy",
        description: "Copy block contents",
        run: () => {
          const text = blockText();
          if (text && typeof navigator !== "undefined") void navigator.clipboard?.writeText(text);
        },
      });
      break;
    }
    case "html": {
      const source = a.source === true;
      options.push(
        {
          title: source ? "Rendered" : "HTML source",
          icon: source ? "newspaper" : "code",
          description: source ? "Show the rendered output" : "Show the HTML markup",
          run: () => setOption({ source: !source }),
        },
        {
          title: "Copy HTML",
          icon: "copy",
          description: "Copy the markup",
          run: () => {
            const text = String(a.html ?? "");
            if (text && typeof navigator !== "undefined") void navigator.clipboard?.writeText(text);
          },
        },
      );
      break;
    }
    case "toggle": {
      options.push(
        toggle(
          "Default state",
          a.open !== false ? "chevron-down" : "chevron-right",
          flag("open", a.open !== false),
          "Open",
          "Collapsed",
          (next) => setOption({ open: next }),
        ),
      );
      break;
    }
    case "callout": {
      const variant = String(a.variant ?? "info");
      options.push(
        pick("Style", calloutIcons[variant] ?? "info", calloutVariants, variant, (v) => setOption({ variant: v, icon: calloutIcons[v] }), undefined, CALLOUT_META),
      );
      break;
    }
    case "blockquote": {
      options.push(
        pick("Style", "palette", quoteVariants, String(a.variant ?? "default"), (v) => setOption({ variant: v }), undefined, QUOTE_VARIANT_META),
        pick("Size", "text-height", quoteSizes, String(a.size ?? "md"), (v) => setOption({ size: v }), (v) => v.toUpperCase(), QUOTE_SIZE_META),
      );
      break;
    }
    case "orderedList": {
      options.push(
        pick("Format", "sort", orderedListStyles, String(a.listStyle ?? "decimal"), (v) => setOption({ listStyle: v }), (v) => v, ORDERED_META),
      );
      break;
    }
    case "heading": {
      const collapsed = !!a.collapsed;
      const mixedLevel = merged.mixed.has("level");
      const level = Number(a.level ?? 1) || 1;
      const numbering = engine.numbering.value;
      const topIds = engine.doc.value.root;
      const myIdx = topIds.indexOf(blockId);
      const startIdx = numbering.startId ? topIds.indexOf(numbering.startId) : 0;
      const numbered = numbering.enabled && myIdx >= 0 && myIdx >= startIdx && level >= numbering.startLevel;
      options.push({
        title: "Level",
        icon: `heading-${level}`,
        description: mixedLevel ? "" : `Heading ${level}`,
        choices: [1, 2, 3, 4].map((l) => ({
          title: `Heading ${l}`,
          icon: `heading-${l}`,
          description: ["Largest", "Large", "Medium", "Small"][l - 1],
          active: !mixedLevel && l === level,
          run: () => dispatchAll((doc, id) => setBlockKind(doc, id, "heading", { level: l }).doc),
        })),
      });
      options.push(
        toggle("Section", collapsed ? "chevron-right" : "chevron-down", flag("collapsed", collapsed), "Collapsed", "Expanded", (next) => setOption({ collapsed: next })),
      );
      if (!many) {
        options.push(
          toggle("Numbering", "hashtag", numbered, "Numbered from here", "Not numbered",
            (next) => (next ? engine.setNumbering(true, level, blockId) : engine.setNumbering(false, numbering.startLevel, null))),
        );
      }
      break;
    }
    case "video":
    case "image": {
      const mediaKind = block.kind === "video" ? "video" : "image";
      const fit = a.fit !== false;
      const height = (a.height as number | null) ?? null;
      options.push(
        toggle("Scale to fit", "arrows-horizontal", flag("fit", fit), "On", "Off", (next) => setOption({ fit: next })),
      );
      if (block.kind === "image") {
        const cropped = Number(a.cropX ?? 0) !== 0 || Number(a.cropY ?? 0) !== 0 || Number(a.cropScale ?? 1) !== 1;
        options.push(
          pick("Content fit", "expand", OBJECT_FITS, String(a.objectFit ?? "cover"), (v) => setOption({ objectFit: v }), undefined, FIT_META),
        );
        if (cropped) {
          options.push({ title: "Reset crop", icon: "refresh", description: "Clear pan and zoom", run: () => setOption({ cropX: 0, cropY: 0, cropScale: 1 }) });
        }
      }
      if (block.kind === "video") {
        options.push(
          toggle("Autoplay", "refresh", flag("autoplay", !!a.autoplay), "On", "Off", (next) => setOption({ autoplay: next })),
        );
      }
      options.push(
        { title: "Taller", icon: "arrow-up", description: "Increase height", run: () => setOption({ height: (height ?? 240) + 40 }) },
        { title: "Shorter", icon: "arrow-down", description: "Decrease height", run: () => setOption({ height: Math.max(80, (height ?? 240) - 40) }) },
        { title: "Reset size", icon: "refresh", description: "Natural height, fit width", run: () => setOption({ height: null, fit: true }) },
        mediaField(mediaKind, `Replace ${mediaKind}`, String(a.src ?? ""), "src"),
      );
      break;
    }
    case "audio": {
      options.push(
        pick("Layout", "menu", audioLayouts, String(a.layout ?? "large"), (v) => setOption({ layout: v }), undefined, AUDIO_META),
        toggle("Autoplay", "refresh", flag("autoplay", !!a.autoplay), "On", "Off", (next) => setOption({ autoplay: next })),
        mediaField("audio", "Replace audio", String(a.src ?? ""), "src"),
      );
      break;
    }
    case "bookmark":
    case "linkPreview": {
      const display = a.display === "card" ? "card" : "inline";
      const url = String(a.url ?? "");
      options.push(
        pick("Display", "id-card", ["card", "inline"], display, (v) => setOption({ display: v }), undefined, DISPLAY_META),
        {
          title: "Open link",
          icon: "open-in-new",
          description: url || "No link set",
          run: () => {
            if (url && typeof window !== "undefined") window.open(url, "_blank", "noopener");
          },
        },
        {
          title: "Copy link",
          icon: "copy",
          description: "Copy the URL",
          run: () => {
            if (url && typeof navigator !== "undefined") void navigator.clipboard?.writeText(url);
          },
        },
        field("Replace link", "link", url || "No link set", url, "https://", (next) => {
          if (next) setOption({ url: next });
        }),
      );
      break;
    }
    case "tableOfContents": {
      const showTitle = a.showTitle !== false;
      const bare = !!a.bare;
      const autoWidth = !!a.autoWidth;
      const fontScale = (a.fontScale as number | undefined) ?? 1;
      const placement = String(a.placement ?? "inline");
      options.push(
        pick("Placement", placement === "inline" ? "list" : "sidebar", TOC_PLACEMENTS, placement, (v) => setOption({ placement: v }), undefined, TOC_PLACEMENT_META),
        toggle("Title", "list", flag("showTitle", showTitle), "Shown", "Hidden", (next) => setOption({ showTitle: next })),
        toggle("Box", "square-dashed", flag("bare", !bare), "Shown", "Hidden", (next) => setOption({ bare: !next })),
        toggle("Width", "arrows-horizontal", flag("autoWidth", autoWidth), "Auto", "Full", (next) => setOption({ autoWidth: next })),
        { title: "Larger text", icon: "arrow-up", description: "Increase font size", run: () => setOption({ fontScale: Math.min(2, Math.round((fontScale + 0.1) * 10) / 10) }) },
        { title: "Smaller text", icon: "arrow-down", description: "Decrease font size", run: () => setOption({ fontScale: Math.max(0.6, Math.round((fontScale - 0.1) * 10) / 10) }) },
      );
      break;
    }
    case "meetingNotes": {
      const transcript = String(a.transcript ?? "");
      const recId = String(a.recId ?? "");
      const audioUrl = recId ? useRecorderSession(recId).audioUrl : "";
      options.push({
        title: "Copy transcript",
        icon: "copy",
        description: transcript ? "Copy transcript text" : "No transcript yet",
        run: () => {
          if (transcript && typeof navigator !== "undefined") void navigator.clipboard?.writeText(transcript);
        },
      });
      options.push({
        title: "Download audio",
        icon: "download",
        description: audioUrl ? "Save the recording" : "No recording yet",
        run: () => {
          if (!audioUrl || typeof document === "undefined") return;
          const link = document.createElement("a");
          link.href = audioUrl;
          link.download = `${transcript ? "recording" : recId || "recording"}.webm`;
          document.body.appendChild(link);
          link.click();
          link.remove();
        },
      });
      break;
    }
    case "embed":
    case "pdf": {
      const fullWidth = a.fullWidth !== false;
      const height = (a.height as number | null) ?? null;
      const srcUrl = String((block.kind === "embed" ? a.url : a.src) ?? "");
      const srcKey = block.kind === "embed" ? "url" : "src";
      options.push(
        toggle("Width", "arrows-horizontal", flag("fullWidth", fullWidth), "Full", "Auto", (next) => setOption({ fullWidth: next })),
        { title: "Taller", icon: "arrow-up", description: "Increase height", run: () => setOption({ height: (height ?? 384) + 40 }) },
        { title: "Shorter", icon: "arrow-down", description: "Decrease height", run: () => setOption({ height: Math.max(120, (height ?? 384) - 40) }) },
        { title: "Reset size", icon: "refresh", description: "Default height and width", run: () => setOption({ height: null, fullWidth: true }) },
        {
          title: "Open in new tab",
          icon: "open-in-new",
          description: srcUrl || "No source set",
          run: () => {
            if (srcUrl && typeof window !== "undefined") window.open(srcUrl, "_blank", "noopener");
          },
        },
        block.kind === "pdf"
          ? mediaField("pdf", "Replace PDF", srcUrl, srcKey)
          : field("Replace embed", "link", srcUrl || "No embed set", srcUrl, "https://", (next) => {
              if (next) setOption({ [srcKey]: next });
            }),
      );
      break;
    }
    case "map": {
      const zoom = Number(a.zoom ?? 13);
      const label = String(a.label ?? "");
      const lat = Number(a.lat ?? 0);
      const lng = Number(a.lng ?? 0);
      const mapAddress = String(a.address ?? "");
      const mapInteractive = a.interactive === true;
      const mapVariant = String(a.variant ?? "inline");
      options.push(
        pick(
          "View",
          "map-pin",
          ["inline", "card"],
          mapVariant,
          (next) => setOption({ variant: next }),
          undefined,
          {
            inline: { icon: "map-pin", desc: "Bare map in the flow" },
            card: { icon: "open-in-new", desc: "Label, address, and a link out" },
          },
        ),
        { title: "Zoom in", icon: "plus", description: "Closer view", run: () => setOption({ zoom: Math.min(19, zoom + 1) }) },
        { title: "Zoom out", icon: "minus", description: "Wider view", run: () => setOption({ zoom: Math.max(1, zoom - 1) }) },
        addressField(mapAddress, "Center on a resolved address"),
        coordinatesField(lat, lng),
        toggle(
          "Interactive",
          "arrows-alt",
          flag("interactive", mapInteractive),
          "Pan and zoom live",
          "Static view",
          (next) => setOption({ interactive: next }),
        ),
        field("Rename label", "menu", label || "Caption on the marker", label, "Office", (next) => setOption({ label: next })),
        {
          title: "Open in maps",
          icon: "open-in-new",
          description: "Open on OpenStreetMap",
          run: () => {
            if (typeof window !== "undefined") {
              window.open(`https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=${zoom}/${lat}/${lng}`, "_blank", "noopener");
            }
          },
        },
      );
      break;
    }
    case "weather": {
      const weatherLabel = String(a.label ?? "");
      const weatherAddress = String(a.address ?? "");
      const weatherLat = Number(a.lat ?? 0);
      const weatherLng = Number(a.lng ?? 0);
      const weatherCount = Math.min(12, Math.max(1, Number(a.count) || 6));
      options.push(
        pick(
          "View",
          "cloud-sun",
          ["card", "inline"],
          String(a.variant ?? "card"),
          (next) => setOption({ variant: next }),
          undefined,
          {
            card: { icon: "id-card", desc: "Reading, details, and strip" },
            inline: { icon: "menu", desc: "Single row in the flow" },
          },
        ),
        pick(
          "Forecast",
          "clock",
          ["hours", "days", "none"],
          String(a.forecast ?? "hours"),
          (next) => setOption({ forecast: next }),
          undefined,
          {
            hours: { icon: "clock", desc: "Next hours" },
            days: { icon: "calendar", desc: "Coming days" },
            none: { icon: "minus", desc: "Reading only" },
          },
        ),
        pick(
          "Cells",
          "sort",
          ["3", "4", "5", "6", "8", "10", "12"],
          String(weatherCount),
          (next) => setOption({ count: Number(next) }),
          (value) => `${value} cells`,
        ),
        addressField(weatherAddress, "Forecast a resolved address"),
        coordinatesField(weatherLat, weatherLng),
        field("Rename label", "menu", weatherLabel || "Place name beside the reading", weatherLabel, "Oslo", (next) => setOption({ label: next })),
      );
      break;
    }
    case "file": {
      const url = String(a.url ?? "");
      const name = String(a.name ?? "file");
      options.push(
        {
          title: "Open",
          icon: "open-in-new",
          description: url || "No file set",
          run: () => {
            if (url && typeof window !== "undefined") window.open(url, "_blank", "noopener");
          },
        },
        {
          title: "Download",
          icon: "download",
          description: "Save the file",
          run: () => {
            if (!url || typeof document === "undefined") return;
            const link = document.createElement("a");
            link.href = url;
            link.download = name;
            document.body.appendChild(link);
            link.click();
            link.remove();
          },
        },
        mediaField("file", "Replace file", url, "url"),
      );
      break;
    }
    case "table": {
      const fullWidth = !!a.fullWidth;
      const textAlign = String(a.textAlign ?? "left");
      options.push(
        toggle("Full width", "arrows-horizontal", flag("fullWidth", fullWidth), "On", "Off", (next) => setOption({ fullWidth: next })),
        pick("Text align", alignIcon(textAlign), ALIGNS, textAlign, (v) => setOption({ textAlign: v }), undefined, ALIGN_META),
      );
      break;
    }
    case "textInput": {
      const multiline = a.multiline === true;
      options.push(
        toggle("Lines", multiline ? "align-left" : "menu", flag("multiline", multiline), "Multiline", "Single line", (next) => setOption({ multiline: next })),
      );
      break;
    }
    case "choiceInput": {
      const multi = a.multi === true;
      const choiceOptions = Array.isArray(a.options) ? (a.options as string[]) : [];
      options.push(
        toggle("Selection", multi ? "check-square" : "circle", flag("multi", multi), "Multiple answers", "One answer", (next) => setOption({ multi: next })),
        {
          title: "Sort options",
          icon: "sort",
          description: "Order the list A to Z",
          run: () => setOption({ options: [...choiceOptions].sort((x, y) => x.localeCompare(y)) }),
        },
      );
      break;
    }
    case "ratingInput": {
      const max = Math.min(10, Math.max(2, Number(a.max) || 5));
      options.push(
        pick(
          "Scale",
          "sort",
          ["2", "3", "4", "5", "6", "7", "8", "9", "10"],
          String(max),
          (v) => setOption({ max: Number(v) }),
          (v) => `1 to ${v}`,
        ),
      );
      break;
    }
    case "countdown": {
      const raw = String(a.target ?? "");
      const parsed = raw ? new Date(raw) : null;
      const targetDate = parsed && !Number.isNaN(parsed.getTime()) ? parsed : null;
      options.push({
        title: "Target",
        icon: "clock",
        description: targetDate
          ? targetDate.toLocaleString(undefined, {
              dateStyle: "medium",
              timeStyle: "short",
            })
          : "No target set",
        run: async (anchor) => {
          const dropdown = (await import("@/components/MarDateDropdown")).default;
          const picked = await openModal<MarDateValue | undefined>({
            component: dropdown,
            kind: "dropdown",
            backdrop: "invisible",
            anchor: anchor ? { target: anchor } : undefined,
            placement: { side: "bottom", align: "start", offset: 6, minWidth: 280 },
            props: { mode: "single", selected: targetDate, withTime: true },
          });
          if (picked === undefined) return;
          setOption({ target: picked instanceof Date ? picked.toISOString() : "" });
        },
      });
      const bgImage = String(a.backgroundImage ?? "");
      options.push(
        pick(
          "Mode",
          a.mode === "inline" ? "arrows-horizontal" : "menu",
          countdownModes,
          String(a.mode ?? "stacked"),
          (v) => setOption({ mode: v }),
          undefined,
          COUNTDOWN_MODE_META,
        ),
        engine.config.requestMedia
          ? {
              title: "Background image",
              icon: "image",
              description: bgImage || "None",
              run: async () => {
                const next = await engine.config.requestMedia?.("image", bgImage);
                if (!next) return;
                setOption({ backgroundImage: next.url });
              },
            }
          : field("Background image", "image", bgImage || "None", bgImage, "https://", (next) => setOption({ backgroundImage: next })),
      );
      break;
    }
    case "imageGrid": {
      const gridColumns = Math.min(6, Math.max(1, Number(a.columns) || 3));
      const gridRows = Math.min(6, Math.max(1, Number(a.rows) || 2));
      const gridGap = Math.max(0, Number(a.gap) || 0);
      const gridRadius = Math.max(0, Number(a.radius) || 0);
      options.push(
        pick(
          "Cells per row",
          "table",
          ["1", "2", "3", "4", "5", "6"],
          String(gridColumns),
          (v) => setOption({ columns: Number(v) }),
          (v) => `${v} across`,
        ),
        pick(
          "Rows",
          "sort",
          ["1", "2", "3", "4", "5", "6"],
          String(gridRows),
          (v) => setOption({ rows: Number(v) }),
          (v) => `${v} down`,
        ),
        pick(
          "Gutter",
          "arrows-horizontal",
          ["0", "2", "4", "8", "16", "24"],
          String(gridGap),
          (v) => setOption({ gap: Number(v) }),
          (v) => (v === "0" ? "No gap" : `${v} px`),
        ),
        pick(
          "Corners",
          "square-dashed",
          ["0", "4", "8", "16", "24"],
          String(gridRadius),
          (v) => setOption({ radius: Number(v) }),
          (v) => (v === "0" ? "Square" : `${v} px`),
        ),
        toggle(
          "Title",
          "text-height",
          flag("showTitle", a.showTitle !== false),
          "Shown",
          "Hidden",
          (next) => setOption({ showTitle: next }),
        ),
        pick(
          "Title size",
          "text-height",
          fontSizes,
          String(a.titleSize ?? "md"),
          (v) => setOption({ titleSize: v }),
          (v) => fontSizeLabel[v] ?? capitalize(v),
          FONT_SIZE_META,
        ),
      );
      break;
    }
    case "columnList": {
      const cols = childBlocks(engine.doc.value, blockId);
      const spans = cols.map((c) => Math.max(1, Number(c.options.span) || 1));
      const preset = spans.join(":");
      const setSpans = (next: number[]): void =>
        engine.dispatch((doc) => {
          let out = doc;
          cols.forEach((col, i) => {
            const span = next[i] ?? 1;
            out = updateBlock(out, col.id, (b) => ({
              ...b,
              options: { ...b.options, span },
            }));
          });
          return { doc: out };
        });
      const presets =
        cols.length === 2
          ? ["1:1", "1:2", "2:1", "1:3", "3:1"]
          : [cols.map(() => "1").join(":")];
      if (!many) {
        options.push(
          pick(
            "Split",
            "sidebar",
            presets,
            presets.includes(preset) ? preset : presets[0] ?? "1:1",
            (v) => setSpans(v.split(":").map((n) => Number(n) || 1)),
            (v) => (v.split(":").every((n) => n === "1") ? "Equal" : v),
          ),
        );
      }
      options.push(
        {
          title: "Add column",
          icon: "plus",
          description: `${cols.length + 1} across`,
          run: () =>
            engine.dispatch((doc) => {
              const paragraph = makeBlock("paragraph");
              const column = makeBlock("column", { span: 1 }, [paragraph.id]);
              return {
                doc: insertBlock(putBlocks(doc, [paragraph]), column, blockId, cols.length),
              };
            }),
        },
        {
          title: "Remove column",
          icon: "minus",
          description:
            cols.length > 2 ? `${cols.length - 1} across` : "Keeps two columns",
          run: () => {
            const last = cols[cols.length - 1];
            if (!last || cols.length <= 2) return;
            engine.dispatch((doc) => ({ doc: removeBlock(doc, last.id) }));
          },
        },
      );
      break;
    }
    case "template": {
      const fieldPath = String(a.field ?? "");
      const repeats = contentShapeOf(block) === "slot";
      options.push(
        field("Field", repeats ? "sitemap" : "link", fieldPath || "No field named", fieldPath, repeats ? "order.lines" : "customer.name", (next) => setOption({ field: next })),
      );
      break;
    }
    case "pageBlock": {
      const pageId = String(a.assetId ?? "");
      const pageLabel = String(a.label ?? "");
      if (pageId) {
        options.push({
          title: "Open page",
          icon: "open-in-new",
          description: pageLabel || "Go to linked page",
          run: () => engine.config.onOpenPageBlock?.(pageId),
        });
      }
      options.push({
        title: "Change page",
        icon: "refresh",
        description: pageId ? "Link a different page" : "Search or create a page",
        run: () => setOption({ assetId: "" }),
      });
      break;
    }
    default:
      break;
  }

  if (
    everyKind(["audio", "video", "pdf", "file", "bookmark", "linkPreview", "embed", "pageBlock"])
  ) {
    options.push(
      pick(
        "Read view",
        "search",
        ["link", "icon", "hidden"],
        String(a.readonlyDisplay ?? "link"),
        (v) => setOption({ readonlyDisplay: v }),
        (v) => (v === "link" ? "Link" : v === "icon" ? "Icon and name" : "Hidden"),
        {
          link: { icon: "link", desc: "Show as a link" },
          icon: { icon: "file", desc: "Icon and name" },
          hidden: { icon: "minus", desc: "Hide in read view" },
        },
      ),
    );
  }

  if (everyKind(["textInput", "choiceInput", "ratingInput"])) {
    const required = a.required === true;
    const answerable = a.interactive !== false;
    options.push(
      toggle("Answer", required ? "circle-check" : "circle", flag("required", required), "Required", "Optional", (next) => setOption({ required: next })),
      toggle("Read view", answerable ? "eye" : "lock", flag("interactive", answerable), "Answerable", "Locked", (next) => setOption({ interactive: next })),
    );
  }
  trimKind();

  if (authoring) {
    options.push({
      title: "Delete",
      icon: "trash",
      description: removeLabel,
      run: deleteAll,
    });
    return options;
  }

  if (blocks.some(structurallyLocked)) {
    options.push({
      title: "Locked",
      icon: "lock",
      description: "Locked by the template",
    });
    return options;
  }

  options.push({
    title: "Delete",
    icon: "trash",
    description: removeLabel,
    run: deleteAll,
  });
  return options;
};
