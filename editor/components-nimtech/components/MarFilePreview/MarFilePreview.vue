<script setup lang="ts">
import {
  computed,
  defineAsyncComponent,
  nextTick,
  onBeforeUnmount,
  ref,
  watch,
} from "vue";
import MarIcon from "../MarIcon";
import { formatDate, useDateFormat } from "@/composables/useDateFormat";
import MarImageControls from "../MarImageControls";
import MarVideoControls from "../MarVideoControls";
import MarAudioControls from "../MarAudioControls";
import MarCode from "../MarCode";
import MarBlockReader from "../MarBlockReader";
import MarLoadingSpinner from "../MarLoadingSpinner";
import MarImage from "../MarImage";

const VueOfficePptx = defineAsyncComponent(() => import("@vue-office/pptx"));
const VueOfficePdf = defineAsyncComponent(() => import("@vue-office/pdf"));

const {
  url,
  mimeType,
  name = "",
  uploading = false,
} = defineProps<{
  /** Fetchable file URL to preview, resetting all preview state when it changes. */
  url: string;
  /** Primary signal for picking the preview kind. */
  mimeType: string;
  /**
   * File name used for extension based kind detection, code language choice, and fallback labels.
   * @mock mockTitle
   */
  name?: string;
  /** Blurs the preview and overlays a spinner while an upload completes. */
  uploading?: boolean;
}>();

const emit = defineEmits<{
  "preview-state": [{ kind: string; sheetNames: string[]; activeSheet: number; scale: number }];
}>();

type PreviewKind =
  | "image"
  | "video"
  | "audio"
  | "pdf"
  | "word"
  | "sheet"
  | "csv"
  | "pptx"
  | "code"
  | "font"
  | "html"
  | "gsuite"
  | "decoded"
  | "zip"
  | "ipynb"
  | "ics"
  | "parquet"
  | "threed"
  | "epub"
  | "other";

interface SheetData {
  name: string;
  rows: unknown[][];
}

interface NotebookCell {
  type: "markdown" | "code";
  source: string;
  outputs: string[];
}

interface IcsEvent {
  summary: string;
  start: string;
  end: string;
  location: string;
}

const extOf = (n: string): string => {
  const i = n.lastIndexOf(".");
  return i >= 0 ? n.slice(i + 1).toLowerCase() : "";
};

const codeLangByExt: Record<string, string> = {
  js: "javascript", jsx: "javascript", mjs: "javascript", cjs: "javascript",
  ts: "typescript", tsx: "typescript", vue: "javascript",
  json: "json", py: "python", go: "go", rs: "rust",
  sh: "bash", bash: "bash", zsh: "bash",
  cs: "csharp", yml: "yaml", yaml: "yaml",
  css: "css", scss: "css", less: "css", sql: "sql",
  md: "markdown", markdown: "markdown", xml: "xml",
  toml: "plaintext", ini: "plaintext", conf: "plaintext", cfg: "plaintext",
  env: "plaintext", diff: "plaintext", patch: "plaintext",
  srt: "plaintext", vtt: "plaintext", properties: "plaintext", log: "plaintext",
};

const threedExts = ["stl", "obj", "gltf", "glb", "3mf", "ply"];

const kind = computed<PreviewKind>(() => {
  const m = mimeType ?? "";
  const ext = extOf(name);
  if (m.startsWith("application/vnd.google-apps")) return "gsuite";
  if (m === "application/epub+zip" || ext === "epub") return "epub";
  if (m === "image/heic" || m === "image/heif" || ["heic", "heif"].includes(ext)) return "decoded";
  if (m === "image/tiff" || ["tif", "tiff"].includes(ext)) return "decoded";
  if (m === "image/vnd.adobe.photoshop" || ext === "psd") return "decoded";
  if (m.startsWith("image/")) return "image";
  if (m.startsWith("video/")) return "video";
  if (m.startsWith("audio/")) return "audio";
  if (m === "application/pdf" || ext === "pdf") return "pdf";
  if (m === "text/html" || ["html", "htm"].includes(ext)) return "html";
  if (ext === "ipynb") return "ipynb";
  if (m === "text/calendar" || ext === "ics") return "ics";
  if (ext === "parquet") return "parquet";
  if (m.startsWith("model/") || threedExts.includes(ext)) return "threed";
  if (m === "application/zip" || m === "application/x-zip-compressed" || ext === "zip") return "zip";
  if (m.includes("wordprocessing") || m === "application/msword" || ["doc", "docx"].includes(ext)) return "word";
  if (m === "text/csv" || ext === "csv") return "csv";
  if (m.includes("spreadsheet") || m === "application/vnd.ms-excel" || ["xls", "xlsx", "ods"].includes(ext)) return "sheet";
  if (m.includes("presentation") || m === "application/vnd.ms-powerpoint" || ["ppt", "pptx", "odp"].includes(ext)) return "pptx";
  if (m.startsWith("font/") || m.includes("font") || ["ttf", "otf", "woff", "woff2", "eot"].includes(ext)) return "font";
  if (
    m.startsWith("text/") ||
    m === "application/json" ||
    m.includes("javascript") ||
    m.includes("ecmascript") ||
    m.includes("xml") ||
    ext in codeLangByExt ||
    ["txt", "log"].includes(ext)
  ) {
    return "code";
  }
  return "other";
});

const codeLang = computed(() => codeLangByExt[extOf(name)] ?? "plaintext");

const pdfSrc = computed(() =>
  url ? `${url}#toolbar=0&navpanes=0&scrollbar=0` : "",
);

const gsuiteSrc = computed(() => {
  if (!url) return "";
  if (/\/preview(\?|$)/.test(url)) return url;
  if (/\/(edit|view)(\?|$)/.test(url)) return url.replace(/\/(edit|view)(\?|$)/, "/preview$2");
  return url.includes("docs.google.com") ? `${url.replace(/\/$/, "")}/preview` : url;
});

const audioPeaks = Array.from({ length: 64 }, () => 0.5);

const audioEl = ref<HTMLAudioElement | null>(null);
const playing = ref(false);
const currentTime = ref(0);
const duration = ref(0);
const volume = ref(1);

const progress = computed(() =>
  duration.value ? currentTime.value / duration.value : 0,
);

const onAudioTime = () => {
  const a = audioEl.value;
  if (a) currentTime.value = a.currentTime;
};

const onAudioMeta = () => {
  const a = audioEl.value;
  if (a) duration.value = a.duration;
};

const toggleAudio = () => {
  const a = audioEl.value;
  if (!a) return;
  if (a.paused) a.play();
  else a.pause();
};

const skipAudio = (delta: number) => {
  const a = audioEl.value;
  if (!a) return;
  a.currentTime = Math.max(0, Math.min(duration.value, a.currentTime + delta));
};

const seekAudio = (ratio: number) => {
  const a = audioEl.value;
  if (a && duration.value) a.currentTime = ratio * duration.value;
};

const setVolume = (v: number) => {
  volume.value = v;
  if (audioEl.value) audioEl.value.volume = v;
};

const status = ref<"idle" | "loading" | "ready" | "error">("idle");
const error = ref("");
const docHtml = ref("");
const codeText = ref("");
const sheets = ref<SheetData[]>([]);
const activeSheet = ref(0);
const fontFamily = ref("");
const decodedSrc = ref("");
const zipEntries = ref<string[]>([]);
const notebook = ref<NotebookCell[]>([]);
const icsEvents = ref<IcsEvent[]>([]);

const dateFormat = useDateFormat();

const icsStamp = (date: Date): string =>
  `${formatDate(date, dateFormat.value.date, dateFormat.value)} ${formatDate(date, dateFormat.value.time, dateFormat.value)}`;
const scale = ref(1);
let fontCounter = 0;

const threedHost = ref<HTMLElement | null>(null);
const epubHost = ref<HTMLElement | null>(null);
let cleanupViewer: (() => void) | null = null;

const activeSheetData = computed<SheetData | null>(
  () => sheets.value[activeSheet.value] ?? null,
);

const cellText = (cell: unknown): string =>
  cell === null || cell === undefined ? "" : String(cell);

const rowsFromObjects = (objects: Record<string, unknown>[]): unknown[][] => {
  if (!objects.length) return [];
  const keys = Object.keys(objects[0] ?? {});
  return [keys, ...objects.map((o) => keys.map((k) => o[k]))];
};

const canvasToObjectUrl = (canvas: HTMLCanvasElement): Promise<string> =>
  new Promise((resolve) => {
    canvas.toBlob((blob) => resolve(blob ? URL.createObjectURL(blob) : ""));
  });

let objectUrl = "";
let addedFont: FontFace | null = null;

const cleanupResources = () => {
  if (objectUrl) {
    URL.revokeObjectURL(objectUrl);
    objectUrl = "";
  }
  if (addedFont) {
    document.fonts.delete(addedFont);
    addedFont = null;
  }
};

const teardownViewer = () => {
  if (cleanupViewer) {
    cleanupViewer();
    cleanupViewer = null;
  }
  cleanupResources();
};

const read = async (target: string): Promise<Response> => {
  const res = await fetch(target);
  if (!res.ok) throw new Error(`Could not read the file, the server answered ${res.status}`);
  return res;
};

const loadThreed = async (target: string) => {
  const THREE = await import("three");
  const res = await read(target);
  const buffer = await res.arrayBuffer();
  await nextTick();
  const host = threedHost.value;
  if (!host || target !== url) return;
  const ext = extOf(name);
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x111111);
  const w = host.clientWidth || 640;
  const h = host.clientHeight || 480;
  const camera = new THREE.PerspectiveCamera(50, w / h, 0.1, 5000);
  camera.position.set(0, 0, 100);
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setSize(w, h);
  renderer.setPixelRatio(window.devicePixelRatio);
  host.appendChild(renderer.domElement);
  scene.add(new THREE.AmbientLight(0xffffff, 0.8));
  const dir = new THREE.DirectionalLight(0xffffff, 1);
  dir.position.set(1, 1, 1);
  scene.add(dir);

  const fit = (object: import("three").Object3D) => {
    const box = new THREE.Box3().setFromObject(object);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    object.position.sub(center);
    const maxDim = Math.max(size.x, size.y, size.z) || 1;
    camera.position.set(0, 0, maxDim * 2.2);
    camera.near = maxDim / 100;
    camera.far = maxDim * 100;
    camera.updateProjectionMatrix();
    scene.add(object);
  };

  if (ext === "stl") {
    const { STLLoader } = await import("three/examples/jsm/loaders/STLLoader.js");
    const geo = new STLLoader().parse(buffer);
    const mesh = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ color: 0xd97757 }));
    fit(mesh);
  } else if (ext === "obj") {
    const { OBJLoader } = await import("three/examples/jsm/loaders/OBJLoader.js");
    fit(new OBJLoader().parse(new TextDecoder().decode(buffer)));
  } else {
    const { GLTFLoader } = await import("three/examples/jsm/loaders/GLTFLoader.js");
    const gltf = await new GLTFLoader().parseAsync(buffer, "");
    fit(gltf.scene);
  }

  if (target !== url) {
    renderer.forceContextLoss();
    renderer.dispose();
    renderer.domElement.remove();
    return;
  }

  const { OrbitControls } = await import("three/examples/jsm/controls/OrbitControls.js");
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  let raf = 0;
  const tick = () => {
    raf = requestAnimationFrame(tick);
    controls.update();
    renderer.render(scene, camera);
  };
  tick();
  const resizeObserver = new ResizeObserver(() => {
    const nw = host.clientWidth;
    const nh = host.clientHeight;
    if (nw === 0 || nh === 0) return;
    camera.aspect = nw / nh;
    camera.updateProjectionMatrix();
    renderer.setSize(nw, nh);
  });
  resizeObserver.observe(host);
  cleanupViewer = () => {
    cancelAnimationFrame(raf);
    resizeObserver.disconnect();
    controls.dispose();
    scene.traverse((obj) => {
      const mesh = obj as import("three").Mesh;
      if (mesh.geometry) mesh.geometry.dispose();
      const mat = mesh.material;
      const mats = Array.isArray(mat) ? mat : mat ? [mat] : [];
      for (const m of mats) {
        for (const key of Object.keys(m)) {
          const val = (m as unknown as Record<string, unknown>)[key];
          if (val && typeof (val as { isTexture?: boolean }).isTexture === "boolean" && (val as { isTexture: boolean }).isTexture) {
            (val as { dispose: () => void }).dispose();
          }
        }
        m.dispose();
      }
    });
    renderer.forceContextLoss();
    renderer.dispose();
    renderer.domElement.remove();
  };
};

const loadEpub = async (target: string) => {
  const ePub = (await import("epubjs")).default;
  await nextTick();
  const host = epubHost.value;
  if (!host || target !== url) return;
  const book = ePub(target);
  const rendition = book.renderTo(host, { width: "100%", height: "100%", flow: "scrolled-doc" });
  await rendition.display();
  if (target !== url) {
    rendition.destroy();
    book.destroy();
    return;
  }
  cleanupViewer = () => {
    rendition.destroy();
    book.destroy();
  };
};

const loadPreview = async () => {
  teardownViewer();
  docHtml.value = "";
  codeText.value = "";
  sheets.value = [];
  activeSheet.value = 0;
  fontFamily.value = "";
  decodedSrc.value = "";
  zipEntries.value = [];
  notebook.value = [];
  icsEvents.value = [];
  scale.value = 1;
  const loadable = [
    "word", "sheet", "csv", "code", "font", "decoded", "zip",
    "ipynb", "ics", "parquet", "threed", "epub",
  ];
  if (!loadable.includes(kind.value)) {
    status.value = "idle";
    return;
  }
  status.value = "loading";
  error.value = "";
  const target = url;
  try {
    if (kind.value === "word") {
      const res = await read(target);
      const buffer = await res.arrayBuffer();
      const mammoth = await import("mammoth");
      const result = await mammoth.convertToHtml({ arrayBuffer: buffer });
      if (target !== url) return;
      docHtml.value = result.value;
    } else if (kind.value === "code") {
      const res = await read(target);
      const text = await res.text();
      if (target !== url) return;
      codeText.value = text;
    } else if (kind.value === "font") {
      fontCounter += 1;
      const family = `mar-preview-font-${fontCounter}`;
      const face = new FontFace(family, `url("${target}")`);
      await face.load();
      if (target !== url) return;
      document.fonts.add(face);
      addedFont = face;
      fontFamily.value = family;
    } else if (kind.value === "decoded") {
      const ext = extOf(name);
      const res = await read(target);
      const buffer = await res.arrayBuffer();
      let src = "";
      if (ext === "psd" || (mimeType ?? "").includes("photoshop")) {
        const { readPsd } = await import("ag-psd");
        const psd = readPsd(buffer);
        src = psd.canvas ? await canvasToObjectUrl(psd.canvas) : "";
        if (src) objectUrl = src;
      } else if (ext === "tif" || ext === "tiff" || (mimeType ?? "") === "image/tiff") {
        const UTIF = await import("utif");
        const ifds = UTIF.decode(buffer);
        UTIF.decodeImage(buffer, ifds[0]);
        const rgba = UTIF.toRGBA8(ifds[0]);
        const canvas = document.createElement("canvas");
        canvas.width = ifds[0].width;
        canvas.height = ifds[0].height;
        const ctx = canvas.getContext("2d");
        if (ctx) {
          const imageData = ctx.createImageData(canvas.width, canvas.height);
          imageData.data.set(new Uint8ClampedArray(rgba));
          ctx.putImageData(imageData, 0, 0);
          src = await canvasToObjectUrl(canvas);
          if (src) objectUrl = src;
        }
      } else {
        const heic2any = (await import("heic2any")).default;
        const blob = await heic2any({ blob: new Blob([buffer]), toType: "image/jpeg" });
        src = URL.createObjectURL(Array.isArray(blob) ? blob[0] : blob);
        objectUrl = src;
      }
      if (target !== url) return;
      decodedSrc.value = src;
    } else if (kind.value === "zip") {
      const res = await read(target);
      const buffer = await res.arrayBuffer();
      const JSZip = (await import("jszip")).default;
      const zip = await JSZip.loadAsync(buffer);
      if (target !== url) return;
      zipEntries.value = Object.keys(zip.files).sort();
    } else if (kind.value === "ipynb") {
      const res = await read(target);
      const data = await res.json();
      if (target !== url) return;
      const cells = Array.isArray(data?.cells) ? data.cells : [];
      notebook.value = cells.map((c: Record<string, unknown>): NotebookCell => {
        const source = Array.isArray(c.source) ? c.source.join("") : String(c.source ?? "");
        const outs = Array.isArray(c.outputs) ? c.outputs : [];
        const outputs = outs.map((o: Record<string, unknown>) => {
          const t = o.text ?? (o.data as Record<string, unknown> | undefined)?.["text/plain"];
          return Array.isArray(t) ? t.join("") : String(t ?? "");
        }).filter(Boolean);
        return { type: c.cell_type === "markdown" ? "markdown" : "code", source, outputs };
      });
    } else if (kind.value === "ics") {
      const res = await read(target);
      const text = await res.text();
      const ICAL = (await import("ical.js")).default;
      const comp = new ICAL.Component(ICAL.parse(text));
      if (target !== url) return;
      icsEvents.value = comp.getAllSubcomponents("vevent").map((v: unknown) => {
        const ev = new ICAL.Event(v);
        return {
          summary: ev.summary ?? "",
          start: ev.startDate ? icsStamp(ev.startDate.toJSDate()) : "",
          end: ev.endDate ? icsStamp(ev.endDate.toJSDate()) : "",
          location: ev.location ?? "",
        };
      });
    } else if (kind.value === "parquet") {
      const res = await read(target);
      const buffer = await res.arrayBuffer();
      const { parquetReadObjects } = await import("hyparquet");
      const objects = (await parquetReadObjects({ file: buffer })) as Record<string, unknown>[];
      if (target !== url) return;
      sheets.value = [{ name: "data", rows: rowsFromObjects(objects) }];
    } else if (kind.value === "threed") {
      await loadThreed(target);
    } else if (kind.value === "epub") {
      await loadEpub(target);
    } else {
      const xlsx = await import("xlsx");
      let workbook;
      if (kind.value === "csv") {
        const res = await read(target);
        const text = await res.text();
        workbook = xlsx.read(text, { type: "string" });
      } else {
        const res = await read(target);
        const buffer = await res.arrayBuffer();
        workbook = xlsx.read(new Uint8Array(buffer), { type: "array" });
      }
      if (target !== url) return;
      sheets.value = workbook.SheetNames.map((sheetName) => {
        const worksheet = workbook.Sheets[sheetName];
        return {
          name: sheetName,
          rows: worksheet
            ? (xlsx.utils.sheet_to_json(worksheet, {
                header: 1,
                blankrows: false,
                raw: false,
              }) as unknown[][])
            : [],
        };
      });
    }
    if (target !== url) return;
    status.value = "ready";
  } catch (e) {
    if (target !== url) return;
    error.value = e instanceof Error ? e.message : "Preview failed";
    status.value = "error";
  }
};

watch(
  () => url,
  () => {
    playing.value = false;
    currentTime.value = 0;
    duration.value = 0;
    void loadPreview();
  },
  { immediate: true },
);

onBeforeUnmount(() => {
  audioEl.value?.pause();
  teardownViewer();
});

watch(
  [kind, () => sheets.value.map((s) => s.name), activeSheet, scale],
  ([k, names, active, sc]) => {
    emit("preview-state", { kind: k, sheetNames: names, activeSheet: active, scale: sc });
  },
  { immediate: true },
);

defineExpose({
  setSheet: (i: number) => {
    activeSheet.value = i;
  },
  zoomBy: (factor: number) => {
    scale.value = Math.min(3, Math.max(0.5, Math.round(scale.value * factor * 100) / 100));
  },
  resetScale: () => {
    scale.value = 1;
  },
});
</script>

<template>
  <div class="mar-file-preview" :class="{ 'mar-file-preview-uploading': uploading }" :data-kind="kind">
    <div v-if="uploading" class="mar-file-preview-uploading-overlay">
      <MarLoadingSpinner />
    </div>
    <div v-if="!url" class="mar-file-preview-fallback">
      <MarIcon icon="file" />
      <span class="mar-file-preview-fallback-name">{{ name || "file" }}</span>
    </div>

    <MarImageControls v-else-if="kind === 'image'" :src="url" :alt="name" />

    <MarVideoControls v-else-if="kind === 'video'" :src="url" />

    <div v-else-if="kind === 'audio'" class="mar-file-preview-audio">
      <audio
        ref="audioEl"
        :src="url"
        @timeupdate="onAudioTime"
        @loadedmetadata="onAudioMeta"
        @play="playing = true"
        @pause="playing = false"
      />
      <MarAudioControls
        :playing="playing"
        :current-time="currentTime"
        :duration="duration"
        :volume="volume"
        :peaks="audioPeaks"
        :progress="progress"
        show-waveform
        show-skip
        @toggle="toggleAudio"
        @skip="skipAudio"
        @seek="seekAudio"
        @update:volume="setVolume"
      />
    </div>

    <div v-else-if="kind === 'pdf'" class="mar-file-preview-office">
      <component :is="VueOfficePdf" :key="url" :src="pdfSrc" class="mar-file-preview-pdf" />
    </div>

    <iframe
      v-else-if="kind === 'gsuite'"
      :src="gsuiteSrc"
      class="mar-file-preview-iframe"
      :title="name || 'preview'"
    />

    <iframe
      v-else-if="kind === 'html'"
      :src="url"
      class="mar-file-preview-iframe"
      sandbox="allow-same-origin allow-popups"
      :title="name || 'preview'"
    />

    <div v-else-if="kind === 'pptx'" class="mar-file-preview-office">
      <component :is="VueOfficePptx" :key="url" :src="url" class="mar-file-preview-pptx" />
    </div>

    <div v-else-if="kind === 'font'" class="mar-file-preview-office">
      <div v-if="status === 'loading'" class="mar-file-preview-state">
        <MarIcon icon="refresh" class="pi-spin mar-file-preview-glyph" />
        <span>Loading font</span>
      </div>
      <div v-else-if="status === 'error'" class="mar-file-preview-state">
        <MarIcon icon="triangle-alert" class="mar-file-preview-glyph" />
        <span class="mar-file-preview-state-name">{{ name || "font" }}</span>
      </div>
      <div v-else class="mar-file-preview-font-scroll">
        <div class="mar-file-preview-font" :style="{ fontFamily, zoom: scale }">
          <div class="mar-file-preview-font-hero">Ag</div>
          <p class="mar-file-preview-font-pangram">
            The quick brown fox jumps over the lazy dog
          </p>
          <p class="mar-file-preview-font-row">ABCDEFGHIJKLMNOPQRSTUVWXYZ</p>
          <p class="mar-file-preview-font-row">abcdefghijklmnopqrstuvwxyz</p>
          <p class="mar-file-preview-font-row">0123456789</p>
          <p class="mar-file-preview-font-s1">The quick brown fox</p>
          <p class="mar-file-preview-font-s2">The quick brown fox</p>
          <p class="mar-file-preview-font-s3">The quick brown fox</p>
        </div>
      </div>
    </div>

    <div v-else-if="kind === 'threed'" class="mar-file-preview-office mar-file-preview-stage">
      <div ref="threedHost" class="mar-file-preview-threed"></div>
      <div v-if="status === 'loading'" class="mar-file-preview-overlay">
        <MarIcon icon="refresh" class="pi-spin mar-file-preview-glyph" />
        <span>Loading model</span>
      </div>
      <div v-else-if="status === 'error'" class="mar-file-preview-overlay">
        <MarIcon icon="triangle-alert" class="mar-file-preview-glyph" />
        <span class="mar-file-preview-state-name">{{ name || "model" }}</span>
        <a class="mar-file-preview-fallback-link" :href="url" target="_blank" rel="noopener noreferrer">Open in new tab</a>
      </div>
    </div>

    <div v-else-if="kind === 'epub'" class="mar-file-preview-office mar-file-preview-stage">
      <div ref="epubHost" class="mar-file-preview-epub"></div>
      <div v-if="status === 'loading'" class="mar-file-preview-overlay">
        <MarIcon icon="refresh" class="pi-spin mar-file-preview-glyph" />
        <span>Loading book</span>
      </div>
      <div v-else-if="status === 'error'" class="mar-file-preview-overlay">
        <MarIcon icon="triangle-alert" class="mar-file-preview-glyph" />
        <span class="mar-file-preview-state-name">{{ name || "book" }}</span>
        <a class="mar-file-preview-fallback-link" :href="url" target="_blank" rel="noopener noreferrer">Open in new tab</a>
      </div>
    </div>

    <div
      v-else-if="['word', 'sheet', 'csv', 'code', 'decoded', 'zip', 'ipynb', 'ics', 'parquet'].includes(kind)"
      class="mar-file-preview-office"
    >
      <div v-if="status === 'loading'" class="mar-file-preview-state">
        <MarIcon icon="refresh" class="pi-spin mar-file-preview-glyph" />
        <span>Loading preview</span>
      </div>

      <div v-else-if="status === 'error'" class="mar-file-preview-state">
        <MarIcon icon="triangle-alert" class="mar-file-preview-glyph" />
        <span class="mar-file-preview-state-name">{{ name || "file" }}</span>
        <a
          class="mar-file-preview-fallback-link"
          :href="url"
          target="_blank"
          rel="noopener noreferrer"
          >Open in new tab</a
        >
      </div>

      <div v-else-if="kind === 'word'" class="mar-file-preview-doc-scroll">
        <div class="mar-file-preview-doc" :style="{ zoom: scale }" v-html="docHtml"></div>
      </div>

      <div v-else-if="kind === 'code'" class="mar-file-preview-code">
        <MarCode :model-value="codeText" :language="codeLang" readonly />
      </div>

      <div v-else-if="kind === 'decoded'" class="mar-file-preview-decoded">
        <MarImage :src="decodedSrc" :alt="name" fit="contain" />
      </div>

      <div v-else-if="kind === 'zip'" class="mar-file-preview-list-scroll">
        <ul class="mar-file-preview-zip">
          <li v-for="entry in zipEntries" :key="entry">
            <MarIcon :icon="entry.endsWith('/') ? 'folder' : 'file'" class="mar-file-preview-glyph" />
            {{ entry }}
          </li>
        </ul>
      </div>

      <div v-else-if="kind === 'ipynb'" class="mar-file-preview-list-scroll">
        <div class="mar-file-preview-notebook">
          <div
            v-for="(cell, i) in notebook"
            :key="i"
            :class="['mar-nb-cell', `mar-nb-cell-${cell.type}`]"
          >
            <MarBlockReader v-if="cell.type === 'markdown'" :model-value="cell.source" content-type="markdown" class="mar-nb-md" />
            <MarCode v-else :model-value="cell.source" language="python" readonly />
            <pre v-for="(out, j) in cell.outputs" :key="j" class="mar-nb-output">{{ out }}</pre>
          </div>
        </div>
      </div>

      <div v-else-if="kind === 'ics'" class="mar-file-preview-list-scroll">
        <div class="mar-file-preview-ics">
          <div v-for="(ev, i) in icsEvents" :key="i" class="mar-ics-event">
            <div class="mar-ics-summary">{{ ev.summary }}</div>
            <div class="mar-ics-time">{{ ev.start }} to {{ ev.end }}</div>
            <div v-if="ev.location" class="mar-ics-loc">{{ ev.location }}</div>
          </div>
        </div>
      </div>

      <div v-else class="mar-file-preview-sheet">
        <div v-if="sheets.length > 1" class="mar-file-preview-sheet-tabs">
          <button
            v-for="(sheet, i) in sheets"
            :key="sheet.name"
            type="button"
            :class="[
              'mar-file-preview-sheet-tab',
              { 'mar-file-preview-sheet-tab-active': i === activeSheet },
            ]"
            @click="activeSheet = i"
          >
            {{ sheet.name }}
          </button>
        </div>
        <div class="mar-file-preview-sheet-scroll">
          <table v-if="activeSheetData" class="mar-file-preview-table">
            <thead v-if="activeSheetData.rows.length">
              <tr>
                <th v-for="(cell, c) in activeSheetData.rows[0]" :key="c">
                  {{ cellText(cell) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(row, r) in activeSheetData.rows.slice(1)" :key="r">
                <td v-for="(cell, c) in row" :key="c">{{ cellText(cell) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <div v-else class="mar-file-preview-fallback">
      <MarIcon icon="file" />
      <span class="mar-file-preview-fallback-name">{{ name || "file" }}</span>
      <a
        class="mar-file-preview-fallback-link"
        :href="url"
        target="_blank"
        rel="noopener noreferrer"
        >Open in new tab</a
      >
    </div>
  </div>
</template>

<style scoped>
.mar-file-preview {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 100%;
  min-height: 0;
  background: var(--mar-image-backdrop);
  overflow: hidden;
}

.mar-file-preview-uploading > *:not(.mar-file-preview-uploading-overlay) {
  filter: blur(8px);
  opacity: 0.6;
  pointer-events: none;
}

.mar-file-preview-uploading-overlay {
  position: absolute;
  inset: 0;
  z-index: 2;
  display: flex;
  align-items: center;
  justify-content: center;
}

.mar-file-preview > .mar-image-controls,
.mar-file-preview > .mar-video-controls {
  width: 100%;
  height: 100%;
}

.mar-file-preview > .mar-video-controls {
  aspect-ratio: auto;
  border-radius: 0;
  background: var(--mar-image-backdrop);
}

.mar-file-preview-audio {
  width: 80%;
  max-width: 32em;
  padding: 0.625em 0.875em;
  background: var(--mar-surface-0);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
}

.mar-file-preview-iframe {
  width: 100%;
  height: 100%;
  border: none;
  background: var(--mar-surface-0);
}

.mar-file-preview-office {
  width: 100%;
  height: 100%;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--mar-surface-100);
}

.mar-file-preview-pptx,
.mar-file-preview-pdf {
  flex: 1;
  min-height: 0;
  overflow: auto;
}

.mar-file-preview-pptx {
  color: var(--mar-paper-color);
  color-scheme: light;
}

.mar-file-preview-stage {
  position: relative;
}

.mar-file-preview-threed,
.mar-file-preview-epub {
  flex: 1;
  min-height: 0;
  width: 100%;
}

.mar-file-preview-threed {
  display: block;
}

.mar-file-preview-epub {
  background: var(--mar-surface-0);
  overflow: auto;
}

.mar-file-preview-overlay {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.6154em;
  background: var(--mar-surface-100);
  color: var(--mar-text-muted-color);
  font-size: 0.8125em;
}

.mar-file-preview-overlay i {
  font-size: 1.5385em;
}

.mar-file-preview-decoded {
  flex: 1;
  min-height: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: auto;
}

.mar-file-preview-decoded > * {
  max-width: 100%;
  max-height: 100%;
}

.mar-file-preview-list-scroll {
  flex: 1;
  min-height: 0;
  overflow: auto;
  background: var(--mar-surface-0);
  scrollbar-width: thin;
  scrollbar-color: var(--mar-surface-400) transparent;
}

.mar-file-preview-zip {
  list-style: none;
  margin: 0;
  padding: 0.9231em 1.2308em;
  font-size: 0.8125em;
  color: var(--mar-text-color);
}

.mar-file-preview-zip li {
  display: flex;
  align-items: center;
  gap: 0.6154em;
  padding: 0.2308em 0;
}

.mar-file-preview-zip i {
  color: var(--mar-text-muted-color);
}

.mar-file-preview-notebook {
  max-width: 52em;
  margin: 0 auto;
  padding: 1.5em;
  display: flex;
  flex-direction: column;
  gap: 0.75em;
}

.mar-nb-cell {
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
  overflow: hidden;
}

.mar-nb-cell pre {
  margin: 0;
  padding: 0.9231em;
  font-size: 0.8125em;
  white-space: pre-wrap;
  word-break: break-word;
  color: var(--mar-text-color);
}

.mar-nb-cell-code pre {
  font-family: ui-monospace, monospace;
  background: var(--mar-surface-50);
}

.mar-nb-output {
  border-top: 1px solid var(--mar-content-border-color);
  background: var(--mar-surface-0);
  color: var(--mar-text-muted-color) !important;
}

.mar-file-preview-ics {
  max-width: 40em;
  margin: 0 auto;
  padding: 1.5em;
  display: flex;
  flex-direction: column;
  gap: 0.5em;
}

.mar-ics-event {
  padding: 0.625em 0.875em;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 8px;
  background: var(--mar-surface-0);
}

.mar-ics-summary {
  font-weight: 600;
  color: var(--mar-text-color);
}

.mar-ics-time,
.mar-ics-loc {
  font-size: 0.75em;
  color: var(--mar-text-muted-color);
}

.mar-file-preview-font-scroll {
  flex: 1;
  min-height: 0;
  overflow: auto;
  background: var(--mar-surface-0);
  scrollbar-width: thin;
  scrollbar-color: var(--mar-surface-400) transparent;
}

.mar-file-preview-font {
  max-width: 46em;
  margin: 0 auto;
  padding: 2.5em 3em;
  color: var(--mar-text-color);
}

.mar-file-preview-font-hero {
  font-size: 5em;
  line-height: 1.1;
  margin-bottom: 0.2em;
}

.mar-file-preview-font-pangram {
  font-size: 1.75em;
  margin: 0 0 0.8571em;
}

.mar-file-preview-font-row {
  font-size: 1.25em;
  letter-spacing: 0.05em;
  word-break: break-all;
  margin: 0 0 0.4em;
  color: var(--mar-text-muted-color);
}

.mar-file-preview-font-s1 {
  font-size: 0.875em;
  margin: 1.4286em 0 0;
}

.mar-file-preview-font-s2 {
  font-size: 1.25em;
  margin: 0.5em 0 0;
}

.mar-file-preview-font-s3 {
  font-size: 2em;
  margin: 0.3125em 0 0;
}

.mar-file-preview-code {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  background: var(--mar-surface-0);
}

.mar-file-preview-code :deep(.mar-code-block) {
  height: 100%;
  border: none;
  border-radius: 0;
}

.mar-file-preview-code :deep(.mar-code-block-host),
.mar-file-preview-code :deep(.cm-editor) {
  height: 100%;
}

.mar-file-preview-code :deep(.cm-scroller) {
  max-height: none;
  overflow: auto;
  scrollbar-width: thin;
  scrollbar-color: var(--mar-surface-400) transparent;
}

.mar-file-preview-state {
  margin: auto;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.6154em;
  color: var(--mar-text-muted-color);
  font-size: 0.8125em;
}

.mar-file-preview-state i {
  font-size: 1.5385em;
}

.mar-file-preview-glyph {
  font-size: 1.2308em;
}

.mar-file-preview-state-name {
  font-weight: 600;
  color: var(--mar-text-color);
}

.mar-file-preview-doc-scroll {
  flex: 1;
  min-height: 0;
  overflow: auto;
  padding: 1.5em;
  scrollbar-width: thin;
  scrollbar-color: var(--mar-surface-400) transparent;
}

.mar-file-preview-doc {
  max-width: 54.8571em;
  margin: 0 auto;
  padding: 2.8571em 3.4286em;
  background: var(--mar-surface-0);
  border: 1px solid var(--mar-content-border-color);
  border-radius: 10px;
  color: var(--mar-text-color);
  font-size: 0.875em;
  line-height: 1.6;
}

.mar-file-preview-doc :deep(h1) {
  font-size: 1.7143em;
  font-weight: 700;
  margin: 0.6667em 0 0.3333em;
}

.mar-file-preview-doc :deep(h2) {
  font-size: 1.4286em;
  font-weight: 600;
  margin: 0.7em 0 0.3em;
}

.mar-file-preview-doc :deep(h3) {
  font-size: 1.2143em;
  font-weight: 600;
  margin: 0.7059em 0 0.3529em;
}

.mar-file-preview-doc :deep(p) {
  margin: 0 0 0.7143em;
}

.mar-file-preview-doc :deep(ul),
.mar-file-preview-doc :deep(ol) {
  padding-left: 1.7143em;
  margin: 0.4286em 0 0.7143em;
}

.mar-file-preview-doc :deep(img) {
  max-width: 100%;
  height: auto;
  border-radius: 6px;
}

.mar-file-preview-doc :deep(table) {
  border-collapse: collapse;
  margin: 0.8571em 0;
  width: 100%;
}

.mar-file-preview-doc :deep(td),
.mar-file-preview-doc :deep(th) {
  border: 1px solid var(--mar-content-border-color);
  padding: 0.3571em 0.5714em;
  text-align: left;
}

.mar-file-preview-doc :deep(a) {
  color: var(--mar-primary-color);
  text-decoration: underline;
}

.mar-file-preview-sheet {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

.mar-file-preview-sheet-tabs {
  display: flex;
  gap: 0.125em;
  padding: 0.375em 0.5em 0;
  background: var(--mar-surface-100);
  border-bottom: 1px solid var(--mar-content-border-color);
  overflow-x: auto;
  scrollbar-width: thin;
}

.mar-file-preview-sheet-tab {
  border: none;
  background: transparent;
  color: var(--mar-text-muted-color);
  font-family: inherit;
  font-size: 0.75em;
  font-weight: 500;
  padding: 0.4167em 0.8333em;
  border-radius: 6px 6px 0 0;
  cursor: pointer;
  white-space: nowrap;
}

.mar-file-preview-sheet-tab-active {
  background: var(--mar-surface-0);
  color: var(--mar-text-color);
}

.mar-file-preview-sheet-scroll {
  flex: 1;
  min-height: 0;
  overflow: auto;
  background: var(--mar-surface-0);
  scrollbar-width: thin;
  scrollbar-color: var(--mar-surface-400) transparent;
}

.mar-file-preview-table {
  border-collapse: collapse;
  font-size: 0.75em;
  color: var(--mar-text-color);
}

.mar-file-preview-table th,
.mar-file-preview-table td {
  border: 1px solid var(--mar-content-border-color);
  padding: 0.3333em 0.6667em;
  text-align: left;
  white-space: nowrap;
  max-width: 32em;
  overflow: hidden;
  text-overflow: ellipsis;
}

.mar-file-preview-table thead th {
  position: sticky;
  top: 0;
  background: var(--mar-surface-200);
  font-weight: 600;
  z-index: 1;
}

.mar-file-preview-table tbody tr:nth-child(even) {
  background: var(--mar-surface-50);
}

.mar-file-preview-office ::-webkit-scrollbar {
  width: 0.375em;
  height: 0.375em;
}

.mar-file-preview-office ::-webkit-scrollbar-track {
  background: transparent;
}

.mar-file-preview-office ::-webkit-scrollbar-thumb {
  background: var(--mar-surface-400);
  border-radius: 9999px;
}

.mar-file-preview-fallback {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.375em;
  color: var(--mar-surface-600);
  padding: 1.5em;
  text-align: center;
}

.mar-file-preview-fallback i {
  font-size: 1.5em;
  color: var(--mar-surface-500);
}

.mar-file-preview-fallback-name {
  font-size: 0.8125em;
  font-weight: 600;
  color: var(--mar-text-color);
}

.mar-file-preview-fallback-link {
  font-size: 0.75em;
  color: var(--mar-primary-color);
  text-decoration: none;
}

.mar-file-preview-overlay .mar-file-preview-fallback-link,
.mar-file-preview-state .mar-file-preview-fallback-link {
  font-size: 0.9231em;
}

.mar-file-preview-fallback-link:hover {
  text-decoration: underline;
}
</style>
