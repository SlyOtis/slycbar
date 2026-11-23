import { reactive } from "vue";
import { notify, dismiss } from "@/composables/useModals";

export interface RecorderSession {
  recording: boolean;
  paused: boolean;
  elapsed: number;
  level: number;
  bars: number[];
  transcript: string;
  audioUrl: string;
  error: string;
  name: string;
}

export interface RecorderOptions {
  socketUrl?: string;
  createSocket?: () => WebSocket;
  onLocate?: () => void;
  onRequestCancel?: (anchor?: HTMLElement) => void;
}

const recorderHooks = new Map<string, RecorderOptions>();

interface Runtime {
  recorder: MediaRecorder;
  stream: MediaStream;
  socket: WebSocket | null;
  audioCtx: AudioContext;
  analyser: AnalyserNode;
  data: Uint8Array<ArrayBuffer>;
  chunks: Blob[];
  timer: number;
  raf: number;
}

const MAX_BARS = 56;

const sessions = reactive<Record<string, RecorderSession>>({});
const runtimes = new Map<string, Runtime>();
const notifIds = new Map<string, string>();

let activeId: string | null = null;

const ensure = (id: string): RecorderSession => {
  if (!sessions[id]) {
    sessions[id] = {
      recording: false,
      paused: false,
      elapsed: 0,
      level: 0,
      bars: [],
      transcript: "",
      audioUrl: "",
      error: "",
      name: "",
    };
  }
  return sessions[id];
};

export const useRecorderSession = (id: string): RecorderSession => ensure(id);

export const setTranscript = (id: string, text: string): void => {
  ensure(id).transcript = text;
};

export const setRecorderName = (id: string, name: string): void => {
  ensure(id).name = name;
};

export const getActiveRecorder = (): { id: string; name: string } | null => {
  if (!activeId) return null;
  const s = sessions[activeId];
  if (!s || !s.recording) return null;
  return { id: activeId, name: s.name };
};

const tick = (id: string) => {
  const rt = runtimes.get(id);
  const s = sessions[id];
  if (!rt || !s) return;
  rt.analyser.getByteTimeDomainData(rt.data);
  let sum = 0;
  for (let i = 0; i < rt.data.length; i += 1) {
    const v = ((rt.data[i] ?? 128) - 128) / 128;
    sum += v * v;
  }
  const rms = Math.sqrt(sum / rt.data.length);
  s.level = Math.min(1, rms * 2.6);
  if (!s.paused) {
    s.bars.push(s.level);
    if (s.bars.length > MAX_BARS) s.bars.shift();
  }
  rt.raf = requestAnimationFrame(() => tick(id));
};

export const startRecorder = async (
  id: string,
  opts: RecorderOptions,
): Promise<void> => {
  const s = ensure(id);
  if (s.recording) return;
  if (activeId && activeId !== id) stopRecorder(activeId);
  s.error = "";
  let stream: MediaStream;
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch {
    s.error = "Microphone access denied";
    return;
  }
  let socket: WebSocket | null = null;
  if (opts.createSocket) socket = opts.createSocket();
  else if (opts.socketUrl) socket = new WebSocket(opts.socketUrl);
  if (socket) {
    socket.binaryType = "arraybuffer";
    socket.addEventListener("message", (e) => {
      const text = typeof e.data === "string" ? e.data : "";
      if (text) s.transcript = s.transcript ? `${s.transcript} ${text}` : text;
    });
  }
  const AudioCtx =
    window.AudioContext ||
    (window as unknown as { webkitAudioContext: typeof AudioContext })
      .webkitAudioContext;
  const audioCtx = new AudioCtx();
  if (audioCtx.state === "suspended") void audioCtx.resume();
  const source = audioCtx.createMediaStreamSource(stream);
  const analyser = audioCtx.createAnalyser();
  analyser.fftSize = 1024;
  source.connect(analyser);
  const data = new Uint8Array(analyser.fftSize);
  const recorder = new MediaRecorder(stream);
  const chunks: Blob[] = [];
  recorder.addEventListener("dataavailable", (e) => {
    if (e.data.size > 0) {
      chunks.push(e.data);
      if (socket && socket.readyState === WebSocket.OPEN) socket.send(e.data);
    }
  });
  recorder.addEventListener("stop", () => {
    if (!chunks.length) return;
    const blob = new Blob(chunks, { type: recorder.mimeType || "audio/webm" });
    s.audioUrl = URL.createObjectURL(blob);
  });
  recorder.start(1000);
  if (s.audioUrl) URL.revokeObjectURL(s.audioUrl);
  s.audioUrl = "";
  s.recording = true;
  s.paused = false;
  s.elapsed = 0;
  s.bars = [];
  activeId = id;
  recorderHooks.set(id, opts);
  const existingNotif = notifIds.get(id);
  if (existingNotif) dismiss(existingNotif);
  notifIds.set(
    id,
    notify(
      "info",
      s.name || "Recording",
      "Recording in progress",
      0,
      { label: "Stop", icon: "stop-circle", onClick: () => stopRecorder(id) },
      { onClick: opts.onLocate, onDismiss: opts.onRequestCancel },
    ),
  );
  const timer = window.setInterval(() => {
    const live = sessions[id];
    if (live && !live.paused) live.elapsed += 1;
  }, 1000);
  const rt: Runtime = {
    recorder,
    stream,
    socket,
    audioCtx,
    analyser,
    data,
    chunks,
    timer,
    raf: 0,
  };
  runtimes.set(id, rt);
  rt.raf = requestAnimationFrame(() => tick(id));
};

export const pauseRecorder = (id: string): void => {
  const rt = runtimes.get(id);
  const s = sessions[id];
  if (!rt || !s || !s.recording || s.paused) return;
  if (rt.recorder.state === "recording") rt.recorder.pause();
  s.paused = true;
  s.level = 0;
};

export const resumeRecorder = (id: string): void => {
  const rt = runtimes.get(id);
  const s = sessions[id];
  if (!rt || !s || !s.recording || !s.paused) return;
  if (rt.recorder.state === "paused") rt.recorder.resume();
  s.paused = false;
};

export const stopRecorder = (id: string, complete = true): void => {
  const rt = runtimes.get(id);
  const s = sessions[id];
  const wasActive = !!rt;
  if (rt) {
    window.clearInterval(rt.timer);
    cancelAnimationFrame(rt.raf);
    if (rt.recorder.state !== "inactive") rt.recorder.stop();
    rt.stream.getTracks().forEach((t) => t.stop());
    rt.socket?.close();
    void rt.audioCtx.close();
    runtimes.delete(id);
  }
  if (s) {
    s.recording = false;
    s.paused = false;
    s.level = 0;
  }
  const notifId = notifIds.get(id);
  if (notifId) {
    dismiss(notifId);
    notifIds.delete(id);
  }
  if (activeId === id) activeId = null;
  const hooks = recorderHooks.get(id);
  recorderHooks.delete(id);
  if (complete && wasActive) {
    notify(
      "success",
      (s?.name ?? "Recording") || "Recording",
      "Recording and transcription complete",
      6000,
      undefined,
      { onClick: hooks?.onLocate },
    );
  }
};

export const discardRecorder = (id: string): void => {
  stopRecorder(id, false);
  const s = sessions[id];
  if (!s) return;
  if (s.audioUrl) URL.revokeObjectURL(s.audioUrl);
  s.audioUrl = "";
  s.transcript = "";
  s.elapsed = 0;
  s.bars = [];
  s.name = "";
};
