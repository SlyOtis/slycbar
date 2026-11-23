const SUBMENU_GAP = 4;

export const submenuPlacement = {
  side: "bottom",
  align: "start",
  offset: 0,
} as const;

export const submenuAnchor = (el: HTMLElement) => {
  const rect = el.getBoundingClientRect();
  return {
    left: rect.right + SUBMENU_GAP,
    right: rect.left - SUBMENU_GAP,
    top: rect.top,
    bottom: rect.top,
    width: rect.width,
    height: 0,
  };
};
