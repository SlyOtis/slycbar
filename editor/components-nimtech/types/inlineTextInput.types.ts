export type MarInlineTextInputUnderline = "none" | "dashed" | "solid";

export type MarInlineTextInputType = "text" | "number" | "percent";

export type MarInlineTextInputNavigate = "prev" | "next" | "up" | "down";

export interface MarInlineTextInputKeyword {
  aliases: string[];
  key: string;
  separator?: string;
}

export interface MarInlineTextInputMatch {
  key: string;
  head: string;
  separator: string;
  term: string;
}

export interface MarInlineTextInputMatchRange {
  start: number;
  end: number;
  head: string;
  separator: string;
  term: string;
  key: string;
}
