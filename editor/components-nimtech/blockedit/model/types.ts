export type BlockId = string;

export type MarBlockKind = string;

export type BlockCategory = "layout" | "data" | "shape" | "template";

export type ContentShape = "delta" | "slot" | "none" | "either";

export type MarContentType = "json" | "html" | "markdown";

export type MarDocumentType = "document" | "template";

export type MarDocumentMode = "edit" | "read";

export type MarkType = "bold" | "italic" | "code" | "strike" | "link";

export interface LinkMark {
  href: string;
  target?: string;
  rel?: string;
}

export interface Marks {
  bold?: true;
  italic?: true;
  code?: true;
  strike?: true;
  link?: LinkMark;
}

export type RefName = "mention" | "image" | "break";

export interface TextOp {
  insert: string;
  marks?: Marks;
}

export interface RefOp {
  insert: { ref: RefName };
  attrs?: Record<string, unknown>;
}

export type DeltaOp = TextOp | RefOp;

export type Delta = DeltaOp[];

export interface BlockSlot {
  blocks: BlockId[];
}

export type BlockContent = Delta | BlockSlot | null;

export type EditMode = "open" | "lockBlock" | "lockContent" | "locked";

export type ReadMode = "document" | "section";

export type FontFamily =
  | "sans"
  | "serif"
  | "mono"
  | "rounded"
  | "inter"
  | "source-serif"
  | "jetbrains-mono"
  | "nunito";

export type FontSize = "sm" | "md" | "lg" | "xl";

export type LineHeight = "tight" | "normal" | "relaxed" | "loose";

export interface MarBlock {
  id: BlockId;
  type: BlockCategory;
  kind: MarBlockKind;
  content: BlockContent;
  options: Record<string, unknown>;
  attr: Record<string, unknown>;
  edit: EditMode;
  read: ReadMode;
  inherits: boolean;
  fontFamily: FontFamily;
  fontSize: FontSize;
  lineHeight: LineHeight;
}

export type PageNumberFormat = "n" | "n-of-m" | "page-n" | "page-n-of-m";

export type PageNumberPosition =
  | "header-left"
  | "header-center"
  | "header-right"
  | "footer-left"
  | "footer-center"
  | "footer-right";

export type PageBreakMode = "auto" | "always" | "avoid";

export interface PageNumbering {
  from: number;
  format: PageNumberFormat;
  position: PageNumberPosition;
  skipFirst: boolean;
}

export interface PageBreak {
  mode: PageBreakMode;
  avoidOrphans: boolean;
  beforeKinds: MarBlockKind[];
}

export interface DocumentPage {
  numbering: PageNumbering;
  break: PageBreak;
}

export interface MarDocument {
  id: string;
  type: MarDocumentType;
  width: string;
  page: DocumentPage;
  root: BlockId[];
  blocks: Record<BlockId, MarBlock>;
}

export interface TextPos {
  blockId: BlockId;
  offset: number;
}

export type Selection =
  | { kind: "text"; anchor: TextPos; head: TextPos }
  | { kind: "node"; blockId: BlockId }
  | { kind: "blocks"; ids: BlockId[] };

export interface BlockLoc {
  parentId: BlockId | null;
  index: number;
}
