import { StreamLanguage, StringStream, type StreamParser } from "@codemirror/language";
import { html } from "@codemirror/legacy-modes/mode/xml";

const KEYWORDS = new Set([
  "if", "else", "end", "range", "with", "define", "template", "block", "break", "continue",
  "nil", "true", "false", "and", "or", "not", "len", "index", "print", "printf", "println",
  "eq", "ne", "lt", "le", "gt", "ge", "html", "js", "urlquery", "slice", "call",
]);

interface GoTemplateState {
  html: unknown;
  action: boolean;
  comment: boolean;
}

const copyHtml = (state: unknown): unknown =>
  html.copyState ? html.copyState(state) : { ...(state as Record<string, unknown>) };

const action = (stream: StringStream, state: GoTemplateState): string | null => {
  if (state.comment) {
    if (stream.match(/^[\s\S]*?\*\/-?\}\}/)) {
      state.comment = false;
      state.action = false;
    } else {
      stream.skipToEnd();
    }
    return "comment";
  }
  if (stream.match("/*")) {
    state.comment = true;
    return "comment";
  }
  if (stream.match(/^-?\}\}/)) {
    state.action = false;
    return "bracket";
  }
  if (stream.eatSpace()) return null;
  if (stream.match(/^"(?:[^"\\]|\\.)*"/) || stream.match(/^`[^`]*`/) || stream.match(/^'(?:[^'\\]|\\.)*'/)) return "string";
  if (stream.match(/^-?\d+(?:\.\d+)?/)) return "number";
  if (stream.match(/^\$[A-Za-z_]\w*/) || stream.match("$")) return "variableName.special";
  if (stream.match(/^\.(?:[A-Za-z_]\w*)?(?:\.[A-Za-z_]\w*)*/)) return "propertyName";
  if (stream.match(/^[A-Za-z_]\w*/)) return KEYWORDS.has(stream.current()) ? "keyword" : "variableName";
  if (stream.match(/^(?::=|[|=(),])/)) return "operator";
  stream.next();
  return null;
};

export const gotemplate: StreamParser<GoTemplateState> = {
  name: "gotemplate",
  startState: (indentUnit) => ({ html: html.startState!(indentUnit), action: false, comment: false }),
  copyState: (state) => ({ html: copyHtml(state.html), action: state.action, comment: state.comment }),
  token(stream, state) {
    if (state.action || state.comment) return action(stream, state);
    if (stream.match(/^\{\{-?/)) {
      state.action = true;
      return "bracket";
    }
    const at = stream.string.indexOf("{{", stream.pos);
    const capped = at === -1 ? stream : new StringStream(stream.string.slice(0, at), (stream as unknown as { tabSize: number }).tabSize, stream.indentUnit);
    if (capped !== stream) {
      capped.pos = stream.pos;
      capped.start = stream.pos;
    }
    const style = html.token(capped, state.html);
    if (capped !== stream) stream.pos = capped.pos;
    if (stream.pos === stream.start) stream.next();
    return style;
  },
  blankLine: (state, indentUnit) => html.blankLine?.(state.html, indentUnit),
  languageData: { commentTokens: { block: { open: "{{/*", close: "*/}}" } } },
};

export const gotemplateLanguage = () => StreamLanguage.define(gotemplate);
