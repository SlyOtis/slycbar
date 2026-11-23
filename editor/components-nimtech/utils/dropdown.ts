import type { MarDropdownOption } from "@/types/dropdown.types";

export const resolveDropdownOptions = (
  options: Array<string | MarDropdownOption>,
): MarDropdownOption[] =>
  options.map((o) => (typeof o === "string" ? { label: o, value: o } : o));
