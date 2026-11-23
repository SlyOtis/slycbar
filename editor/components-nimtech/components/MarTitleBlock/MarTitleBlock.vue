<script setup lang="ts">
import type { MarBlock } from "@/blockedit/model/types.ts";
import type { BlockEngine } from "@/blockedit/engine/BlockEngine.ts";
import { MarBlockEditText } from "@/blockedit/render/MarBlockEditText.ts";

defineProps<{
  /** Block model instance holding the title content. */
  block: MarBlock;
  /** Editor engine that owns the document and receives edits. */
  engine: BlockEngine;
}>();
</script>

<template>
  <MarBlockEditText :block="block" :engine="engine" />
</template>
