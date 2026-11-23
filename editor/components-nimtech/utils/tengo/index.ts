import {
  LRLanguage,
  LanguageSupport,
  indentNodeProp,
  continuedIndent,
  delimitedIndent,
  foldNodeProp,
  foldInside,
} from "@codemirror/language";
import {
  completeFromList,
  snippetCompletion,
  type Completion,
} from "@codemirror/autocomplete";
import { parser } from "./parser";

const snippets: Completion[] = [
  snippetCompletion("if ${condition} {\n\t${}\n}", { label: "if", detail: "block", type: "keyword" }),
  snippetCompletion("if ${condition} {\n\t${}\n} else {\n\t${}\n}", {
    label: "if",
    detail: "/ else block",
    type: "keyword",
  }),
  snippetCompletion("for ${item} in ${list} {\n\t${}\n}", { label: "for", detail: "in loop", type: "keyword" }),
  snippetCompletion("for ${i} := 0; ${i} < ${len}; ${i}++ {\n\t${}\n}", {
    label: "for",
    detail: "c-style loop",
    type: "keyword",
  }),
  snippetCompletion("func(${params}) {\n\t${}\n}", { label: "func", detail: "literal", type: "keyword" }),
];

export const tengoLanguage = LRLanguage.define({
  name: "tengo",
  parser: parser.configure({
    props: [
      indentNodeProp.add({
        IfStatement: continuedIndent({ except: /^\s*(\{|else\b)/ }),
        Block: delimitedIndent({ closing: "}" }),
        MapLiteral: delimitedIndent({ closing: "}" }),
        ArrayLiteral: delimitedIndent({ closing: "]" }),
        BlockComment: () => null,
      }),
      foldNodeProp.add({
        "Block MapLiteral ArrayLiteral": foldInside,
        BlockComment: (tree) => ({ from: tree.from + 2, to: tree.to - 2 }),
      }),
    ],
  }),
  languageData: {
    closeBrackets: { brackets: ["(", "[", "{", "'", '"', "`"] },
    commentTokens: { line: "//", block: { open: "/*", close: "*/" } },
    indentOnInput: /^\s*[}\]]$/,
  },
});

export const tengo = (): LanguageSupport =>
  new LanguageSupport(tengoLanguage, [
    tengoLanguage.data.of({ autocomplete: completeFromList(snippets) }),
  ]);
