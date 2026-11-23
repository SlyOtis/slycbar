import type { BlockEngine } from "./BlockEngine";
import type { MarContentType, MarDocumentType } from "../model/types";
import type { MarMediaAsset, MarMediaKind } from "../../types/media.types";

export interface SlashCommandCtx {
  engine: BlockEngine;
  blockId: string;
}

export interface SlashCommand {
  title: string;
  icon: string;
  description?: string;
  keywords?: string[];
  run: (ctx: SlashCommandCtx) => void;
}

export interface MentionItem {
  id: string;
  label: string;
  icon?: string;
  image?: string;
  type?: string;
  href?: string;
  preview?: string;
}

export interface PageRef {
  assetId: string;
  label?: string;
  icon?: string;
}

export interface AssetRef {
  id: string;
  url: string;
  name: string;
  mimeType?: string;
}

export interface PollRef {
  id: string;
}

export interface PollData {
  question: string;
  options: string[];
  votes: number[];
  userVoteIndex: number | null;
  status: string;
}

export interface CountdownLabels {
  days: string;
  hours: string;
  minutes: string;
  seconds: string;
}

export interface EditorConfig {
  contentType?: MarContentType;
  type?: MarDocumentType;
  placeholder?: string;
  onUpdate?: (value: string) => void;
  onCharDiff?: (delta: number) => void;
  slashCommands?: SlashCommand[];
  searchMentions?: (query: string) => Promise<MentionItem[]>;
  mentionTypes?: string[];
  searchPages?: (query: string) => Promise<PageRef[]>;
  createPageBlock?: (name: string) => Promise<PageRef | null>;
  requestMedia?: (
    kind: MarMediaKind,
    current?: string,
  ) => Promise<MarMediaAsset | null>;
  uploadFile?: (file: File, documentId?: string) => Promise<AssetRef>;
  openAsset?: (assetId: string) => void;
  resolveLinkPreview?: (url: string) => Promise<Record<string, unknown>>;
  audioSocketUrl?: string;
  createAudioSocket?: () => WebSocket;
  createPoll?: (question: string, options: string[]) => Promise<PollRef | null>;
  resolvePoll?: (pollId: string) => Promise<PollData>;
  votePoll?: (pollId: string, optionIndex: number) => Promise<PollData>;
  updatePoll?: (
    pollId: string,
    patch: { question?: string; options?: string[] },
  ) => Promise<void>;
  countdownLabels?: CountdownLabels;
  onOpenRecording?: (recId: string) => void;
  onOpenMention?: (mention: { id: string; type: string; href: string }) => void;
  onOpenPageBlock?: (assetId: string) => void;
  onRenamePageBlock?: (assetId: string, label: string) => void;
  onCreatePageBlock?: (assetId: string) => void;
}
