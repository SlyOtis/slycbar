import { StateEffect, StateField, type Extension, type Text } from "@codemirror/state";
import { EditorView, ViewPlugin, hoverTooltip, showTooltip, type Tooltip, type ViewUpdate } from "@codemirror/view";
import { snippet, type Completion, type CompletionContext, type CompletionResult } from "@codemirror/autocomplete";
import { classHighlighter, highlightCode } from "@lezer/highlight";
import type {
  MarCodeAnswer,
  MarCodeCompletionItem,
  MarCodeDiagnostic,
  MarCodePosition,
  MarCodeSignatureHelp,
} from "@/components/MarCode/marCode.types";
import type { MarFuncEntry } from "@/components/MarFuncList/marFuncList.types";
import { tengoLanguage } from "./index";

const kinds: Record<number, string> = {
  2: "method",
  3: "function",
  5: "property",
  6: "variable",
  9: "namespace",
  14: "keyword",
  21: "constant",
};

export const getTengoPosition = (doc: Text, offset: number): MarCodePosition => {
  const line = doc.lineAt(offset);
  return { line: line.number - 1, character: offset - line.from };
};

export const getTengoOffset = (doc: Text, position: MarCodePosition): number => {
  const line = doc.line(Math.min(Math.max(1, position.line + 1), doc.lines));
  return Math.min(line.from + Math.max(0, position.character), line.to);
};

const getCode = (code: string): HTMLElement => {
  const pre = document.createElement("pre");
  pre.className = "mar-code-hint-code";
  highlightCode(
    code,
    tengoLanguage.parser.parse(code),
    classHighlighter,
    (text, classes) => {
      const span = document.createElement("span");
      span.textContent = text;
      if (classes) span.className = classes;
      pre.appendChild(span);
    },
    () => pre.appendChild(document.createTextNode("\n")),
  );
  return pre;
};

const getMarkup = (value: string): HTMLElement => {
  const dom = document.createElement("div");
  dom.className = "mar-code-hint";
  value.split(/```(?:\w+)?\n([\s\S]*?)\n?```/).forEach((part, index) => {
    if (index % 2 === 1) {
      dom.appendChild(getCode(part));
      return;
    }
    part
      .split(/\n{2,}/)
      .map((text) => text.trim())
      .filter(Boolean)
      .forEach((text) => {
        const p = document.createElement("p");
        p.className = "mar-code-hint-text";
        p.textContent = text;
        dom.appendChild(p);
      });
  });
  return dom;
};

const getOption = (item: MarCodeCompletionItem, index: number): Completion => ({
  label: item.label,
  detail: item.detail && item.detail !== item.label ? item.detail : undefined,
  type: kinds[item.kind],
  boost: Math.max(-99, 99 - index),
  info: item.documentation ? () => getMarkup(item.documentation!.value) : undefined,
  apply: item.insertText ? (item.insertTextFormat === 2 ? snippet(item.insertText) : item.insertText) : undefined,
});

const getCompletion =
  (answer: MarCodeAnswer) =>
  async (context: CompletionContext): Promise<CompletionResult | null> => {
    const word = context.matchBefore(/[\w$]*/);
    const from = word ? word.from : context.pos;
    const dot = context.state.sliceDoc(from - 1, from) === ".";
    if (!context.explicit && from === context.pos && !dot) return null;
    const response = await answer({
      method: "textDocument/completion",
      code: context.state.doc.toString(),
      position: getTengoPosition(context.state.doc, context.pos),
    });
    if (context.aborted) return null;
    return { from, options: (response.items ?? []).map(getOption), validFor: /^[\w$]*$/ };
  };

const getHover = (answer: MarCodeAnswer): Extension =>
  hoverTooltip(async (view, pos) => {
    const response = await answer({
      method: "textDocument/hover",
      code: view.state.doc.toString(),
      position: getTengoPosition(view.state.doc, pos),
    });
    const hover = response.hover;
    if (!hover) return null;
    const doc = view.state.doc;
    return {
      pos: hover.range ? getTengoOffset(doc, hover.range.start) : pos,
      end: hover.range ? getTengoOffset(doc, hover.range.end) : pos,
      above: true,
      create: () => ({ dom: getMarkup(hover.contents.value) }),
    };
  });

const getSignatureDom = (help: MarCodeSignatureHelp): HTMLElement => {
  const signature = help.signatures[help.activeSignature ?? 0] ?? help.signatures[0];
  const dom = document.createElement("div");
  dom.className = "mar-code-hint";
  const label = document.createElement("pre");
  label.className = "mar-code-hint-code";
  const active = signature.parameters[help.activeParameter ?? 0]?.label ?? "";
  const open = signature.label.indexOf("(");
  const at = active ? signature.label.indexOf(active, open < 0 ? 0 : open) : -1;
  if (at < 0) label.textContent = signature.label;
  else {
    const strong = document.createElement("strong");
    strong.className = "mar-code-hint-active";
    strong.textContent = active;
    label.append(signature.label.slice(0, at), strong, signature.label.slice(at + active.length));
  }
  dom.appendChild(label);
  if (signature.documentation) {
    const p = document.createElement("p");
    p.className = "mar-code-hint-text";
    p.textContent = signature.documentation.value;
    dom.appendChild(p);
  }
  return dom;
};

const setSignature = StateEffect.define<Tooltip | null>();

const signatureField = StateField.define<Tooltip | null>({
  create: () => null,
  update(value, tr) {
    for (const effect of tr.effects) if (effect.is(setSignature)) return effect.value;
    if (!value || !tr.docChanged) return value;
    return { ...value, pos: tr.changes.mapPos(value.pos) };
  },
  provide: (field) => showTooltip.from(field),
});

const getSignature = (answer: MarCodeAnswer): Extension => [
  signatureField,
  ViewPlugin.fromClass(
    class {
      timer = 0;
      asked = 0;
      constructor(readonly view: EditorView) {}
      update(update: ViewUpdate) {
        if (update.focusChanged && !update.view.hasFocus) {
          window.clearTimeout(this.timer);
          this.asked++;
          queueMicrotask(() => this.view.dispatch({ effects: setSignature.of(null) }));
          return;
        }
        if (!update.docChanged && !update.selectionSet) return;
        window.clearTimeout(this.timer);
        this.timer = window.setTimeout(() => void this.ask(), 150);
      }
      async ask() {
        const asked = ++this.asked;
        const { state } = this.view;
        const pos = state.selection.main.head;
        const response = await answer({
          method: "textDocument/signatureHelp",
          code: state.doc.toString(),
          position: getTengoPosition(state.doc, pos),
        });
        if (asked !== this.asked || this.view.state.doc !== state.doc) return;
        const help = response.signature;
        const tooltip: Tooltip | null =
          help && help.signatures.length
            ? { pos, above: true, strictSide: false, create: () => ({ dom: getSignatureDom(help) }) }
            : null;
        this.view.dispatch({ effects: setSignature.of(tooltip) });
      }
      destroy() {
        window.clearTimeout(this.timer);
        this.asked++;
      }
    },
  ),
];

export const tengoClient = (answer: MarCodeAnswer): Extension => [
  tengoLanguage.data.of({ autocomplete: getCompletion(answer) }),
  getHover(answer),
  getSignature(answer),
];

export const getTengoDiagnostics = async (answer: MarCodeAnswer, code: string): Promise<MarCodeDiagnostic[]> => {
  const response = await answer({ method: "textDocument/diagnostic", code, position: { line: 0, character: 0 } });
  return (response.diagnostics ?? []).map((d) => ({
    line: d.range.start.line + 1,
    column: d.range.start.character + 1,
    endLine: d.range.end.line + 1,
    endColumn: d.range.end.character + 1,
    message: d.message,
    severity: d.severity === 2 ? "warning" : "error",
  }));
};

export const getTengoReference = async (answer: MarCodeAnswer): Promise<MarFuncEntry[]> => {
  const response = await answer({ method: "tengo/reference", code: "", position: { line: 0, character: 0 } });
  return (response.reference?.groups ?? []).flatMap((group) =>
    group.entries.map((entry) => ({ ...entry, group: entry.group || group.name })),
  );
};
