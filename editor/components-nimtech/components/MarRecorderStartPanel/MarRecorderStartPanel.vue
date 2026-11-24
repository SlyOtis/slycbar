<script setup lang="ts">
import { nextTick, onMounted, ref } from "vue";
import MarTextInput from "../MarTextInput";
import MarButton from "../MarButton";
import MarIcon from "../MarIcon";

const {
  defaultName = "",
  activeName = null,
} = defineProps<{
  /**
   * Prefills the name input and is the fallback when the trimmed input is empty.
   * @mock mockTitle
   */
  defaultName?: string;
  /**
   * Name of the recording already running; when set a warning states that starting will stop it.
   * @mock mockTitle
   */
  activeName?: string | null;
}>();

const emit = defineEmits<{ close: [result?: { name: string }] }>();

const name = ref(defaultName);
const inputEl = ref<{ $el?: HTMLElement } | null>(null);

onMounted(() => {
  nextTick(() => {
    const el = inputEl.value?.$el?.querySelector?.("input") as
      | HTMLInputElement
      | null;
    el?.focus();
    el?.select();
  });
});

const onStart = () => {
  emit("close", { name: name.value.trim() || defaultName });
};

const onKey = (e: KeyboardEvent) => {
  if (e.key === "Enter") onStart();
};
</script>

<template>
  <div class="mar-rec-start">
    <span class="mar-rec-start-title">New recording</span>
    <MarTextInput
      ref="inputEl"
      v-model="name"
      placeholder="Recording name"
      @keydown="onKey"
    />
    <div v-if="activeName" class="mar-rec-start-warn">
      <MarIcon icon="circle-error" class="mar-rec-start-icon" />
      <span>Starting will stop “{{ activeName }}”.</span>
    </div>
    <div class="mar-rec-start-actions">
      <MarButton
        label="Cancel"
        severity="secondary"
        @click="emit('close')"
      />
      <MarButton @click="onStart">
        <MarIcon icon="circle-fill" class="mar-rec-start-icon" />
        <span>Start</span>
      </MarButton>
    </div>
  </div>
</template>

<style scoped>
.mar-rec-start {
  display: flex;
  flex-direction: column;
  gap: 0.5em;
  width: 16em;
  padding: 0.75em;
}

.mar-rec-start-title {
  font-size: 0.8125em;
  font-weight: 600;
  color: var(--mar-text-color);
}

.mar-rec-start-warn {
  display: flex;
  align-items: center;
  gap: 0.5em;
  font-size: 0.75em;
  color: var(--mar-red-500);
}

.mar-rec-start-icon {
  font-size: 1.3333em;
}

.mar-rec-start-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.375em;
}
</style>
