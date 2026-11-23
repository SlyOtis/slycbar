export type MarMediaKind = "image" | "video" | "audio" | "pdf" | "file";

export type MarMediaAsset = {
  id: string;
  url: string;
  name: string;
  mimeType: string;
  size?: number;
  createdAt?: string;
  updatedAt?: string;
};
