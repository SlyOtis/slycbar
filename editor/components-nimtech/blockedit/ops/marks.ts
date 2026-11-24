import type { LinkMark, MarDocument, MarkType, Selection } from "../model/types";
import { hasMark, isTextOp, mergeDelta, splitDelta, withMark, withoutMark } from "../model/delta";
import { contentOf, setBlockContent } from "./text";

export const toggleMark = (
  doc: MarDocument,
  blockId: string,
  from: number,
  to: number,
  type: MarkType,
  link?: LinkMark,
): { doc: MarDocument; selection: Selection } => {
  const [head, tail] = splitDelta(contentOf(doc, blockId), to);
  const [left, mid] = splitDelta(head, from);
  const textOps = mid.filter(isTextOp);
  const allHave = textOps.length > 0 && textOps.every((op) => hasMark(op, type));
  const marked = mid.map((op) =>
    isTextOp(op) ? (allHave ? withoutMark(op, type) : withMark(op, type, link)) : op,
  );
  return {
    ...setBlockContent(doc, blockId, mergeDelta([...left, ...marked, ...tail])),
    selection: {
      kind: "text",
      anchor: { blockId, offset: from },
      head: { blockId, offset: to },
    },
  };
};
