export const fileMatchesAccept = (file: File, accept: string): boolean =>
  accept.split(",").some((pattern) => {
    const p = pattern.trim();
    if (!p || p === "*" || p === "*/*") return true;
    if (p.endsWith("/*")) return file.type.startsWith(p.slice(0, -1));
    if (p.startsWith(".")) return file.name.toLowerCase().endsWith(p.toLowerCase());
    return file.type === p;
  });
