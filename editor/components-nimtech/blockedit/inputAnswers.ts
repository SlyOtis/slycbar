import { inject, type InjectionKey } from "vue";

export interface MarInputAnswers {
  values: Record<string, string>;
  set: (key: string, value: string) => void;
}

export const MAR_INPUT_ANSWERS: InjectionKey<MarInputAnswers> =
  Symbol("marInputAnswers");

export const useMarInputAnswers = (): MarInputAnswers | null =>
  inject(MAR_INPUT_ANSWERS, null);

export const marInputKey = (attrs: {
  key?: string;
  label?: string;
}): string => {
  const key = String(attrs.key ?? "").trim();
  if (key) return key;
  return String(attrs.label ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
};
