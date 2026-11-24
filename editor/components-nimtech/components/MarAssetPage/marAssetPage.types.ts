import type { MarImageFrame } from "../MarImage";
import type { MarFileGroupBy } from "../MarFileExplorer";

export type MarAssetKind = "folder" | "document" | "drawing" | "file";

export type MarAssetDocumentMode = "edit" | "read" | "paper";

export const MAR_DRAWING_MIME = "application/vnd.mar.paint+json";

export interface MarAsset {
  /** Unique identifier of the asset. */
  id: string;
  /** Display name of the asset. */
  name: string;
  /** Whether the asset is a folder, a document, a drawing, or a file. */
  kind: MarAssetKind;
  /** Id of the parent asset, null or absent for roots. */
  parentId?: string | null;
  /** The asset's own emoji, drawn beside the file type glyph that its mime type and name pick. */
  icon?: string;
  /** Banner image URL shown in the page header. */
  bannerUrl?: string | null;
  /** Framing of the banner per variant key, the header reads hero. */
  bannerFrames?: Record<string, MarImageFrame>;
  /** Mime type used to pick previews and detect markdown files. */
  mimeType?: string;
  /** Source URL for file previews, downloads, and markdown fetches. */
  url?: string;
  /** Source URL for the grid and row thumbnail, sized for a tile rather than full resolution. */
  thumbnailUrl?: string;
  /** Visibility label rendered as a tag. */
  visibility?: string;
  /** ISO date string used for sorting and the Updated column. */
  updatedAt?: string;
  /** Tag strings used for filtering and pill rendering. */
  tags?: string[];
  /** Marks a reserved asset, which the explorer flags with a lock and never offers Move for. */
  reserved?: boolean;
  /** Marks the index of its folder, which makes the page header carry its siblings as tabs. */
  index?: boolean;
  /** Marks an html page template, which opens in the code editor with a rendered preview instead of the block editor. */
  template?: boolean;
}

export interface MarAssetCreate {
  id: string;
  parentId: string | null;
  kind: MarAssetKind;
  name: string;
}

export interface MarAssetRename {
  id: string;
  name: string;
}

export interface MarAssetIndex {
  id: string;
  index: boolean;
}

export interface MarAssetMove {
  id: string;
  parentId: string | null;
}

export interface MarAssetView {
  /** Which folder browser renders, files, tree, or list. */
  folder: "file" | "tree" | "list";
  /** Column the folder children sort on. */
  sortKey: "name" | "updated";
  /** Direction the sort runs in. */
  sortDir: "asc" | "desc";
  /** Grouping applied to the file view tiles. */
  groupBy: MarFileGroupBy;
  /** Column keys hidden in the tree and list views. */
  hiddenColumns: string[];
  /** Minimum tile width in pixels used by the file view grid. */
  gridSize: number;
}

export type MarSearchSelect =
  | { kind: "tag"; value: string }
  | { kind: "creator"; value: string }
  | { kind: "name"; assetId: string }
  | { kind: "type"; value: string };
