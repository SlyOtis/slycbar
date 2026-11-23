let counter = 0;

export const generateBlockId = (): string => {
  counter += 1;
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return `b${counter.toString(36)}${Math.floor(performance.now()).toString(36)}`;
};
