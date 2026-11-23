import type { MarFuncEntry } from "../MarFuncList/marFuncList.types";

export interface MarCodeDiagnostic {
  /** Line the mark starts on, 1 based. */
  line: number;
  /** Column the mark starts at, 1 based. */
  column: number;
  /** Text shown in the hover tooltip and the gutter. */
  message: string;
  /** Colour of the underline and the gutter marker. */
  severity?: "error" | "warning";
  /** Line the mark ends on, 1 based; the start line when left out. */
  endLine?: number;
  /** Column the mark ends before, 1 based; the end of the word at the start when left out. */
  endColumn?: number;
}

export interface MarCodePosition {
  /** Line, 0 based. */
  line: number;
  /** Column in UTF-16 code units, 0 based. */
  character: number;
}

export interface MarCodeRange {
  /** Where the range starts. */
  start: MarCodePosition;
  /** Where the range ends, exclusive. */
  end: MarCodePosition;
}

export interface MarCodeMarkup {
  /** `markdown` or `plaintext`. */
  kind: string;
  /** The text, a fenced code block followed by prose for markdown. */
  value: string;
}

export interface MarCodeCompletionItem {
  /** Name offered and matched against what is typed. */
  label: string;
  /** Language server kind: 2 method, 3 function, 5 field, 6 variable, 9 module, 14 keyword, 21 constant. */
  kind: number;
  /** Signature shown beside the label. */
  detail?: string;
  /** Text shown in the info panel of the option. */
  documentation?: MarCodeMarkup;
  /** Text written in place of the label. */
  insertText?: string;
  /** 2 when `insertText` is a snippet with `${1:name}` fields. */
  insertTextFormat?: number;
  /** Order the server ranks the item in. */
  sortText?: string;
}

export interface MarCodeHover {
  /** What the name under the pointer is. */
  contents: MarCodeMarkup;
  /** The name the hover is about. */
  range?: MarCodeRange;
}

export interface MarCodeSignature {
  /** The whole signature. */
  label: string;
  /** What the call does. */
  documentation?: MarCodeMarkup;
  /** Each parameter as it reads in the label. */
  parameters: { label: string }[];
}

export interface MarCodeSignatureHelp {
  /** The signatures of the call around the cursor. */
  signatures: MarCodeSignature[];
  /** Index of the signature shown. */
  activeSignature?: number;
  /** Index of the parameter the cursor is in. */
  activeParameter?: number;
}

export interface MarCodeServerDiagnostic {
  /** Where the problem is. */
  range: MarCodeRange;
  /** 1 error, 2 warning. */
  severity: number;
  /** Name of the checker. */
  source?: string;
  /** What is wrong. */
  message: string;
}

export interface MarCodeRequest {
  /** `textDocument/completion`, `textDocument/hover`, `textDocument/signatureHelp`, `textDocument/diagnostic` or `tengo/reference`. */
  method: string;
  /** The whole document. */
  code: string;
  /** The cursor the request is about. */
  position: MarCodePosition;
}

export interface MarCodeResponse {
  /** Completion items. */
  items?: MarCodeCompletionItem[];
  /** Hover for the name at the position. */
  hover?: MarCodeHover | null;
  /** Signature of the call around the position. */
  signature?: MarCodeSignatureHelp | null;
  /** Problems in the document. */
  diagnostics?: MarCodeServerDiagnostic[];
  /** The catalogue of what the language offers, in groups of `MarFuncEntry` shaped entries. */
  reference?: MarCodeReference | null;
}

/** Posts a request to the host's language server and resolves its response. */
export type MarCodeAnswer = (request: MarCodeRequest) => Promise<MarCodeResponse>;

export interface MarCodeReference {
  /** Groups in the order the server lists them. */
  groups: { name: string; entries: MarFuncEntry[] }[];
}
