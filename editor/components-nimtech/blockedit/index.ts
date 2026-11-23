import { createBlockEngine } from "./engine/BlockEngine";
import type { EditorConfig } from "./engine/config";
import type { MarDocument } from "./model/types";
import { registerDefaultViews } from "./render/views/defaults";
import { marBlockEditorDefaultCommands } from "./commands/slashCommands";
import "./blockedit.css";

export interface CreateBlockEditorOptions extends EditorConfig {
  content?: MarDocument | string;
  editable?: boolean;
}

export const createBlockEditor = (opts: CreateBlockEditorOptions = {}) => {
  registerDefaultViews();
  const { content, editable, ...config } = opts;
  if (!config.slashCommands) config.slashCommands = marBlockEditorDefaultCommands;
  return createBlockEngine(content ?? "", config, editable ?? true);
};

export { BlockTree, BlockNode } from "./render/BlockTree";
export { registerBlockView, resolveBlockView } from "./render/views/registry";
export { marDocumentFromHtml, marBlocksFromHtml } from "./serialize/htmlParse";
export { marDocumentToHtml } from "./serialize/htmlSerialize";
export { marDocumentToEmailHtml, type MarEmailOptions } from "./serialize/emailSerialize";
export {
  marDocumentFromMarkdown,
  marDocumentToMarkdown,
  marBlocksFromMarkdown,
  marBlockToMarkdown,
} from "./serialize/markdown";
export { schema, makeBlock, makeDocument } from "./model/schema";
export { marBlockEditorDefaultCommands, marBlockEditorDefaultGroups } from "./commands/slashCommands";
export { contentString } from "./serialize/json";
export type { BlockEngine, CollabBinding } from "./engine/BlockEngine";
export { createYBinding, type YBinding, type YBindingOptions } from "./collab/yBinding";
export type { CollabProvider, CollabProviderEvent, CollabUser } from "./collab/provider";
export { LOCAL_ORIGIN, docToY, yToDoc } from "./collab/yDoc";
export { normalize, fitBlocks } from "./model/normalize";
export { remotePeers, type RemotePeer, type RemoteSelection } from "./collab/awareness";
export type {
  EditorConfig,
  SlashCommand,
  SlashCommandCtx,
  MentionItem,
  PageRef,
  AssetRef,
} from "./engine/config";
export type {
  MarBlock,
  MarBlockKind,
  MarContentType,
  MarDocument,
  MarDocumentType,
  MarDocumentMode,
  BlockCategory,
  ContentShape,
  Delta,
  DeltaOp,
  Marks,
  MarkType,
  EditMode,
  ReadMode,
  Selection,
  TextPos,
  BlockId,
} from "./model/types";
