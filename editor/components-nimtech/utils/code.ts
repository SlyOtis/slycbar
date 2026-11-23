import { EditorView } from "codemirror";
import { StreamLanguage, HighlightStyle, Language, LanguageSupport } from "@codemirror/language";
import { RangeSetBuilder, type EditorState, type Extension } from "@codemirror/state";
import { Decoration, ViewPlugin, type DecorationSet, type ViewUpdate } from "@codemirror/view";
import { forEachDiagnostic, setDiagnosticsEffect, type Diagnostic } from "@codemirror/lint";
import { json } from "@codemirror/lang-json";
import { javascript } from "@codemirror/lang-javascript";
import { python } from "@codemirror/lang-python";
import { go } from "@codemirror/lang-go";
import { css } from "@codemirror/lang-css";
import { vue } from "@codemirror/lang-vue";
import { shell } from "@codemirror/legacy-modes/mode/shell";
import { csharp } from "@codemirror/legacy-modes/mode/clike";
import { yaml } from "@codemirror/legacy-modes/mode/yaml";
import { rust } from "@codemirror/legacy-modes/mode/rust";
import { standardSQL } from "@codemirror/legacy-modes/mode/sql";
import { html, xml } from "@codemirror/legacy-modes/mode/xml";
import { gotemplateLanguage } from "@/utils/gotemplate";
import { tags as t, tagHighlighter, highlightCode } from "@lezer/highlight";
import { tengo } from "@/utils/tengo";
import { tengoClient } from "@/utils/tengo/client";
import type { MarCodeAnswer, MarCodeDiagnostic } from "@/components/MarCode/marCode.types";

export interface CodeThemeOptions {
  showLineNumbers: boolean;
  minHeight: number | string;
  maxHeight: number | string;
  fitContent: boolean;
  fill: boolean;
  lineWrap: boolean;
}

export const codeHighlight = HighlightStyle.define([
  { tag: t.keyword, color: "var(--mar-code-keyword)", fontWeight: "600" },
  {
    tag: [t.controlKeyword, t.moduleKeyword, t.definitionKeyword, t.operatorKeyword],
    color: "var(--mar-code-keyword)",
    fontWeight: "600",
  },
  { tag: [t.atom, t.bool, t.null], color: "var(--mar-code-literal)" },
  { tag: t.number, color: "var(--mar-code-literal)" },
  { tag: [t.string, t.special(t.string)], color: "var(--mar-code-string)" },
  { tag: t.regexp, color: "var(--mar-code-string)" },
  { tag: [t.escape, t.character], color: "var(--mar-code-escape)" },
  { tag: t.comment, color: "var(--mar-code-comment)", fontStyle: "italic" },
  { tag: t.lineComment, color: "var(--mar-code-comment)", fontStyle: "italic" },
  { tag: t.blockComment, color: "var(--mar-code-comment)", fontStyle: "italic" },
  {
    tag: [t.function(t.variableName), t.function(t.propertyName)],
    color: "var(--mar-code-function)",
  },
  { tag: [t.variableName, t.name], color: "var(--mar-code-name)" },
  { tag: [t.propertyName, t.attributeName], color: "var(--mar-code-name)" },
  { tag: [t.typeName, t.className, t.namespace], color: "var(--mar-code-name)", fontWeight: "600" },
  { tag: [t.tagName, t.angleBracket], color: "var(--mar-code-tag)" },
  {
    tag: [
      t.operator,
      t.definitionOperator,
      t.derefOperator,
      t.compareOperator,
      t.arithmeticOperator,
      t.logicOperator,
      t.bitwiseOperator,
      t.updateOperator,
    ],
    color: "var(--mar-code-escape)",
  },
  {
    tag: [t.punctuation, t.separator, t.bracket, t.brace, t.paren, t.squareBracket],
    color: "var(--mar-code-default)",
  },
  { tag: t.meta, color: "var(--mar-code-keyword)" },
  { tag: [t.url, t.link], color: "var(--mar-code-function)", textDecoration: "underline" },
  { tag: t.invalid, color: "var(--mar-code-tag)", textDecoration: "underline wavy" },
  { tag: [t.heading, t.strong], fontWeight: "bold" },
  { tag: t.emphasis, fontStyle: "italic" },
  { tag: t.strikethrough, textDecoration: "line-through" },
]);

export const codeTheme = ({
  showLineNumbers,
  minHeight,
  maxHeight,
  fitContent,
  fill,
  lineWrap,
}: CodeThemeOptions): Extension =>
  EditorView.theme({
    "&": {
      backgroundColor: "var(--mar-code-bg)",
      color: "var(--mar-code-fg)",
      height: "100%",
    },
    ".cm-scroller": {
      fontFamily: "var(--mar-code-font)",
      fontSize: "0.75rem",
      lineHeight: "1.65",
      minHeight: minHeight ? (typeof minHeight === "number" ? `${minHeight}px` : minHeight) : null,
      maxHeight: fitContent ? "none" : fill ? "100%" : typeof maxHeight === "number" ? `${maxHeight}px` : maxHeight,
      overflowX: lineWrap ? "hidden" : "auto",
      overflowY: fitContent ? "visible" : "auto",
    },
    ".cm-content": showLineNumbers
      ? { padding: "10px 0", caretColor: "var(--mar-primary-color)" }
      : { padding: "10px 14px", caretColor: "var(--mar-primary-color)" },
    ".cm-cursor": {
      borderLeftColor: "var(--mar-primary-color)",
      borderLeftWidth: "2px",
    },
    ".cm-gutters": showLineNumbers
      ? {
          backgroundColor: "transparent",
          color: "rgba(215, 218, 224, 0.4)",
          border: "none",
          paddingRight: "8px",
        }
      : { display: "none" },
    ".cm-activeLine": { backgroundColor: "rgba(255,255,255,0.04)" },
    ".cm-activeLineGutter": { backgroundColor: "rgba(255,255,255,0.04)" },
    ".cm-selectionBackground, &.cm-focused .cm-selectionBackground, ::selection": {
      backgroundColor:
        "color-mix(in srgb, var(--mar-primary-color) 40%, transparent) !important",
    },
    "&.cm-focused": { outline: "none" },
    ".cm-dropCursor": { borderLeftColor: "var(--mar-primary-color)", borderLeftWidth: "2px" },
    ".cm-lintRange": {
      backgroundImage: "none",
      textDecorationLine: "underline",
      textDecorationStyle: "wavy",
      textDecorationSkipInk: "none",
      textUnderlineOffset: "0.2em",
    },
    ".cm-lintRange-error": { textDecorationColor: "var(--mar-danger-color)" },
    ".cm-lintRange-warning": { textDecorationColor: "var(--mar-warn-color)" },
    ".cm-lintPoint:after": { borderBottomColor: "var(--mar-danger-color)" },
    ".cm-lintPoint-warning:after": { borderBottomColor: "var(--mar-warn-color)" },
    ".cm-lintLine-error": { backgroundImage: "linear-gradient(color-mix(in srgb, var(--mar-danger-color) 12%, transparent), color-mix(in srgb, var(--mar-danger-color) 12%, transparent))" },
    ".cm-lintLine-warning": { backgroundImage: "linear-gradient(color-mix(in srgb, var(--mar-warn-color) 12%, transparent), color-mix(in srgb, var(--mar-warn-color) 12%, transparent))" },
    ".cm-gutter-lint": { width: "1em" },
    ".cm-gutter-lint .cm-gutterElement": { display: "flex", alignItems: "center", justifyContent: "center" },
    ".cm-lint-marker": {
      width: "0.5em",
      height: "0.5em",
      borderRadius: "50%",
    },
    ".cm-lint-marker-error": { content: "none", backgroundColor: "var(--mar-danger-color)" },
    ".cm-lint-marker-warning": { content: "none", backgroundColor: "var(--mar-warn-color)" },
    ".cm-tooltip": {
      backgroundColor: "var(--mar-code-bg)",
      color: "var(--mar-code-fg)",
      border: "1px solid rgba(255,255,255,0.12)",
      borderRadius: "6px",
      fontFamily: "var(--mar-code-font)",
      fontSize: "0.75rem",
    },
    ".cm-tooltip-lint": { padding: "0.25em 0", maxInlineSize: "min(40em, 90vw)" },
    ".cm-tooltip-hover, .cm-completionInfo": { maxInlineSize: "min(36em, 90vw)" },
    ".mar-code-hint": { display: "flex", flexDirection: "column", gap: "0.5em", padding: "0.5em 0.75em" },
    ".mar-code-hint-code": { margin: "0", fontFamily: "var(--mar-code-font)", whiteSpace: "pre-wrap", overflowWrap: "anywhere" },
    ".mar-code-hint-text": { margin: "0", fontFamily: "var(--mar-font-family)", whiteSpace: "pre-wrap", opacity: "0.8" },
    ".mar-code-hint-active": { color: "var(--mar-code-keyword)", fontWeight: "600" },
    ".mar-code-hint .tok-keyword": { color: "var(--mar-code-keyword)", fontWeight: "600" },
    ".mar-code-hint .tok-string": { color: "var(--mar-code-string)" },
    ".mar-code-hint .tok-number, .mar-code-hint .tok-bool, .mar-code-hint .tok-atom": { color: "var(--mar-code-literal)" },
    ".mar-code-hint .tok-variableName, .mar-code-hint .tok-propertyName": { color: "var(--mar-code-function)" },
    ".mar-code-hint .tok-comment": { color: "var(--mar-code-comment)", fontStyle: "italic" },
    ".mar-code-hint .tok-operator, .mar-code-hint .tok-punctuation": { color: "var(--mar-code-escape)" },
    ".cm-diagnostic": { marginLeft: "0", padding: "0.25em 0.75em", whiteSpace: "pre-wrap", overflowWrap: "anywhere" },
    ".cm-diagnostic-error, .cm-diagnostic-warning": { borderLeft: "none" },
    ".cm-diagnostic-error::before": {
      content: '"Error"',
      color: "var(--mar-danger-color)",
      fontWeight: "600",
      marginInlineEnd: "0.5em",
    },
    ".cm-diagnostic-warning::before": {
      content: '"Warning"',
      color: "var(--mar-warn-color)",
      fontWeight: "600",
      marginInlineEnd: "0.5em",
    },
  });

export const codeDiagnostics = (state: EditorState, diagnostics: MarCodeDiagnostic[]): Diagnostic[] =>
  diagnostics.map((diagnostic) => {
    const doc = state.doc;
    const lineAt = (n: number) => doc.line(Math.min(Math.max(1, Math.floor(n) || 1), doc.lines));
    const start = lineAt(diagnostic.line);
    let from = start.from + Math.min(Math.max(0, (diagnostic.column || 1) - 1), start.length);
    let to = from;
    if (diagnostic.endLine || diagnostic.endColumn) {
      const end = lineAt(diagnostic.endLine ?? diagnostic.line);
      to = end.from + Math.min(Math.max(0, (diagnostic.endColumn ?? end.length + 1) - 1), end.length);
    } else {
      const word = state.wordAt(from);
      to = word && word.from === from ? word.to : Math.min(from + 1, start.to);
    }
    if (to < from) to = from;
    if (to === from && start.length > 0) {
      if (from < start.to) to = from + 1;
      else from = from - 1;
    }
    return { from, to, severity: diagnostic.severity ?? "error", message: diagnostic.message };
  });

const diagnosticLine = {
  error: Decoration.line({ class: "cm-lintLine-error" }),
  warning: Decoration.line({ class: "cm-lintLine-warning" }),
};

const diagnosticLines = (state: EditorState): DecorationSet => {
  const lines = new Map<number, "error" | "warning">();
  forEachDiagnostic(state, (diagnostic, from, to) => {
    const severity = diagnostic.severity;
    if (severity !== "error" && severity !== "warning") return;
    const first = state.doc.lineAt(from).number;
    const last = state.doc.lineAt(Math.max(from, to)).number;
    for (let n = first; n <= last; n++) {
      if (lines.get(n) !== "error") lines.set(n, severity);
    }
  });
  const builder = new RangeSetBuilder<Decoration>();
  [...lines.entries()]
    .sort(([a], [b]) => a - b)
    .forEach(([n, severity]) => {
      const line = state.doc.line(n);
      builder.add(line.from, line.from, diagnosticLine[severity]);
    });
  return builder.finish();
};

export const codeDiagnosticLines = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = diagnosticLines(view.state);
    }
    update(update: ViewUpdate) {
      if (update.docChanged || update.transactions.some((tr) => tr.effects.some((e) => e.is(setDiagnosticsEffect))))
        this.decorations = diagnosticLines(update.state);
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

export const codeLanguage = (language: string, answer?: MarCodeAnswer): Extension => {
  const lang = (language || "").toLowerCase();
  if (lang === "json") return json();
  if (lang === "typescript" || lang === "ts") return javascript({ typescript: true });
  if (lang === "javascript" || lang === "js") return javascript();
  if (lang === "vue") return vue();
  if (lang === "tengo") return answer ? [tengo(), tengoClient(answer)] : tengo();
  if (lang === "python" || lang === "py") return python();
  if (lang === "go") return go();
  if (lang === "bash" || lang === "sh" || lang === "shell")
    return StreamLanguage.define(shell);
  if (lang === "csharp" || lang === "cs" || lang === "c#")
    return StreamLanguage.define(csharp);
  if (lang === "yaml" || lang === "yml") return StreamLanguage.define(yaml);
  if (lang === "rust" || lang === "rs") return StreamLanguage.define(rust);
  if (lang === "css") return css();
  if (lang === "sql") return StreamLanguage.define(standardSQL);
  if (lang === "html" || lang === "htm") return StreamLanguage.define(html);
  if (lang === "gotemplate") return gotemplateLanguage();
  if (lang === "xml" || lang === "svg") return StreamLanguage.define(xml);
  return [];
};

export const codeLineWrap = (lineWrap: boolean): Extension =>
  lineWrap ? EditorView.lineWrapping : [];

export interface CodeSegment {
  text: string;
  className: string;
}

const segmentHighlighter = tagHighlighter([
  { tag: [t.keyword, t.controlKeyword, t.moduleKeyword, t.definitionKeyword, t.operatorKeyword], class: "mar-tok-keyword" },
  { tag: [t.atom, t.bool, t.null, t.number], class: "mar-tok-literal" },
  { tag: [t.string, t.special(t.string), t.regexp], class: "mar-tok-string" },
  { tag: [t.comment, t.lineComment, t.blockComment], class: "mar-tok-comment" },
  { tag: [t.function(t.variableName), t.function(t.propertyName)], class: "mar-tok-function" },
  { tag: [t.variableName, t.name, t.propertyName, t.attributeName], class: "mar-tok-name" },
  { tag: [t.typeName, t.className, t.namespace], class: "mar-tok-type" },
  { tag: [t.tagName, t.angleBracket], class: "mar-tok-tag" },
  { tag: [t.operator, t.definitionOperator, t.compareOperator, t.arithmeticOperator, t.logicOperator, t.punctuation], class: "mar-tok-operator" },
]);

export const getCodeSegments = (code: string, language: string): CodeSegment[] => {
  const ext = codeLanguage(language);
  const lang = ext instanceof LanguageSupport ? ext.language : ext instanceof Language ? ext : null;
  if (!lang) return [{ text: code, className: "" }];
  const segments: CodeSegment[] = [];
  highlightCode(
    code,
    lang.parser.parse(code),
    segmentHighlighter,
    (text, className) => segments.push({ text, className }),
    () => segments.push({ text: "\n", className: "" }),
  );
  return segments;
};
