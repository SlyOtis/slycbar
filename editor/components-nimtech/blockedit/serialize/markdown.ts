import type { BlockId, Delta, MarBlock, MarBlockKind, MarDocument } from "../model/types";
import { deltaText, hasMark, isRefOp, isTextOp, linkOf, sliceDelta, textOp, refOp } from "../model/delta";
import { childIds } from "../model/tree";
import { isTextKind, makeBlock, makeDocument } from "../model/schema";
import { fitBlocks } from "../model/normalize";

type Blocks = Record<BlockId, MarBlock>;

const option = (block: MarBlock, key: string): string => String(block.options[key] ?? "");

const deltaOf = (block: MarBlock | undefined): Delta =>
  block && Array.isArray(block.content) ? block.content : [];

const inlineToMd = (content: Delta): string =>
  content
    .map((op) => {
      if (isRefOp(op)) {
        const attrs = op.attrs ?? {};
        if (op.insert.ref === "break") return "  \n";
        if (op.insert.ref === "image") {
          const img = `![${String(attrs.alt ?? "")}](${String(attrs.src ?? "")})`;
          const imgHref = String(attrs.href ?? "");
          return imgHref ? `[${img}](${imgHref})` : img;
        }
        const label = String(attrs.label ?? "");
        const href = String(attrs.href ?? "");
        const type = String(attrs.type ?? "");
        if (!href) return `@${label}`;
        return type ? `[@${label}](${href} "${type}")` : `[@${label}](${href})`;
      }
      if (!isTextOp(op)) return "";
      let text = op.insert;
      if (hasMark(op, "code")) text = "`" + text + "`";
      if (hasMark(op, "bold")) text = `**${text}**`;
      if (hasMark(op, "italic")) text = `*${text}*`;
      if (hasMark(op, "strike")) text = `~~${text}~~`;
      const link = linkOf(op);
      if (link) text = `[${text}](${link.href})`;
      return text;
    })
    .join("");

const childrenMd = (doc: MarDocument, block: MarBlock, depth: number): string =>
  childIds(block)
    .map((id) => blockToMd(doc, id, depth))
    .join("\n\n");

export const MARKDOWN_FENCED_BLOCKS = new Set([
  "titleBlock",
  "video",
  "audio",
  "pdf",
  "file",
  "bookmark",
  "linkPreview",
  "embed",
  "pageBlock",
  "map",
  "tableOfContents",
  "meetingNotes",
  "weather",
  "poll",
  "countdown",
  "imageGrid",
  "textInput",
  "choiceInput",
  "ratingInput",
  "toggle",
  "section",
  "template",
  "columnList",
  "column",
  "break",
]);

const fenceRun = (body: string): string => {
  let longest = 0;
  for (const run of body.match(/`+/g) ?? []) longest = Math.max(longest, run.length);
  return "`".repeat(Math.max(3, longest + 1));
};

const fenceMd = (doc: MarDocument, block: MarBlock, depth: number): string => {
  const body = isTextKind(block.kind)
    ? inlineToMd(deltaOf(block))
    : childrenMd(doc, block, depth);
  const keys = Object.keys(block.options);
  const info = keys.length ? ` ${JSON.stringify(block.options)}` : "";
  const ticks = fenceRun(body);
  return body
    ? `${ticks}${block.kind}${info}\n${body}\n${ticks}`
    : `${ticks}${block.kind}${info}\n${ticks}`;
};

const blockToMd = (doc: MarDocument, id: BlockId, depth = 0): string => {
  const block = doc.blocks[id];
  if (!block) return "";
  const pad = "  ".repeat(depth);
  switch (block.kind) {
    case "paragraph":
      return pad + inlineToMd(deltaOf(block));
    case "heading":
      return `${"#".repeat(Number(block.options.level) || 1)} ${inlineToMd(deltaOf(block))}`;
    case "blockquote":
      return childIds(block)
        .map((childId) => `> ${blockToMd(doc, childId, 0)}`)
        .join("\n");
    case "bulletList":
    case "orderedList":
    case "taskList":
      return childIds(block)
        .map((itemId, i) => {
          const item = doc.blocks[itemId];
          const marker =
            block.kind === "orderedList"
              ? `${i + 1}.`
              : block.kind === "taskList"
                ? item?.options.checked
                  ? "- [x]"
                  : "- [ ]"
                : "-";
          const inner = item
            ? childIds(item)
                .map((childId) => blockToMd(doc, childId, 0))
                .join("\n\n")
            : "";
          const [head = "", ...rest] = inner.split("\n");
          return [
            `${pad}${marker} ${head}`,
            ...rest.map((l) => (l.trim() ? `${pad}  ${l}` : "")),
          ].join("\n");
        })
        .join("\n");
    case "codeBlock": {
      const code = deltaText(deltaOf(block));
      const ticks = fenceRun(code);
      return `${ticks}${option(block, "language")}\n${code}\n${ticks}`;
    }
    case "horizontalRule":
      return "---";
    case "table":
      return childIds(block)
        .map((rowId, i) => {
          const row = doc.blocks[rowId];
          const cells = row
            ? childIds(row).map((cellId) => {
                const cell = doc.blocks[cellId];
                if (!cell) return "";
                return inlineToMd(
                  childIds(cell).flatMap((paraId) => deltaOf(doc.blocks[paraId])),
                );
              })
            : [];
          const line = `| ${cells.join(" | ")} |`;
          if (i === 0) {
            const sep = `| ${cells.map(() => "---").join(" | ")} |`;
            return `${line}\n${sep}`;
          }
          return line;
        })
        .join("\n");
    case "image":
      return `![](${option(block, "src")})`;
    case "html":
      return option(block, "html");
    case "callout": {
      const variant = (option(block, "variant") || "info").toUpperCase();
      const inner = childrenMd(doc, block, 0);
      return [`> [!${variant}]`, ...inner.split("\n").map((l) => `> ${l}`)].join("\n");
    }
    default:
      return MARKDOWN_FENCED_BLOCKS.has(block.kind)
        ? fenceMd(doc, block, depth)
        : childrenMd(doc, block, depth);
  }
};

export const marBlockRangeToMarkdown = (
  block: MarBlock,
  from: number,
  to: number,
): string => inlineToMd(sliceDelta(deltaOf(block), from, to));

export const marBlockToMarkdown = (block: MarBlock, doc: MarDocument): string =>
  blockToMd(doc, block.id);

export const marDocumentToMarkdown = (doc: MarDocument): string =>
  doc.root
    .map((id) => blockToMd(doc, id))
    .filter((s) => s !== "")
    .join("\n\n");

const inlineFromMd = (text: string): Delta => {
  const out: Delta = [];
  const re = /\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)]+)\)|!\[([^\]]*)\]\(([^)]+)\)|\*\*([^*]+)\*\*|\*([^*]+)\*|`([^`]+)`|~~([^~]+)~~|\[([^\]]+)\]\(([^)"]*?)(?:\s+"([^"]*)")?\)/g;
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(textOp(text.slice(last, m.index)));
    if (m[2] != null) out.push(refOp("image", { src: m[2], alt: m[1] ?? "", href: m[3] ?? "" }));
    else if (m[5] != null) out.push(refOp("image", { src: m[5], alt: m[4] ?? "", href: "" }));
    else if (m[6] != null) out.push(textOp(m[6], { bold: true }));
    else if (m[7] != null) out.push(textOp(m[7], { italic: true }));
    else if (m[8] != null) out.push(textOp(m[8], { code: true }));
    else if (m[9] != null) out.push(textOp(m[9], { strike: true }));
    else if (m[10] != null) {
      const target = m[11] ?? "";
      const title = m[12];
      if (m[10].startsWith("@"))
        out.push(
          refOp("mention", {
            id: "",
            label: m[10].slice(1),
            href: target,
            ...(title ? { type: title } : {}),
          }),
        );
      else out.push(textOp(m[10], { link: { href: target } }));
    }
    last = re.lastIndex;
  }
  if (last < text.length) out.push(textOp(text.slice(last)));
  return out;
};

const LIST_ITEM = /^(?:([-*])|(\d+)\.)[ \t]+(.*)$/;
const TASK_TEXT = /^\[([ xX])\][ \t]+(.*)$/;
const CONTINUATION = /^(?: {2,}|\t)/;

const listItemOf = (
  line: string,
): { kind: MarBlockKind; checked: boolean; text: string } | null => {
  const m = LIST_ITEM.exec(line);
  if (!m) return null;
  const text = m[3] ?? "";
  if (m[2] != null) return { kind: "orderedList", checked: false, text };
  const task = TASK_TEXT.exec(text);
  if (task) return { kind: "taskList", checked: task[1] !== " ", text: task[2] ?? "" };
  return { kind: "bulletList", checked: false, text };
};

const put = (blocks: Blocks, block: MarBlock): BlockId => {
  blocks[block.id] = block;
  return block.id;
};

const parseInto = (md: string, blocks: Blocks): BlockId[] => {
  const lines = md.replace(/\r\n/g, "\n").split("\n");
  const root: BlockId[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i] ?? "";
    if (!line.trim()) {
      i += 1;
      continue;
    }
    const fence = /^(`{3,})[ \t]*([^\s`]*)[ \t]*(.*)$/.exec(line);
    if (fence) {
      const ticks = fence[1] ?? "```";
      const name = fence[2] ?? "";
      const info = (fence[3] ?? "").trim();
      const closing = new RegExp(`^\`{${ticks.length},}\\s*$`);
      const body: string[] = [];
      i += 1;
      while (i < lines.length && !closing.test(lines[i] ?? "")) {
        body.push(lines[i] ?? "");
        i += 1;
      }
      i += 1;
      if (MARKDOWN_FENCED_BLOCKS.has(name)) {
        let options: Record<string, unknown> = {};
        if (info) {
          try {
            const parsed: unknown = JSON.parse(info);
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
              options = parsed as Record<string, unknown>;
            }
          } catch {
            options = {};
          }
        }
        const inner = body.join("\n").trim();
        root.push(
          put(
            blocks,
            isTextKind(name)
              ? makeBlock(name, options, inner ? inlineFromMd(inner) : [])
              : makeBlock(name, options, inner ? parseInto(inner, blocks) : []),
          ),
        );
        continue;
      }
      root.push(
        put(blocks, makeBlock("codeBlock", { language: name || "plaintext" }, [
          textOp(body.join("\n")),
        ])),
      );
      continue;
    }
    const heading = /^(#{1,6})\s+(.*)$/.exec(line);
    if (heading) {
      root.push(
        put(
          blocks,
          makeBlock("heading", { level: heading[1]?.length ?? 1 }, inlineFromMd(heading[2] ?? "")),
        ),
      );
      i += 1;
      continue;
    }
    if (/^(---|\*\*\*|___)\s*$/.test(line)) {
      root.push(put(blocks, makeBlock("horizontalRule")));
      i += 1;
      continue;
    }
    const image = /^!\[[^\]]*\]\(([^)]+)\)\s*$/.exec(line);
    if (image) {
      root.push(put(blocks, makeBlock("image", { src: image[1] })));
      i += 1;
      continue;
    }
    const table = /^\|(.+)\|\s*$/.exec(line);
    if (table && /^\|[\s:|-]+\|\s*$/.test(lines[i + 1] ?? "")) {
      const rows: BlockId[] = [];
      let header = true;
      while (i < lines.length && /^\|(.+)\|\s*$/.test(lines[i] ?? "")) {
        const cur = lines[i] ?? "";
        if (/^\|[\s:|-]+\|\s*$/.test(cur)) {
          i += 1;
          continue;
        }
        const cells = cur
          .slice(1, cur.lastIndexOf("|"))
          .split("|")
          .map((c) => c.trim())
          .map((c) => {
            const paragraph = put(blocks, makeBlock("paragraph", {}, inlineFromMd(c)));
            return put(
              blocks,
              makeBlock(header ? "tableHeader" : "tableCell", {}, [paragraph]),
            );
          });
        rows.push(put(blocks, makeBlock("tableRow", {}, cells)));
        header = false;
        i += 1;
      }
      root.push(put(blocks, makeBlock("table", {}, rows)));
      continue;
    }
    const opener = listItemOf(line);
    if (opener) {
      const kind = opener.kind;
      const chunks: { checked: boolean; lines: string[] }[] = [];
      while (i < lines.length) {
        const cur = lines[i] ?? "";
        const entry = listItemOf(cur);
        if (entry) {
          if (entry.kind !== kind) break;
          chunks.push({ checked: entry.checked, lines: [entry.text] });
          i += 1;
          continue;
        }
        if (CONTINUATION.test(cur)) {
          chunks[chunks.length - 1]?.lines.push(cur);
          i += 1;
          continue;
        }
        if (cur.trim()) break;
        let j = i;
        while (j < lines.length && !(lines[j] ?? "").trim()) j += 1;
        const next = lines[j] ?? "";
        const continues =
          j < lines.length && (listItemOf(next)?.kind === kind || CONTINUATION.test(next));
        if (!continues) break;
        chunks[chunks.length - 1]?.lines.push("");
        i += 1;
      }
      const items = chunks.map((chunk) => {
        const rest = chunk.lines.slice(1);
        const indent = rest
          .filter((l) => l.trim())
          .reduce((n, l) => Math.min(n, (/^[ \t]*/.exec(l)?.[0] ?? "").length), Number.MAX_SAFE_INTEGER);
        const body = [
          chunk.lines[0] ?? "",
          ...rest.map((l) => (l.trim() ? l.slice(indent) : "")),
        ].join("\n");
        const children = parseInto(body, blocks);
        if (!children.length) children.push(put(blocks, makeBlock("paragraph", {}, [])));
        return put(
          blocks,
          kind === "taskList"
            ? makeBlock("taskItem", { checked: chunk.checked }, children)
            : makeBlock("listItem", {}, children),
        );
      });
      root.push(put(blocks, makeBlock(kind, {}, items)));
      continue;
    }
    const quote = /^>\s?(.*)$/.exec(line);
    if (quote) {
      const quoteLines: string[] = [];
      while (i < lines.length) {
        const q = /^>\s?(.*)$/.exec(lines[i] ?? "");
        if (!q) break;
        quoteLines.push(q[1] ?? "");
        i += 1;
      }
      const callout = /^\[!(\w+)\]\s*$/.exec(quoteLines[0] ?? "");
      if (callout) {
        const variant = (callout[1] ?? "info").toLowerCase();
        const body = quoteLines.slice(1).filter((l) => l.trim());
        const paragraph = put(blocks, makeBlock("paragraph", {}, inlineFromMd(body.join(" "))));
        root.push(put(blocks, makeBlock("callout", { variant }, [paragraph])));
        continue;
      }
      const paragraph = put(blocks, makeBlock("paragraph", {}, inlineFromMd(quoteLines.join(" "))));
      root.push(put(blocks, makeBlock("blockquote", {}, [paragraph])));
      continue;
    }
    if (/^<\/?[a-zA-Z][\w-]*(\s|>|\/)/.test(line)) {
      const htmlLines: string[] = [];
      while (i < lines.length && (lines[i] ?? "").trim() !== "") {
        htmlLines.push(lines[i] ?? "");
        i += 1;
      }
      root.push(put(blocks, makeBlock("html", { html: htmlLines.join("\n") })));
      continue;
    }
    root.push(put(blocks, makeBlock("paragraph", {}, inlineFromMd(line))));
    i += 1;
  }
  return root;
};

export const marDocumentFromMarkdown = (md: string): MarDocument => {
  const blocks: Blocks = {};
  const root = parseInto(md, blocks);
  return makeDocument(root, blocks);
};

export const marBlocksFromMarkdown = (
  md: string,
  into?: MarBlockKind,
): MarDocument => fitBlocks(marDocumentFromMarkdown(md), into);
