import { getMediaOptions, makeBlock } from "../model/schema";
import type { MarMediaKind } from "../../types/media.types";
import type { SlashCommand, SlashCommandCtx } from "../engine/config";
import {
  columnsBlock,
  layoutBlock,
  placeBlock,
  tableBlock,
  turnInto,
  wrapInList,
} from "./index";
import type { EditMode } from "../model/types";
import type { BlockEngine } from "../engine/BlockEngine";

const placeLayout = (
  engine: BlockEngine,
  blockId: string,
  kind: string,
  edit?: EditMode,
): void => {
  const made = layoutBlock(kind);
  placeBlock(engine, blockId, edit ? { ...made.block, edit } : made.block, made.created);
};

const monthAhead = (): string => {
  const date = new Date();
  date.setMonth(date.getMonth() + 1);
  return date.toISOString();
};

const placeMedia = async (
  engine: SlashCommandCtx["engine"],
  blockId: string,
  kind: MarMediaKind,
): Promise<void> => {
  const request = engine.config.requestMedia;
  const asset = request ? await request(kind) : undefined;
  if (asset === null) return;
  placeBlock(engine, blockId, makeBlock(kind, asset ? getMediaOptions(kind, asset) : {}));
};

export const marBlockEditorDefaultCommands: SlashCommand[] = [
  {
    title: "Text",
    icon: "text-height",
    description: "Plain paragraph",
    keywords: ["paragraph", "text"],
    run: ({ engine, blockId }) => turnInto(engine, blockId, "paragraph"),
  },
  {
    title: "Heading 1",
    icon: "heading-1",
    description: "Large section heading",
    keywords: ["h1", "title"],
    run: ({ engine, blockId }) => turnInto(engine, blockId, "heading", { level: 1 }),
  },
  {
    title: "Heading 2",
    icon: "heading-2",
    description: "Medium section heading",
    keywords: ["h2"],
    run: ({ engine, blockId }) => turnInto(engine, blockId, "heading", { level: 2 }),
  },
  {
    title: "Heading 3",
    icon: "heading-3",
    description: "Small section heading",
    keywords: ["h3"],
    run: ({ engine, blockId }) => turnInto(engine, blockId, "heading", { level: 3 }),
  },
  {
    title: "Heading 4",
    icon: "heading-4",
    description: "Subsection heading",
    keywords: ["h4"],
    run: ({ engine, blockId }) => turnInto(engine, blockId, "heading", { level: 4 }),
  },
  {
    title: "Bulleted list",
    icon: "list",
    description: "Simple bullet list",
    keywords: ["ul", "unordered", "bullet"],
    run: ({ engine, blockId }) => wrapInList(engine, blockId, "bulletList"),
  },
  {
    title: "Numbered list",
    icon: "list",
    description: "Ordered list",
    keywords: ["ol", "ordered", "number"],
    run: ({ engine, blockId }) => wrapInList(engine, blockId, "orderedList"),
  },
  {
    title: "Task list",
    icon: "check-square",
    description: "Checkbox list",
    keywords: ["todo", "checkbox", "task"],
    run: ({ engine, blockId }) => wrapInList(engine, blockId, "taskList"),
  },
  {
    title: "Quote",
    icon: "comment",
    description: "Block quote",
    keywords: ["blockquote"],
    run: ({ engine, blockId }) =>
      placeLayout(engine, blockId, "blockquote"),
  },
  {
    title: "Code block",
    icon: "code",
    description: "Code with syntax",
    keywords: ["code", "snippet"],
    run: ({ engine, blockId }) => turnInto(engine, blockId, "codeBlock"),
  },
  {
    title: "Mermaid diagram",
    icon: "sitemap",
    description: "Diagram from text",
    keywords: ["diagram", "mermaid", "flowchart"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("codeBlock", { language: "mermaid" })),
  },
  {
    title: "HTML",
    icon: "code",
    description: "Embed raw HTML",
    keywords: ["html", "markup", "embed"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("html", { source: true })),
  },
  {
    title: "Divider",
    icon: "minus",
    description: "Horizontal rule",
    keywords: ["hr", "rule", "separator"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("horizontalRule")),
  },
  {
    title: "Page break",
    icon: "printer",
    description: "Start a new page",
    keywords: ["break", "page", "print"],
    run: ({ engine, blockId }) => placeBlock(engine, blockId, makeBlock("break")),
  },
  {
    title: "Table",
    icon: "table",
    description: "3 by 3 table",
    keywords: ["grid", "table"],
    run: ({ engine, blockId }) => {
      const made = tableBlock();
      placeBlock(engine, blockId, made.block, made.created);
    },
  },
  {
    title: "Image",
    icon: "image",
    description: "Embed an image",
    keywords: ["picture", "photo"],
    run: ({ engine, blockId }) => placeMedia(engine, blockId, "image"),
  },
  {
    title: "Toggle",
    icon: "chevron-right",
    description: "Collapsible block",
    keywords: ["collapse", "accordion"],
    run: ({ engine, blockId }) =>
      placeLayout(engine, blockId, "toggle"),
  },
  {
    title: "Callout",
    icon: "info",
    description: "Highlighted note",
    keywords: ["note", "info", "warning"],
    run: ({ engine, blockId }) =>
      placeLayout(engine, blockId, "callout"),
  },
  {
    title: "Section",
    icon: "heading-1",
    description: "Titled section with a body",
    keywords: ["section", "template", "heading", "part"],
    run: ({ engine, blockId }) =>
      placeLayout(engine, blockId, "section", "open"),
  },
  {
    title: "Template field",
    icon: "code",
    description: "Reference to a field of the data",
    keywords: ["template", "field", "placeholder", "variable"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("template")),
  },
  {
    title: "Template repeat",
    icon: "repeat",
    description: "Blocks repeated once per element of a field",
    keywords: ["template", "repeat", "range", "list"],
    run: ({ engine, blockId }) => placeLayout(engine, blockId, "template"),
  },
  {
    title: "Table of contents",
    icon: "list",
    description: "Document outline",
    keywords: ["toc", "outline"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("tableOfContents")),
  },
  {
    title: "Legend",
    icon: "sidebar",
    description: "Heading legend on the side of the page",
    keywords: ["legend", "toc", "outline", "side"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("tableOfContents", { placement: "right" })),
  },
  {
    title: "Columns",
    icon: "sidebar",
    description: "Side by side columns",
    keywords: ["column", "grid"],
    run: ({ engine, blockId }) => {
      const made = columnsBlock();
      placeBlock(engine, blockId, made.block, made.created);
    },
  },
  {
    title: "Video",
    icon: "video",
    description: "Embed a video",
    keywords: ["video", "movie"],
    run: ({ engine, blockId }) => placeMedia(engine, blockId, "video"),
  },
  {
    title: "Audio",
    icon: "music",
    description: "Embed audio",
    keywords: ["audio", "sound"],
    run: ({ engine, blockId }) => placeMedia(engine, blockId, "audio"),
  },
  {
    title: "PDF",
    icon: "file-pdf",
    description: "Embed a PDF",
    keywords: ["pdf", "document"],
    run: ({ engine, blockId }) => placeMedia(engine, blockId, "pdf"),
  },
  {
    title: "Bookmark",
    icon: "bookmark",
    description: "Link preview card",
    keywords: ["link", "bookmark"],
    run: ({ engine, blockId }) => placeBlock(engine, blockId, makeBlock("bookmark")),
  },
  {
    title: "Embed",
    icon: "code",
    description: "Embed an iframe",
    keywords: ["iframe", "embed"],
    run: ({ engine, blockId }) => placeBlock(engine, blockId, makeBlock("embed")),
  },
  {
    title: "Meeting notes",
    icon: "mic",
    description: "Record and transcribe",
    keywords: ["record", "audio", "transcribe"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("meetingNotes")),
  },
  {
    title: "Map",
    icon: "map-pin",
    description: "Embed a location map",
    keywords: ["map", "location", "place", "address"],
    run: ({ engine, blockId }) => placeBlock(engine, blockId, makeBlock("map")),
  },
  {
    title: "Weather",
    icon: "cloud-sun",
    description: "Forecast for a place from yr",
    keywords: ["weather", "forecast", "yr", "temperature", "rain"],
    run: ({ engine, blockId }) => placeBlock(engine, blockId, makeBlock("weather")),
  },
  {
    title: "Page",
    icon: "file",
    description: "Link or create a sub page",
    keywords: ["page", "subpage", "document", "child"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("pageBlock", { label: "" })),
  },
  {
    title: "Text input",
    icon: "file-text",
    description: "Free text survey question",
    keywords: ["input", "question", "survey", "text", "answer"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("textInput")),
  },
  {
    title: "Choice input",
    icon: "list-check",
    description: "Option survey question",
    keywords: ["input", "question", "survey", "choice", "select", "option"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("choiceInput")),
  },
  {
    title: "Rating input",
    icon: "star",
    description: "Star scale survey question",
    keywords: ["input", "question", "survey", "rating", "scale", "stars"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("ratingInput")),
  },
  {
    title: "Poll",
    icon: "chart-bar",
    description: "Question with live vote results",
    keywords: ["poll", "vote", "question", "survey"],
    run: ({ engine, blockId }) => placeBlock(engine, blockId, makeBlock("poll")),
  },
  {
    title: "Countdown",
    icon: "clock",
    description: "Ticking time left to a date",
    keywords: ["countdown", "timer", "date", "deadline"],
    run: ({ engine, blockId }) =>
      placeBlock(
        engine,
        blockId,
        makeBlock("countdown", { target: monthAhead() }),
      ),
  },
  {
    title: "Image grid",
    icon: "images",
    description: "Gallery of images in a grid",
    keywords: ["image", "grid", "gallery", "photos"],
    run: ({ engine, blockId }) =>
      placeBlock(engine, blockId, makeBlock("imageGrid")),
  },
];

const defaultGroupDefs: { label: string; titles: string[] }[] = [
  {
    label: "Text",
    titles: ["Text", "Heading 1", "Heading 2", "Heading 3", "Quote", "Callout"],
  },
  {
    label: "Lists",
    titles: ["Bulleted list", "Numbered list", "Task list", "Toggle"],
  },
  { label: "Media", titles: ["Image", "Image grid", "Video", "Audio", "PDF"] },
  { label: "Embeds", titles: ["Bookmark", "Embed", "Meeting notes", "Page"] },
  {
    label: "Inputs",
    titles: ["Text input", "Choice input", "Rating input", "Poll"],
  },
  {
    label: "Advanced",
    titles: [
      "Section",
      "Table",
      "Code block",
      "Mermaid diagram",
      "Divider",
      "Page break",
      "Table of contents",
      "Columns",
      "Countdown",
    ],
  },
];

const placedTitles = new Set(defaultGroupDefs.flatMap((g) => g.titles));

export const marBlockEditorDefaultGroups: {
  label: string;
  commands: string[];
}[] = [
  ...defaultGroupDefs.map((g) => ({ label: g.label, commands: [...g.titles] })),
  {
    label: "More",
    commands: marBlockEditorDefaultCommands
      .filter((c) => !placedTitles.has(c.title))
      .map((c) => c.title),
  },
].filter((g) => g.commands.length > 0);
