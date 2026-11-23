import type { Delta, DeltaOp, LinkMark, Marks, MarkType, RefName, RefOp, TextOp } from "./types";

export const isTextOp = (op: DeltaOp): op is TextOp => typeof op.insert === "string";

export const isRefOp = (op: DeltaOp): op is RefOp => typeof op.insert !== "string";

export const refOf = (op: DeltaOp): RefName | null =>
  isTextOp(op) ? null : op.insert.ref;

export const opLength = (op: DeltaOp): number =>
  isTextOp(op) ? op.insert.length : 1;

export const deltaLength = (delta: Delta): number =>
  delta.reduce((total, op) => total + opLength(op), 0);

export const deltaText = (delta: Delta): string =>
  delta.map((op) => (isTextOp(op) ? op.insert : "")).join("");

export const hasMark = (op: DeltaOp, type: MarkType): boolean =>
  isTextOp(op) && op.marks?.[type] !== undefined;

export const linkOf = (op: DeltaOp): LinkMark | null =>
  isTextOp(op) ? op.marks?.link ?? null : null;

export const withMark = (op: TextOp, type: MarkType, link?: LinkMark): TextOp => {
  const marks: Marks = { ...op.marks };
  if (type === "link") marks.link = link ?? { href: "" };
  else marks[type] = true;
  return { ...op, marks };
};

export const withoutMark = (op: TextOp, type: MarkType): TextOp => {
  const marks: Marks = { ...op.marks };
  delete marks[type];
  return Object.keys(marks).length ? { ...op, marks } : { insert: op.insert };
};

export const sameMarks = (a: DeltaOp, b: DeltaOp): boolean =>
  JSON.stringify(isTextOp(a) ? a.marks ?? null : null) ===
  JSON.stringify(isTextOp(b) ? b.marks ?? null : null);

export const markNames = (op: DeltaOp): MarkType[] =>
  isTextOp(op) && op.marks
    ? (Object.keys(op.marks).filter((k) => op.marks?.[k as MarkType] !== undefined) as MarkType[])
    : [];

export const textOp = (insert: string, marks?: Marks): TextOp =>
  marks && Object.keys(marks).length ? { insert, marks } : { insert };

export const refOp = (ref: RefName, attrs?: Record<string, unknown>): RefOp =>
  attrs && Object.keys(attrs).length ? { insert: { ref }, attrs } : { insert: { ref } };

export const mergeDelta = (delta: Delta): Delta => {
  const out: Delta = [];
  for (const op of delta) {
    const last = out[out.length - 1];
    if (isTextOp(op) && !op.insert) continue;
    if (last && isTextOp(last) && isTextOp(op) && sameMarks(last, op)) {
      out[out.length - 1] = { ...last, insert: last.insert + op.insert };
      continue;
    }
    out.push(op);
  }
  return out;
};

export const splitDelta = (delta: Delta, offset: number): [Delta, Delta] => {
  const left: Delta = [];
  const right: Delta = [];
  let at = 0;
  for (const op of delta) {
    const len = opLength(op);
    if (at + len <= offset) left.push(op);
    else if (at >= offset) right.push(op);
    else if (isTextOp(op)) {
      const cut = offset - at;
      left.push(textOp(op.insert.slice(0, cut), op.marks));
      right.push(textOp(op.insert.slice(cut), op.marks));
    } else right.push(op);
    at += len;
  }
  return [left, right];
};

export const sliceDelta = (delta: Delta, from: number, to: number): Delta => {
  const [head] = splitDelta(delta, to);
  const [, mid] = splitDelta(head, from);
  return mid;
};
