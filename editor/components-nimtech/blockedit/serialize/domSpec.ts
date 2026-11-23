
export interface AttrSpec {
  name: string;
  parse: (el: HTMLElement) => unknown;
  render: (value: unknown) => Record<string, string> | null;
}

export interface BlockSpec {
  type: string;
  tag: string;
  dataType?: string;
  attrs: AttrSpec[];
}

const dataAttr = (
  name: string,
  attr: string,
  fallback: string,
  omitDefault = false,
): AttrSpec => ({
  name,
  parse: (el) => el.getAttribute(attr) || fallback,
  render: (value) =>
    omitDefault && value === fallback ? null : { [attr]: String(value) },
});

const passAttr = (name: string, attr: string): AttrSpec => ({
  name,
  parse: (el) => el.getAttribute(attr),
  render: (value) => (value == null ? null : { [attr]: String(value) }),
});

const optionalAttr = (name: string, attr: string): AttrSpec => ({
  name,
  parse: (el) => el.getAttribute(attr) || "",
  render: (value) => (value ? { [attr]: String(value) } : null),
});

const boolAttr = (
  name: string,
  attr: string,
  defaultValue: boolean,
  trueWord = "true",
  falseWord = "false",
): AttrSpec => ({
  name,
  parse: (el) => {
    const raw = el.getAttribute(attr);
    if (raw == null) return defaultValue;
    return raw !== falseWord;
  },
  render: (value) => ({ [attr]: value ? trueWord : falseWord }),
});

const omitBoolAttr = (
  name: string,
  attr: string,
  emitWhen: boolean,
): AttrSpec => ({
  name,
  parse: (el) => el.getAttribute(attr) === "true",
  render: (value) => (value === emitWhen ? { [attr]: "true" } : null),
});

const numberAttr = (name: string, attr: string): AttrSpec => ({
  name,
  parse: (el) => {
    const raw = el.getAttribute(attr);
    return raw ? Number(raw) : null;
  },
  render: (value) =>
    value != null ? { [attr]: String(value) } : null,
});

const roAttr: AttrSpec[] = [dataAttr("readonlyDisplay", "data-ro", "link", false)];

const inputGating: AttrSpec[] = [
  omitBoolAttr("required", "data-required", true),
  boolAttr("interactive", "data-interactive", true),
];

const mediaSrc: AttrSpec[] = [
  passAttr("src", "src"),
  optionalAttr("name", "data-name"),
  ...roAttr,
];

const urlAttr: AttrSpec[] = [passAttr("url", "data-url"), ...roAttr];

const displayAttr: AttrSpec[] = [optionalAttr("display", "data-display")];

const sizeAttrs: AttrSpec[] = [
  {
    name: "fullWidth",
    parse: (el) => el.getAttribute("data-full-width") !== "false",
    render: (value) =>
      value === false ? { "data-full-width": "false" } : null,
  },
  numberAttr("height", "data-height"),
];

export const blockSpecs: BlockSpec[] = [
  {
    type: "paragraph",
    tag: "p",
    attrs: [
      dataAttr("align", "data-align", "left", true),
      dataAttr("width", "data-width", "full", true),
      dataAttr("wrap", "data-wrap", "wrap", true),
      dataAttr("padTop", "data-pt", "none", true),
    ],
  },
  {
    type: "heading",
    tag: "h",
    attrs: [omitBoolAttr("collapsed", "data-collapsed", true)],
  },
  {
    type: "titleBlock",
    tag: "h1",
    dataType: "title",
    attrs: [],
  },
  {
    type: "blockquote",
    tag: "blockquote",
    attrs: [
      dataAttr("variant", "data-variant", "default", true),
      dataAttr("size", "data-size", "md", true),
    ],
  },
  { type: "bulletList", tag: "ul", attrs: [] },
  {
    type: "orderedList",
    tag: "ol",
    attrs: [dataAttr("listStyle", "data-list-style", "decimal", true)],
  },
  { type: "listItem", tag: "li", attrs: [] },
  {
    type: "taskList",
    tag: "ul",
    dataType: "taskList",
    attrs: [],
  },
  {
    type: "taskItem",
    tag: "li",
    dataType: "taskItem",
    attrs: [boolAttr("checked", "data-checked", false)],
  },
  {
    type: "codeBlock",
    tag: "pre",
    attrs: [dataAttr("language", "data-language", "plaintext", false)],
  },
  {
    type: "horizontalRule",
    tag: "hr",
    attrs: [],
  },
  {
    type: "break",
    tag: "div",
    dataType: "break",
    attrs: [
      {
        name: "mode",
        parse: (el) => el.getAttribute("data-mode") || "always",
        render: (value) => ({
          "data-mode": String(value),
          style: `break-after:${value === "always" ? "page" : String(value)}`,
        }),
      },
    ],
  },
  {
    type: "image",
    tag: "div",
    attrs: [
      passAttr("src", "src"),
      dataAttr("align", "data-align", "center", false),
      {
        name: "fit",
        parse: (el) => el.getAttribute("data-fit") !== "0",
        render: (value) => ({ "data-fit": value ? "1" : "0" }),
      },
      dataAttr("objectFit", "data-object-fit", "cover", false),
      numberAttr("height", "style-height"),
      numberAttr("cropX", "data-crop-x"),
      numberAttr("cropY", "data-crop-y"),
      numberAttr("cropScale", "data-crop-scale"),
    ],
  },
  {
    type: "table",
    tag: "table",
    attrs: [
      dataAttr("align", "data-align", "left", false),
      boolAttr("fullWidth", "data-full-width", false),
      dataAttr("textAlign", "data-text-align", "left", false),
    ],
  },
  { type: "tableRow", tag: "tr", attrs: [] },
  {
    type: "tableHeader",
    tag: "th",
    attrs: [numberAttr("colspan", "colspan"), numberAttr("rowspan", "rowspan")],
  },
  {
    type: "tableCell",
    tag: "td",
    attrs: [numberAttr("colspan", "colspan"), numberAttr("rowspan", "rowspan")],
  },
  {
    type: "callout",
    tag: "div",
    dataType: "callout",
    attrs: [
      dataAttr("variant", "data-variant", "info", false),
      passAttr("icon", "data-icon"),
    ],
  },
  {
    type: "tableOfContents",
    tag: "div",
    dataType: "table-of-contents",
    attrs: [
      boolAttr("showTitle", "data-show-title", true),
      omitBoolAttr("bare", "data-bare", true),
      omitBoolAttr("autoWidth", "data-auto-width", true),
      dataAttr("placement", "data-placement", "inline", true),
      {
        name: "fontScale",
        parse: (el) => Number(el.getAttribute("data-font-scale")) || 1,
        render: (value) =>
          value && value !== 1 ? { "data-font-scale": String(value) } : null,
      },
    ],
  },
  {
    type: "columnList",
    tag: "div",
    dataType: "column-list",
    attrs: [],
  },
  {
    type: "column",
    tag: "div",
    dataType: "column",
    attrs: [
      {
        name: "span",
        parse: (el) => Number(el.getAttribute("data-span")) || 1,
        render: (value) => {
          const span = Number(value) || 1;
          return span === 1
            ? null
            : { "data-span": String(span), style: `flex-grow:${span}` };
        },
      },
    ],
  },
  {
    type: "video",
    tag: "div",
    dataType: "video",
    attrs: [
      ...mediaSrc,
      dataAttr("align", "data-align", "center", false),
      boolAttr("fit", "data-fit", true),
      numberAttr("height", "data-height"),
      boolAttr("autoplay", "data-autoplay", false),
    ],
  },
  {
    type: "audio",
    tag: "div",
    dataType: "audio",
    attrs: [
      ...mediaSrc,
      optionalAttr("title", "data-title"),
      optionalAttr("description", "data-description"),
      dataAttr("layout", "data-layout", "large", false),
      optionalAttr("cover", "data-cover"),
      {
        name: "waveform",
        parse: (el) => {
          try {
            return JSON.parse(el.getAttribute("data-waveform") || "[]");
          } catch {
            return [];
          }
        },
        render: (value) =>
          Array.isArray(value) && value.length
            ? { "data-waveform": JSON.stringify(value) }
            : null,
      },
      boolAttr("autoplay", "data-autoplay", false),
    ],
  },
  {
    type: "pdf",
    tag: "div",
    dataType: "pdf",
    attrs: [...mediaSrc, ...sizeAttrs],
  },
  {
    type: "file",
    tag: "div",
    dataType: "file",
    attrs: [
      passAttr("assetId", "data-asset-id"),
      passAttr("name", "data-name"),
      passAttr("url", "data-url"),
      optionalAttr("mimeType", "data-mime"),
      ...roAttr,
    ],
  },
  {
    type: "pageBlock",
    tag: "div",
    dataType: "page-block",
    attrs: [
      passAttr("assetId", "data-asset-id"),
      passAttr("label", "data-label"),
      passAttr("icon", "data-icon"),
      ...roAttr,
    ],
  },
  {
    type: "bookmark",
    tag: "div",
    dataType: "bookmark",
    attrs: [...urlAttr, ...displayAttr],
  },
  {
    type: "linkPreview",
    tag: "div",
    dataType: "link-preview",
    attrs: [...urlAttr, ...displayAttr],
  },
  {
    type: "embed",
    tag: "div",
    dataType: "embed",
    attrs: [...urlAttr, ...sizeAttrs],
  },
  {
    type: "toggle",
    tag: "div",
    dataType: "toggle",
    attrs: [
      boolAttr("open", "data-open", true),
      optionalAttr("summary", "data-summary"),
      boolAttr("background", "data-bg", true),
    ],
  },
  {
    type: "section",
    tag: "div",
    dataType: "section",
    attrs: [
      optionalAttr("heading", "data-heading"),
      optionalAttr("key", "data-key"),
    ],
  },
  {
    type: "template",
    tag: "div",
    dataType: "template",
    attrs: [optionalAttr("field", "data-field")],
  },
  {
    type: "meetingNotes",
    tag: "div",
    dataType: "meeting-notes",
    attrs: [
      optionalAttr("recId", "data-rec-id"),
      optionalAttr("transcript", "data-transcript"),
    ],
  },
  {
    type: "map",
    tag: "div",
    dataType: "map",
    attrs: [
      numberAttr("lat", "data-lat"),
      numberAttr("lng", "data-lng"),
      numberAttr("zoom", "data-zoom"),
      optionalAttr("label", "data-label"),
      optionalAttr("address", "data-address"),
      dataAttr("variant", "data-variant", "inline", true),
      omitBoolAttr("interactive", "data-interactive", true),
    ],
  },
  {
    type: "weather",
    tag: "div",
    dataType: "weather",
    attrs: [
      numberAttr("lat", "data-lat"),
      numberAttr("lng", "data-lng"),
      optionalAttr("label", "data-label"),
      optionalAttr("address", "data-address"),
      dataAttr("variant", "data-variant", "card", true),
      dataAttr("forecast", "data-forecast", "hours", true),
      numberAttr("count", "data-count"),
    ],
  },
  {
    type: "textInput",
    tag: "div",
    dataType: "text-input",
    attrs: [
      optionalAttr("key", "data-key"),
      optionalAttr("label", "data-label"),
      omitBoolAttr("multiline", "data-multiline", true),
      ...inputGating,
    ],
  },
  {
    type: "choiceInput",
    tag: "div",
    dataType: "choice-input",
    attrs: [
      optionalAttr("key", "data-key"),
      optionalAttr("label", "data-label"),
      {
        name: "options",
        parse: (el) => {
          try {
            return JSON.parse(el.getAttribute("data-options") || "[]");
          } catch {
            return [];
          }
        },
        render: (value) =>
          Array.isArray(value) && value.length
            ? { "data-options": JSON.stringify(value) }
            : null,
      },
      omitBoolAttr("multi", "data-multi", true),
      ...inputGating,
    ],
  },
  {
    type: "ratingInput",
    tag: "div",
    dataType: "rating-input",
    attrs: [
      optionalAttr("key", "data-key"),
      optionalAttr("label", "data-label"),
      numberAttr("max", "data-max"),
      ...inputGating,
    ],
  },
  {
    type: "countdown",
    tag: "div",
    dataType: "countdown",
    attrs: [
      optionalAttr("target", "data-target"),
      dataAttr("mode", "data-mode", "stacked", true),
      dataAttr("background", "data-background", "none", true),
      optionalAttr("backgroundImage", "data-background-image"),
    ],
  },
  {
    type: "imageGrid",
    tag: "div",
    dataType: "image-grid",
    attrs: [
      {
        name: "images",
        parse: (el) => {
          try {
            return JSON.parse(el.getAttribute("data-images") || "[]");
          } catch {
            return [];
          }
        },
        render: (value) =>
          Array.isArray(value) && value.length
            ? { "data-images": JSON.stringify(value) }
            : null,
      },
      numberAttr("columns", "data-columns"),
      numberAttr("rows", "data-rows"),
      numberAttr("gap", "data-gap"),
      numberAttr("radius", "data-radius"),
      boolAttr("showTitle", "data-show-title", true),
      dataAttr("titleSize", "data-title-size", "md", true),
    ],
  },
  {
    type: "poll",
    tag: "div",
    dataType: "poll",
    attrs: [
      optionalAttr("pollId", "data-poll-id"),
      optionalAttr("question", "data-question"),
      {
        name: "options",
        parse: (el) => {
          try {
            return JSON.parse(el.getAttribute("data-options") || "[]");
          } catch {
            return [];
          }
        },
        render: (value) =>
          Array.isArray(value) && value.length
            ? { "data-options": JSON.stringify(value) }
            : null,
      },
    ],
  },
];

export const mentionAttrs: AttrSpec[] = [
  passAttr("id", "data-id"),
  passAttr("label", "data-label"),
  optionalAttr("icon", "data-icon"),
  optionalAttr("type", "data-mtype"),
  optionalAttr("href", "data-href"),
  optionalAttr("preview", "data-preview"),
  optionalAttr("image", "data-image"),
];

export const specByType = new Map(blockSpecs.map((s) => [s.type, s]));
