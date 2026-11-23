import type { MarLinkTarget } from "@/types/link.types";

export const getLinkRel = (target?: MarLinkTarget): string | undefined =>
  target === "_blank" ? "noopener noreferrer" : undefined;
