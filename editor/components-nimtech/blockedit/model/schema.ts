import type {
  BlockCategory,
  BlockContent,
  BlockId,
  ContentShape,
  Delta,
  EditMode,
  MarBlock,
  MarDocument,
  ReadMode,
} from "./types";
import type { MarMediaAsset, MarMediaKind } from "../../types/media.types";
import { generateBlockId } from "./ids";
import { defaultText, isSlot } from "./tree";

export interface SchemaSpec {
  kind: string;
  category: BlockCategory;
  contentShape: ContentShape;
  text: boolean;
  defaults: Record<string, unknown>;
  edit: EditMode;
  read: ReadMode;
  childKinds: string[] | "*";
}

const ANY = "*" as const;

const FLOW_CHILDREN = [
  "paragraph",
  "heading",
  "titleBlock",
  "blockquote",
  "bulletList",
  "orderedList",
  "taskList",
  "table",
  "callout",
  "toggle",
  "section",
  "columnList",
  "countdown",
  "imageGrid",
  "codeBlock",
  "html",
  "horizontalRule",
  "break",
  "image",
  "pageBlock",
  "tableOfContents",
  "video",
  "audio",
  "pdf",
  "file",
  "bookmark",
  "linkPreview",
  "embed",
  "meetingNotes",
  "map",
  "weather",
  "textInput",
  "choiceInput",
  "ratingInput",
  "poll",
  "template",
];

const defs: Record<
  string,
  {
    category: BlockCategory;
    contentShape: ContentShape;
    text?: boolean;
    defaults?: Record<string, unknown>;
    edit?: EditMode;
    read?: ReadMode;
    childKinds?: string[] | "*";
  }
> = {
  paragraph: { category: "data", contentShape: "delta", text: true, defaults: { align: "left", width: "full", wrap: "wrap", padTop: "none" } },
  heading: { category: "data", contentShape: "delta", text: true, defaults: { level: 1, collapsed: false } },
  titleBlock: { category: "data", contentShape: "delta", text: true },
  blockquote: { category: "layout", contentShape: "slot", defaults: { variant: "default", size: "md" }, childKinds: FLOW_CHILDREN },
  bulletList: { category: "layout", contentShape: "slot", childKinds: ["listItem"] },
  orderedList: { category: "layout", contentShape: "slot", defaults: { listStyle: "decimal" }, childKinds: ["listItem"] },
  listItem: { category: "layout", contentShape: "slot", childKinds: ["paragraph", "bulletList", "orderedList", "taskList"] },
  taskList: { category: "layout", contentShape: "slot", childKinds: ["taskItem"] },
  taskItem: { category: "layout", contentShape: "slot", defaults: { checked: false }, childKinds: ["paragraph", "bulletList", "orderedList", "taskList"] },
  codeBlock: { category: "data", contentShape: "delta", defaults: { language: "plaintext", lineNumbers: true, lineWrap: false } },
  html: { category: "data", contentShape: "delta", defaults: { html: "", source: false } },
  horizontalRule: { category: "shape", contentShape: "none" },
  break: { category: "shape", contentShape: "none", defaults: { mode: "always" } },
  image: { category: "data", contentShape: "delta", defaults: { src: "", align: "center", fit: true, objectFit: "cover", height: null, cropX: 0, cropY: 0, cropScale: 1 } },
  table: { category: "layout", contentShape: "slot", defaults: { align: "left", fullWidth: false, textAlign: "left" }, childKinds: ["tableRow"] },
  tableRow: { category: "layout", contentShape: "slot", childKinds: ["tableHeader", "tableCell"] },
  tableHeader: { category: "layout", contentShape: "slot", defaults: { colspan: 1, rowspan: 1 }, childKinds: FLOW_CHILDREN },
  tableCell: { category: "layout", contentShape: "slot", defaults: { colspan: 1, rowspan: 1 }, childKinds: FLOW_CHILDREN },
  callout: { category: "layout", contentShape: "slot", defaults: { variant: "info", icon: "info" }, childKinds: FLOW_CHILDREN },
  tableOfContents: { category: "data", contentShape: "delta", defaults: { showTitle: true, bare: false, autoWidth: false, fontScale: 1, placement: "inline" } },
  columnList: { category: "layout", contentShape: "slot", childKinds: ["column"] },
  column: { category: "layout", contentShape: "slot", defaults: { span: 1 }, childKinds: FLOW_CHILDREN },
  video: { category: "data", contentShape: "delta", defaults: { src: "", name: null, align: "center", fit: true, height: null, autoplay: false } },
  audio: { category: "data", contentShape: "delta", defaults: { src: "", name: null, title: "", description: "", layout: "large", cover: "", waveform: [], autoplay: false } },
  pdf: { category: "data", contentShape: "delta", defaults: { src: "", name: null, fullWidth: true, height: null } },
  file: { category: "data", contentShape: "delta", defaults: { assetId: null, name: "File", url: null, mimeType: "" } },
  pageBlock: { category: "data", contentShape: "delta", defaults: { assetId: null, label: "Untitled page", icon: "file" } },
  bookmark: { category: "data", contentShape: "delta", defaults: { url: null, display: null } },
  linkPreview: { category: "data", contentShape: "delta", defaults: { url: null, display: null } },
  embed: { category: "data", contentShape: "delta", defaults: { url: null, fullWidth: true, height: null } },
  toggle: { category: "layout", contentShape: "slot", defaults: { open: true, summary: "", background: true }, childKinds: FLOW_CHILDREN },
  section: {
    category: "layout",
    contentShape: "slot",
    defaults: { heading: "", key: "" },
    edit: "lockBlock",
    read: "document",
    childKinds: FLOW_CHILDREN,
  },
  template: {
    category: "template",
    contentShape: "either",
    defaults: { field: "" },
    childKinds: FLOW_CHILDREN,
  },
  meetingNotes: { category: "data", contentShape: "delta", defaults: { recId: null, transcript: "" } },
  map: { category: "data", contentShape: "delta", defaults: { lat: 59.9139, lng: 10.7522, zoom: 13, label: "", address: "", variant: "inline", interactive: false } },
  weather: { category: "data", contentShape: "delta", defaults: { lat: 59.9139, lng: 10.7522, label: "", address: "", variant: "card", forecast: "hours", count: 6 } },
  textInput: { category: "data", contentShape: "delta", defaults: { key: "", label: "", multiline: false, required: false, interactive: true } },
  choiceInput: { category: "data", contentShape: "delta", defaults: { key: "", label: "", options: [], multi: false, required: false, interactive: true } },
  ratingInput: { category: "data", contentShape: "delta", defaults: { key: "", label: "", max: 5, required: false, interactive: true } },
  poll: { category: "data", contentShape: "delta", defaults: { pollId: "", question: "", options: [] } },
  countdown: { category: "data", contentShape: "delta", text: true, defaults: { target: "", mode: "stacked", background: "none", backgroundImage: "" } },
  imageGrid: { category: "data", contentShape: "delta", text: true, defaults: { images: [], columns: 3, rows: 2, gap: 0, radius: 0, showTitle: true, titleSize: "md" } },
};

export const schema: Record<string, SchemaSpec> = {};
for (const [kind, def] of Object.entries(defs)) {
  schema[kind] = {
    kind,
    category: def.category,
    contentShape: def.contentShape,
    text: def.text === true,
    defaults: def.defaults ?? {},
    edit: def.edit ?? "open",
    read: def.read ?? "document",
    childKinds: def.childKinds ?? ANY,
  };
}

export const rootChildKinds = FLOW_CHILDREN;

export const categoryOf = (kind: string): BlockCategory =>
  schema[kind]?.category ?? "data";

export const contentShapeOf = (block: string | MarBlock): ContentShape => {
  const shape =
    schema[typeof block === "string" ? block : block.kind]?.contentShape ?? "delta";
  if (shape !== "either" || typeof block === "string") return shape;
  return isSlot(block) ? "slot" : "delta";
};

export const isLayout = (kind: string): boolean => categoryOf(kind) === "layout";
export const isData = (kind: string): boolean => categoryOf(kind) === "data";
export const isShape = (kind: string): boolean => categoryOf(kind) === "shape";
export const isTextKind = (kind: string): boolean => schema[kind]?.text === true;

export const defaultOptions = (kind: string): Record<string, unknown> => ({
  ...(schema[kind]?.defaults ?? {}),
});

export const accepts = (parentKind: string | null, childKind: string): boolean => {
  const allowed = parentKind ? schema[parentKind]?.childKinds : rootChildKinds;
  if (!allowed) return false;
  if (allowed === ANY) return true;
  return allowed.includes(childKind);
};

export const emptyContent = (kind: string): BlockContent => {
  const shape = contentShapeOf(kind);
  if (shape === "none") return null;
  if (shape === "slot") return { blocks: [] };
  return [];
};

const isBlockIds = (content?: Delta | BlockId[]): content is BlockId[] =>
  Array.isArray(content) && typeof content[0] === "string";

export const makeBlock = (
  kind: string,
  options: Record<string, unknown> = {},
  content?: Delta | BlockId[],
): MarBlock => {
  const spec = schema[kind];
  const shape = spec?.contentShape ?? "delta";
  let blockContent: BlockContent;
  if (shape === "none") blockContent = null;
  else if (shape === "slot" || (shape === "either" && isBlockIds(content)))
    blockContent = { blocks: (content as BlockId[] | undefined) ?? [] };
  else blockContent = (content as Delta | undefined) ?? [];
  return {
    id: generateBlockId(),
    type: categoryOf(kind),
    kind,
    content: blockContent,
    options: { ...(spec?.defaults ?? {}), ...options },
    attr: {},
    edit: spec?.edit ?? "open",
    read: spec?.read ?? "document",
    inherits: true,
    ...defaultText,
  };
};

export const getMediaOptions = (
  kind: MarMediaKind,
  asset: MarMediaAsset,
): Record<string, unknown> => {
  if (kind === "file")
    return { assetId: asset.id, url: asset.url, name: asset.name, mimeType: asset.mimeType };
  if (kind === "pdf") return { src: asset.url, name: asset.name };
  return { src: asset.url };
};

export const makeDocument = (
  root: BlockId[] = [],
  blocks: Record<BlockId, MarBlock> = {},
): MarDocument => ({
  id: "",
  type: "document",
  width: "",
  page: {
    numbering: { from: 1, format: "n", position: "footer-center", skipFirst: true },
    break: { mode: "auto", avoidOrphans: true, beforeKinds: [] },
  },
  root,
  blocks,
});
