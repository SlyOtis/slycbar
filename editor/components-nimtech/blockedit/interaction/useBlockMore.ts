import { closeModal, openModal } from "@/composables/useModals";
import MarBlockMore from "@/components/MarBlockMore";
import type { BlockEngine } from "../engine/BlockEngine";
import type { BlockId } from "../model/types";
import { getBlockOptions } from "./blockOptions";

const MORE_ID = "be-block-more";

export const openBlockMenu = (
  engine: BlockEngine,
  blockIds: BlockId[],
  anchorEl: HTMLElement,
  onClose?: () => void,
): void => {
  const options = getBlockOptions(engine, blockIds);
  if (!options.length) return;
  void openModal({
    id: MORE_ID,
    kind: "dropdown",
    component: MarBlockMore,
    anchor: { target: anchorEl },
    placement: { side: "bottom", align: "start", offset: 4 },
    backdrop: "invisible",
    dismissOnEscape: false,
    props: { options, count: blockIds.length },
    on: {
      close: () => {
        closeModal(MORE_ID);
        onClose?.();
      },
    },
  }).then(() => onClose?.());
};
