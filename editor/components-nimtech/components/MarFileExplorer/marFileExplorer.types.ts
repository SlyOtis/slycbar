export interface MarFileItem {
  /** Unique identifier used for selection, presence, and rename tracking. */
  id: string;
  /** Display name, also the source of extension based icon detection and name grouping. */
  name: string;
  /** Whether the item is a folder or a file. */
  kind: "folder" | "file";
  /** Preformatted size label of the file. */
  size?: string;
  /** Download URL whose presence adds the Download entry to the item menu. */
  url?: string;
  /** Image URL replacing the type icon on the tile when set. */
  thumbnailUrl?: string | null;
  /** Mime type consulted first when picking the type icon. */
  mimeType?: string;
  /** Last modified timestamp used for the modified grouping buckets. */
  updatedAt?: string;
  /** Tag labels, up to three revealed as chips on hover with an overflow chip. */
  tags?: string[];
  /** Marks a root folder, which drops Move from its menu since a root has nowhere to go. */
  root?: boolean;
  /** Marks the item as reserved, adding the lock glyph beside the warning corner. */
  reserved?: boolean;
  /** Marks the item as the index of its folder, adding a star in the tile corner. */
  index?: boolean;
}

export interface MarFileMoveTarget {
  /** Identity of the destination folder. */
  id: string;
  /** Name shown in the destination list. */
  label: string;
  /** Path of the destination shown under the name. */
  path?: string;
}

export type MarFileGroupBy =
  | "none"
  | "kind"
  | "type"
  | "modified"
  | "name"
  | "tag";
