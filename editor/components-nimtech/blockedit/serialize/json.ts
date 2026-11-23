import type { MarContentType, MarDocument } from "../model/types";
import { makeDocument } from "../model/schema";
import { marDocumentFromHtml } from "./htmlParse";
import { marDocumentFromMarkdown } from "./markdown";

export const marDocumentFromJson = (value: string): MarDocument => {
  if (!value.trim()) return makeDocument();
  try {
    const parsed: unknown = JSON.parse(value);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as MarDocument;
    }
    return makeDocument();
  } catch {
    return makeDocument();
  }
};

export const marDocumentFromContent = (
  value: MarDocument | string,
  contentType: MarContentType = "json",
): MarDocument => {
  if (typeof value !== "string") return value;
  if (contentType === "markdown") return marDocumentFromMarkdown(value);
  if (contentType === "html") return marDocumentFromHtml(value);
  return marDocumentFromJson(value);
};

export const contentString = (value: MarDocument | string | null | undefined): string =>
  typeof value === "string" ? value : value ? JSON.stringify(value) : "";
