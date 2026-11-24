<script setup lang="ts">
defineProps<{
  /**
   * Recording name interpolated into the delete message.
   * @mock mockTitle
   */
  name?: string;
}>();

const emit = defineEmits<{ close: [deleted: boolean] }>();
</script>

<template>
  <div class="mar-rec-cancel">
    <p class="mar-rec-cancel-msg">
      Delete {{ name ?? "this recording" }}? This cannot be undone.
    </p>
    <div class="mar-rec-cancel-actions">
      <button type="button" class="mar-rec-cancel-keep" @click="emit('close', false)">
        Keep
      </button>
      <button type="button" class="mar-rec-cancel-delete" @click="emit('close', true)">
        Delete
      </button>
    </div>
  </div>
</template>

<style scoped>
.mar-rec-cancel {
  background: var(--mar-surface-0);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 10px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.16);
  padding: 1.25em;
  width: 18em;
  box-sizing: border-box;
  font-family: inherit;
}

.mar-rec-cancel-msg {
  margin: 0 0 1.5385em;
  font-size: 0.8125em;
  line-height: 1.5;
  color: var(--mar-text-color);
}

.mar-rec-cancel-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.625em;
}

.mar-rec-cancel-keep,
.mar-rec-cancel-delete {
  padding: 0.5833em 1.3333em;
  border-radius: 6px;
  font: inherit;
  font-size: 0.75em;
  font-weight: 600;
  white-space: nowrap;
  cursor: pointer;
  border: 1px solid var(--mar-content-border-color);
  background: var(--mar-surface-0);
  color: var(--mar-text-color);
  transition: background 0.15s ease, border-color 0.15s ease;
}

.mar-rec-cancel-keep:hover {
  background: var(--mar-surface-100);
}

.mar-rec-cancel-delete {
  border-color: transparent;
  background: var(--mar-red-500);
  color: var(--mar-overlay-color);
}

.mar-rec-cancel-delete:hover {
  background: var(--mar-red-600);
}
</style>
