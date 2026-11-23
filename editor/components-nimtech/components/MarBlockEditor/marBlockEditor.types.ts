export interface MarPageBlockRef {
  assetId: string;
  label?: string;
  icon?: string;
}

export interface MarPollRef {
  id: string;
}

export interface MarPollData {
  question: string;
  options: string[];
  votes: number[];
  userVoteIndex: number | null;
  status: string;
}

export interface MarCountdownLabels {
  days: string;
  hours: string;
  minutes: string;
  seconds: string;
}

export interface MarBlockAssetRef {
  id: string;
  url: string;
  name: string;
  mimeType?: string;
}

export type MarBlockLinkCard = "summary" | "summary_large_image" | "player";

export interface MarBlockLinkPreview {
  url: string;
  title?: string;
  description?: string;
  imageUrl?: string;
  favicon?: string;
  siteName?: string;
  card?: MarBlockLinkCard;
  type?: string;
  provider?: string;
  author?: string;
  embedUrl?: string;
}

export interface MarBlockMention {
  id: string;
  label: string;
  icon?: string;
  image?: string;
  type?: string;
  href?: string;
  preview?: string;
}

export interface MarBlockHeadingNumbering {
  /** Turns automatic heading numbering on. */
  enabled: boolean;
  /**
   * Heading level the numbering starts at.
   * @minimum 1
   * @maximum 6
   */
  startLevel: number;
}
