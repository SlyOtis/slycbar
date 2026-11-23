<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from "vue";
import { EditorView, basicSetup } from "codemirror";
import { EditorState, Compartment } from "@codemirror/state";
import { keymap, tooltips } from "@codemirror/view";
import { indentWithTab } from "@codemirror/commands";
import { indentRange, syntaxHighlighting } from "@codemirror/language";
import { lintGutter, setDiagnostics } from "@codemirror/lint";
import { codeDiagnosticLines, codeDiagnostics, codeHighlight, codeLanguage, codeLineWrap, codeTheme } from "@/utils/code";
import { getTengoDiagnostics } from "@/utils/tengo/client";
import type { MarCodeAnswer, MarCodeDiagnostic } from "./marCode.types";

const {
  modelValue = "",
  language = "plaintext",
  readonly = false,
  showLineNumbers = true,
  minHeight = 0,
  maxHeight = 360,
  fitContent = false,
  fill = false,
  lineWrap = false,
  answer,
} = defineProps<{
  /** Document text bound with v-model. */
  modelValue?: string;
  /** Language name selecting the syntax highlighter. */
  language?: string;
  /** Makes the editor state read only. */
  readonly?: boolean;
  /** Shows the line number gutter. */
  showLineNumbers?: boolean;
  /**
   * Minimum scroller height, a number in pixels or a css length such as clamp(8rem, 30%, 20rem).
   * @minimum 0
   */
  minHeight?: number | string;
  /**
   * Maximum scroller height before internal scrolling, a number in pixels or a css length such as 60%.
   * @minimum 0
   */
  maxHeight?: number | string;
  /** Grows the editor with its content instead of scrolling. */
  fitContent?: boolean;
  /** Fills the height of the element holding it instead of stopping at maxHeight. */
  fill?: boolean;
  /** Wraps long lines instead of scrolling horizontally. */
  lineWrap?: boolean;
  /** Posts a request to the host's language server and resolves its response; with `tengo` it drives completion, hover, signature help and diagnostics as you type. */
  answer?: MarCodeAnswer;
}>();

/** Problems marked inline with an underline, a gutter marker and a hover tooltip, 1 based lines and columns; the language server writes it while `answer` is set. */
const diagnostics = defineModel<MarCodeDiagnostic[]>("diagnostics", { default: () => [] });

const emit = defineEmits<{
  "update:modelValue": [value: string];
  change: [value: string];
  cursor: [before: string];
}>();

const buildTheme = () =>
  codeTheme({ showLineNumbers, minHeight, maxHeight, fitContent, fill, lineWrap });

const host = ref<HTMLElement | null>(null);
let view: EditorView | null = null;
let internalValue = modelValue;

const langCompartment = new Compartment();
const readOnlyCompartment = new Compartment();
const themeCompartment = new Compartment();
const wrapCompartment = new Compartment();

const applyDiagnostics = (): void => {
  if (!view) return;
  view.dispatch(setDiagnostics(view.state, codeDiagnostics(view.state, diagnostics.value)));
};

let checkTimer = 0;
let checked = 0;

const check = (): void => {
  window.clearTimeout(checkTimer);
  if (!answer || language.toLowerCase() !== "tengo") return;
  const ask = answer;
  checkTimer = window.setTimeout(() => {
    if (!view) return;
    const code = view.state.doc.toString();
    const asked = ++checked;
    void getTengoDiagnostics(ask, code).then((list) => {
      if (asked === checked && view?.state.doc.toString() === code) diagnostics.value = list;
    });
  }, 300);
};

const insertAtCursor = (text: string): void => {
  if (!view || view.state.readOnly) return;
  view.dispatch(view.state.replaceSelection(text), { scrollIntoView: true, userEvent: "input.paste" });
  view.focus();
};

onMounted(() => {
  if (!host.value) return;
  const state = EditorState.create({
    doc: modelValue,
    extensions: [
      basicSetup,
      keymap.of([indentWithTab]),
      langCompartment.of(codeLanguage(language, answer)),
      syntaxHighlighting(codeHighlight),
      themeCompartment.of(buildTheme()),
      wrapCompartment.of(codeLineWrap(lineWrap)),
      readOnlyCompartment.of(EditorState.readOnly.of(readonly)),
      lintGutter(),
      codeDiagnosticLines,
      tooltips({ parent: document.body }),
      EditorView.updateListener.of((update) => {
        if (update.selectionSet || update.docChanged) {
          const head = update.state.selection.main.head;
          const line = update.state.doc.lineAt(head);
          emit("cursor", update.state.sliceDoc(line.from, head));
        }
        if (!update.docChanged) return;
        const v = update.state.doc.toString();
        internalValue = v;
        emit("update:modelValue", v);
        emit("change", v);
        check();
      }),
    ],
  });
  view = new EditorView({ state, parent: host.value });
  applyDiagnostics();
  check();
});

onBeforeUnmount(() => {
  window.clearTimeout(checkTimer);
  view?.destroy();
  view = null;
});

watch(
  () => modelValue,
  (val) => {
    if (!view || val === internalValue) return;
    internalValue = val;
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: val },
    });
    applyDiagnostics();
  },
);

watch(
  () => [language, answer] as const,
  () => {
    if (!view) return;
    view.dispatch({ effects: langCompartment.reconfigure(codeLanguage(language, answer)) });
    check();
  },
);

watch(
  () => readonly,
  (val) => {
    if (!view) return;
    view.dispatch({
      effects: readOnlyCompartment.reconfigure(EditorState.readOnly.of(val)),
    });
  },
);

watch(
  () => [showLineNumbers, minHeight, maxHeight, fitContent] as const,
  () => {
    if (!view) return;
    view.dispatch({ effects: themeCompartment.reconfigure(buildTheme()) });
  },
);

watch(
  () => lineWrap,
  () => {
    if (!view) return;
    view.dispatch({ effects: wrapCompartment.reconfigure(codeLineWrap(lineWrap)) });
  },
);

watch(diagnostics, applyDiagnostics, { deep: true });

const prettierParsers: Record<string, string> = {
  css: "css",
  scss: "scss",
  vue: "vue",
  html: "html",
  htm: "html",
  javascript: "babel",
  js: "babel",
  typescript: "typescript",
  ts: "typescript",
  json: "json",
};

const getPrettier = async (source: string, parser: string): Promise<string> => {
  const [prettier, postcss, html, babel, estree, typescript] = await Promise.all([
    import("prettier/standalone"),
    import("prettier/plugins/postcss"),
    import("prettier/plugins/html"),
    import("prettier/plugins/babel"),
    import("prettier/plugins/estree"),
    import("prettier/plugins/typescript"),
  ]);
  return prettier.format(source, {
    parser,
    plugins: [postcss, html, babel, estree, typescript],
    printWidth: 100,
    singleQuote: true,
    semi: false,
  });
};

const format = async (): Promise<boolean> => {
  if (!view || readonly) return false;
  const source = view.state.doc.toString();
  const parser = prettierParsers[(language || "").toLowerCase()];
  if (parser) {
    try {
      const formatted = await getPrettier(source, parser);
      if (formatted !== source) view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: formatted } });
      return true;
    } catch {
      return false;
    }
  }
  const changes = indentRange(view.state, 0, view.state.doc.length);
  if (!changes.empty) view.dispatch({ changes });
  return true;
};

defineExpose({ focus: () => view?.focus(), view: () => view, insertAtCursor, format });
</script>

<template>
  <div class="mar-code-block" :class="{ 'mar-code-block-fill': fill }">
    <div ref="host" class="mar-code-block-host"></div>
  </div>
</template>

<style scoped>
.mar-code-block {
  background: var(--mar-code-bg);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
  overflow: hidden;
}

.mar-code-block-fill {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
}

.mar-code-block-host {
  background: var(--mar-code-bg);
}

.mar-code-block-fill .mar-code-block-host {
  flex: 1;
  min-height: 0;
}

.mar-code-block :deep(.cm-editor) {
  background: var(--mar-code-bg);
}
</style>
