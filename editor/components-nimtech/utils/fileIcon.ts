import type { IconType } from "@/types/icon.types";
import { MAR_DRAWING_MIME } from "@/components/MarAssetPage/marAssetPage.types";

const codeExts = [
  "js", "ts", "tsx", "jsx", "json", "html", "css", "scss", "less", "go",
  "py", "rs", "java", "c", "cpp", "h", "rb", "php", "sh", "yml", "yaml",
  "xml", "vue", "sql", "toml",
];
const archiveExts = ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"];
const fontExts = ["ttf", "otf", "woff", "woff2", "eot"];
const imageExts = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "avif", "heic", "tiff"];
const videoExts = ["mp4", "mov", "webm", "mkv", "avi", "m4v"];
const audioExts = ["mp3", "wav", "ogg", "flac", "m4a", "aac"];

const extOf = (name: string): string => {
  const i = name.lastIndexOf(".");
  return i >= 0 ? name.slice(i + 1).toLowerCase() : "";
};

const iconFromExt = (ext: string): IconType => {
  if (ext === "pdf") return "file-pdf";
  if (ext === "svg") return "file-svg";
  if (imageExts.includes(ext)) return "file-image";
  if (videoExts.includes(ext)) return "file-video";
  if (audioExts.includes(ext)) return "file-audio";
  if (fontExts.includes(ext)) return "file-font";
  if (archiveExts.includes(ext)) return "file-archive";
  if (ext === "csv") return "file-csv";
  if (["xls", "xlsx", "ods"].includes(ext)) return "file-sheet";
  if (["ppt", "pptx", "odp"].includes(ext)) return "file-slides";
  if (["doc", "docx", "odt", "rtf"].includes(ext)) return "file-word";
  if (codeExts.includes(ext)) return "file-code";
  if (["md", "markdown"].includes(ext)) return "file-markdown";
  if (["txt", "log"].includes(ext)) return "file-text";
  return "file";
};

export const getFileIcon = (name: string, mimeType?: string): IconType => {
  const mime = mimeType ?? "";
  if (mime === "" || mime === "application/octet-stream" || mime === "text/plain") {
    const guess = iconFromExt(extOf(name));
    if (guess !== "file") return guess;
    return mime === "text/plain" ? "file-text" : "file";
  }
  if (mime === MAR_DRAWING_MIME) return "palette";
  if (mime === "application/pdf") return "file-pdf";
  if (mime === "image/svg+xml") return "file-svg";
  if (mime.startsWith("image/")) return "file-image";
  if (mime.startsWith("video/")) return "file-video";
  if (mime.startsWith("audio/")) return "file-audio";
  if (mime.startsWith("font/") || mime.includes("font")) return "file-font";
  if (mime.includes("zip") || mime.includes("compressed") || mime.includes("tar") || mime.includes("7z") || mime.includes("rar") || mime.includes("gzip")) return "file-archive";
  if (mime === "text/csv") return "file-csv";
  if (mime.includes("spreadsheet") || mime.includes("ms-excel")) return "file-sheet";
  if (mime.includes("presentation") || mime.includes("powerpoint")) return "file-slides";
  if (mime.includes("word") || mime === "application/msword" || mime.includes("opendocument.text")) return "file-word";
  if (mime === "application/json" || mime.includes("javascript") || mime.includes("ecmascript") || mime.includes("xml")) return "file-code";
  if (mime === "text/markdown" || mime === "text/x-markdown") return "file-markdown";
  if (mime.startsWith("text/")) return "file-text";
  return "file";
};
