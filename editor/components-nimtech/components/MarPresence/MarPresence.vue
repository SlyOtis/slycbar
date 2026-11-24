<script setup lang="ts">
import { computed } from "vue";
import { openModal, type ModalHandle } from "@/composables/useModals.ts";
import MarAvatar from "../MarAvatar";

export interface MarPresenceUser {
  /** Unique key for the avatar and the payload of the select emit. */
  id: string;
  /** Display name shown in the hover tooltip and used for the avatar fallback. */
  name: string;
  /** Avatar image URL passed to MarAvatar; null or absent falls back to the name rendering. */
  imageUrl?: string | null;
  /** Carried on the type but not rendered by the component. */
  color?: string;
  /** Marks the current user with a green ring and flags the tooltip name as you. */
  self?: boolean;
  /** Carried on the type but not rendered by the component. */
  location?: string | null;
}

const FIT_SLOTS = 12;

const {
  users,
  max = 5,
  fit = false,
} = defineProps<{
  /** Users to render as overlapping avatars in array order. */
  users: MarPresenceUser[];
  /**
   * Maximum number of avatars rendered; the rest collapse into an overflow counter. Ignored when fit is set.
   * @minimum 0
   */
  max?: number;
  /** Shows as many avatars as the width holds, up to twelve slots, following it through container queries, with the last slot reading the count of the rest. */
  fit?: boolean;
}>();

defineEmits<{
  select: [id: string];
}>();

const visible = computed(() => (fit ? users : users.slice(0, Math.min(users.length, max))));
const overflow = computed(() => (fit ? 0 : Math.max(0, users.length - visible.value.length)));

const cutAt = (index: number) => fit && index <= users.length - 2 && index < FIT_SLOTS;

let tip: ModalHandle | null = null;

const onEnter = (e: MouseEvent | FocusEvent, user: MarPresenceUser) => {
  tip = openModal({
    kind: "tooltip",
    text: user.self ? `${user.name} (you)` : user.name,
    anchor: e.currentTarget as HTMLElement,
    placement: { side: "top" },
  });
};

const onLeave = () => tip?.close();
</script>

<template>
  <div
    class="mar-presence"
    :class="{ 'mar-presence-fit': fit }"
    :style="fit ? { '--mar-presence-count': users.length } : undefined"
  >
    <template v-for="(user, index) in visible" :key="user.id">
      <span
        v-if="cutAt(index)"
        class="mar-presence-overflow mar-presence-cut"
        :class="`mar-presence-cut-${index}`"
        >+{{ users.length - index }}</span
      >
      <button
        type="button"
        class="mar-presence-item"
        :class="{ 'mar-presence-item-self': user.self }"
        @mouseenter="onEnter($event, user)"
        @mouseleave="onLeave"
        @focus="onEnter($event, user)"
        @blur="onLeave"
        @click="$emit('select', user.id)"
      >
        <MarAvatar
          :src="user.imageUrl ?? null"
          :label="user.name"
        />
      </button>
    </template>
    <span v-if="overflow > 0" class="mar-presence-overflow">+{{ overflow }}</span>
  </div>
</template>

<style scoped>
.mar-presence {
  display: inline-flex;
  align-items: center;
  isolation: isolate;
}

.mar-presence-fit {
  container: mar-presence / inline-size;
  contain-intrinsic-inline-size: calc(0.4375em + var(--mar-presence-count) * (0.91667em + 4px));
  max-inline-size: 100%;
  min-inline-size: 0;
  overflow-x: clip;
}

.mar-presence-item {
  position: relative;
  display: inline-flex;
  flex: 0 0 auto;
  border: 2px solid var(--mar-surface-0);
  border-radius: 50%;
  background: transparent;
  padding: 0;
  font-size: 0.8333em;
  cursor: pointer;
  transition: transform 0.15s ease;
}

.mar-presence-item-self {
  border-color: var(--mar-green-500);
  z-index: 1;
}

.mar-presence-item ~ .mar-presence-item {
  margin-left: -0.525em;
}

.mar-presence-item:hover {
  transform: translateY(-0.075em);
  z-index: 2;
}

.mar-presence-overflow {
  position: relative;
  z-index: 3;
  display: inline-flex;
  flex: 0 0 auto;
  align-items: center;
  justify-content: center;
  width: 2.6em;
  height: 2.6em;
  border-radius: 50%;
  background: var(--mar-surface-200);
  color: var(--mar-surface-700);
  font-size: 0.625em;
  font-weight: 700;
  border: 2px solid var(--mar-surface-0);
}

.mar-presence-item ~ .mar-presence-overflow {
  margin-left: -0.7em;
}

.mar-presence-cut {
  display: none;
  width: 2.1667em;
  height: 2.1667em;
}

@container mar-presence (width < calc(0.4375em + 2 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-0 {
    display: inline-flex;
  }

  .mar-presence-cut-0 ~ .mar-presence-item {
    display: none;
  }
}

@container mar-presence (width >= calc(0.4375em + 2 * (0.91667em + 4px) - 0.01em)) and (width < calc(0.4375em + 3 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-1 {
    display: inline-flex;
  }

  .mar-presence-cut-1 ~ .mar-presence-item {
    display: none;
  }
}

@container mar-presence (width >= calc(0.4375em + 3 * (0.91667em + 4px) - 0.01em)) and (width < calc(0.4375em + 4 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-2 {
    display: inline-flex;
  }

  .mar-presence-cut-2 ~ .mar-presence-item {
    display: none;
  }
}

@container mar-presence (width >= calc(0.4375em + 4 * (0.91667em + 4px) - 0.01em)) and (width < calc(0.4375em + 5 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-3 {
    display: inline-flex;
  }

  .mar-presence-cut-3 ~ .mar-presence-item {
    display: none;
  }
}

@container mar-presence (width >= calc(0.4375em + 5 * (0.91667em + 4px) - 0.01em)) and (width < calc(0.4375em + 6 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-4 {
    display: inline-flex;
  }

  .mar-presence-cut-4 ~ .mar-presence-item {
    display: none;
  }
}

@container mar-presence (width >= calc(0.4375em + 6 * (0.91667em + 4px) - 0.01em)) and (width < calc(0.4375em + 7 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-5 {
    display: inline-flex;
  }

  .mar-presence-cut-5 ~ .mar-presence-item {
    display: none;
  }
}

@container mar-presence (width >= calc(0.4375em + 7 * (0.91667em + 4px) - 0.01em)) and (width < calc(0.4375em + 8 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-6 {
    display: inline-flex;
  }

  .mar-presence-cut-6 ~ .mar-presence-item {
    display: none;
  }
}

@container mar-presence (width >= calc(0.4375em + 8 * (0.91667em + 4px) - 0.01em)) and (width < calc(0.4375em + 9 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-7 {
    display: inline-flex;
  }

  .mar-presence-cut-7 ~ .mar-presence-item {
    display: none;
  }
}

@container mar-presence (width >= calc(0.4375em + 9 * (0.91667em + 4px) - 0.01em)) and (width < calc(0.4375em + 10 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-8 {
    display: inline-flex;
  }

  .mar-presence-cut-8 ~ .mar-presence-item {
    display: none;
  }
}

@container mar-presence (width >= calc(0.4375em + 10 * (0.91667em + 4px) - 0.01em)) and (width < calc(0.4375em + 11 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-9 {
    display: inline-flex;
  }

  .mar-presence-cut-9 ~ .mar-presence-item {
    display: none;
  }
}

@container mar-presence (width >= calc(0.4375em + 11 * (0.91667em + 4px) - 0.01em)) and (width < calc(0.4375em + 12 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-10 {
    display: inline-flex;
  }

  .mar-presence-cut-10 ~ .mar-presence-item {
    display: none;
  }
}

@container mar-presence (width >= calc(0.4375em + 12 * (0.91667em + 4px) - 0.01em)) {
  .mar-presence-cut-11 {
    display: inline-flex;
  }

  .mar-presence-cut-11 ~ .mar-presence-item {
    display: none;
  }
}
</style>
