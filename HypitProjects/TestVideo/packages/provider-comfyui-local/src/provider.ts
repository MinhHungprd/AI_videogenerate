import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { canonicalize, defineEndpointPackage, wakeAfter } from "@hypit/hypit/endpoint-kit";
import type { AsyncEndpoint, EndpointRequest, ResourceId } from "@hypit/hypit/endpoint-kit";
import { generationTypes, sealGeneratedImageSet, sealGeneratedVideoSet } from "@hypit/hypit/generation";

export const providerModule = { name: "@local/provider-comfyui-local", version: "1" } as const;
export const imageCapability = { module: { name: "@hypit/gpt-image", version: "1" }, name: "gpt-image-2" } as const;
export const videoCapability = { module: { name: "@hypit/seedance", version: "1" }, name: "seedance-2-mini" } as const;

type JsonObject = Record<string, unknown>;
type WorkflowNode = { class_type?: string; inputs: Record<string, unknown> };
export type Workflow = Record<string, WorkflowNode>;

function object(value: unknown, message = "Expected object"): JsonObject {
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw new Error(message);
  return value as JsonObject;
}

function text(value: unknown, message = "Expected nonempty text"): string {
  if (typeof value !== "string" || value.length === 0) throw new Error(message);
  return value;
}

function number(value: unknown, message = "Expected number"): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new Error(message);
  return value;
}

function resourceId(value: unknown): ResourceId {
  const id = text(value, "Artifact resource ID is unavailable");
  if (!/^res_[a-zA-Z0-9._:-]+$/u.test(id)) throw new Error("Artifact resource ID is invalid");
  return id as ResourceId;
}

function localAddress(value: string): string {
  const url = new URL(value);
  if (url.protocol !== "http:" || !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) {
    throw new Error("ComfyUI requires loopback HTTP");
  }
  return url.href.replace(/\/$/u, "");
}

function copyWorkflow(value: unknown): Workflow {
  return structuredClone(object(value, "Workflow must be an object")) as Workflow;
}

function node(workflow: Workflow, id: string, expected: string): WorkflowNode {
  const value = workflow[id];
  if (value?.class_type !== expected || value.inputs === null || typeof value.inputs !== "object") {
    throw new Error(`Workflow node ${id} must be ${expected}`);
  }
  return value;
}

export function injectImageWorkflow(template: unknown, values: {
  prompt: string; seed: number; width: number; height: number; outputPrefix: string;
}): Workflow {
  const workflow = copyWorkflow(template);
  node(workflow, "6", "CLIPTextEncode").inputs.text = values.prompt;
  node(workflow, "3", "KSampler").inputs.seed = values.seed;
  const latent = node(workflow, "13", "EmptySD3LatentImage").inputs;
  latent.width = values.width;
  latent.height = values.height;
  node(workflow, "9", "SaveImage").inputs.filename_prefix = values.outputPrefix;
  return workflow;
}

export function injectVideoWorkflow(template: unknown, values: {
  prompt: string; seed: number; width: number; height: number; frames: number; fps: number;
  inputImage: string; outputPrefix: string;
}): Workflow {
  const workflow = copyWorkflow(template);
  node(workflow, "6", "CLIPTextEncode").inputs.text = values.prompt;
  node(workflow, "3", "KSampler").inputs.seed = values.seed;
  const latent = node(workflow, "55", "Wan22ImageToVideoLatent").inputs;
  latent.width = values.width;
  latent.height = values.height;
  latent.length = values.frames;
  const output = node(workflow, "47", "SaveWEBM").inputs;
  output.fps = values.fps;
  output.filename_prefix = values.outputPrefix;
  node(workflow, "57", "LoadImage").inputs.image = values.inputImage;
  return workflow;
}

export async function checkComfyHealth(baseUrl: string, fetcher: typeof globalThis.fetch = globalThis.fetch) {
  const base = localAddress(baseUrl);
  const response = await fetcher(`${base}/system_stats`, { signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new Error(`ComfyUI health returned HTTP ${response.status}`);
  const devices = object(await response.json()).devices;
  if (!Array.isArray(devices)) throw new Error("ComfyUI health omitted devices");
  const cuda = devices.map((item) => object(item)).find((item) => item.type === "cuda");
  if (cuda === undefined) throw new Error("ComfyUI CUDA device is unavailable");
  return { ok: true as const, device: text(cuda.name, "ComfyUI CUDA device name is unavailable").replace(/^cuda:\d+\s+/u, "").split(" : ")[0]! };
}

function ports(request: EndpointRequest): Record<string, readonly unknown[]> {
  const value = object(request.constraints);
  return object(value.ports, "Generation request omitted ports") as Record<string, readonly unknown[]>;
}

function firstPort(values: Record<string, readonly unknown[]>, name: string): unknown {
  const value = values[name]?.[0];
  if (value === undefined) throw new Error(`Generation request omitted ${name}`);
  return value;
}

function outputDimensions(aspectRatio: string, kind: "image" | "video") {
  if (kind === "video") {
    if (aspectRatio !== "9:16") throw new Error("Local Wan workflow supports only 9:16");
    return { width: 480, height: 864 };
  }
  if (aspectRatio === "1:1") return { width: 768, height: 768 };
  if (aspectRatio === "3:4") return { width: 768, height: 1024 };
  if (aspectRatio === "9:16") return { width: 576, height: 1024 };
  throw new Error(`Local image workflow does not support aspect ratio ${aspectRatio}`);
}

function support(kind: "image" | "video", request: EndpointRequest) {
  try {
    const values = ports(request);
    outputDimensions(text(firstPort(values, "aspectRatio")), kind);
    if (kind === "image") {
      if (String(firstPort(values, "resolution")) !== "1K") throw new Error("Local image workflow supports only 1K");
      if ((values.images?.length ?? 0) > 0) throw new Error("Local image workflow does not accept reference images");
    } else {
      if (String(firstPort(values, "resolution")) !== "480p") throw new Error("Local Wan workflow supports only 480p");
      const duration = number(firstPort(values, "duration"));
      if (duration < 3 || duration > 4) throw new Error("Local Wan workflow supports 3 to 4 seconds");
      if (firstPort(values, "generateAudio") !== false) throw new Error("Local Wan workflow does not generate audio");
      if (firstPort(values, "webSearch") !== false) throw new Error("LOCAL_GENERATION_ONLY forbids web search");
      if ((values.firstFrame?.length ?? 0) !== 1) throw new Error("Local Wan workflow requires one first frame");
    }
    return { status: "supported" as const };
  } catch (error) {
    return { status: "unsupported" as const, reason: error instanceof Error ? error.message : String(error) };
  }
}

type OutputRef = { filename: string; subfolder: string; type: string };
type TaskHandle = { id: string; kind: "image" | "video"; output?: OutputRef };

export function createComfyProvider(options: {
  instance: string;
  pool: string;
  baseUrl: string;
  localOnly: boolean;
  workflowRoot?: string;
  pollIntervalMs?: number;
  fetch?: typeof globalThis.fetch;
  readWorkflow?: (kind: "image" | "video") => Promise<unknown>;
}) {
  if (!options.localOnly) throw new Error("LOCAL_GENERATION_ONLY=true is required");
  const base = localAddress(options.baseUrl);
  const fetcher = options.fetch ?? globalThis.fetch;
  const interval = options.pollIntervalMs ?? 2_000;
  const workflowRoot = options.workflowRoot ?? "D:/AI/workflows";
  const readWorkflow = options.readWorkflow ?? (async (kind: "image" | "video") =>
    JSON.parse(await readFile(join(workflowRoot, kind === "image" ? "image.json" : "video_i2v.json"), "utf8")) as unknown);

  async function fetchJson(path: string, init?: RequestInit): Promise<JsonObject> {
    const response = await fetcher(`${base}${path}`, { ...init, signal: AbortSignal.timeout(30_000) });
    if (!response.ok) throw new Error(`ComfyUI ${init?.method ?? "GET"} ${path} returned HTTP ${response.status}`);
    return object(await response.json(), "ComfyUI returned invalid JSON");
  }

  function endpoint(kind: "image" | "video"): AsyncEndpoint {
    return {
      async start(context) {
        const supported = support(kind, context.need);
        if (supported.status === "unsupported") throw new Error(supported.reason);
        const values = ports(context.need);
        const prompt = text(firstPort(values, "prompt"));
        const aspectRatio = text(firstPort(values, "aspectRatio"));
        const dimensions = outputDimensions(aspectRatio, kind);
        const seed = Math.floor(Math.random() * Number.MAX_SAFE_INTEGER);
        let workflow: Workflow;
        if (kind === "image") {
          workflow = injectImageWorkflow(await readWorkflow(kind), {
            prompt, seed, ...dimensions, outputPrefix: `hypit/image-${context.operation}`,
          });
        } else {
          const item = object(firstPort(values, "firstFrame"));
          const artifact = object(item.artifact, "First frame omitted Artifact");
          const bytes = await context.resources.get(resourceId(artifact.resource));
          if (bytes === undefined) throw new Error("First frame bytes are unavailable");
          const mediaType = text(artifact.mediaType);
          const extension = mediaType === "image/jpeg" ? "jpg" : "png";
          const uploadName = `hypit-${context.operation}.${extension}`;
          const form = new FormData();
          form.append("image", new Blob([new Uint8Array(bytes)], { type: mediaType }), uploadName);
          form.append("type", "input");
          form.append("subfolder", "hypit");
          const uploadResponse = await fetcher(`${base}/upload/image`, {
            method: "POST", body: form, signal: AbortSignal.timeout(30_000),
          });
          if (!uploadResponse.ok) throw new Error(`ComfyUI POST /upload/image returned HTTP ${uploadResponse.status}`);
          const upload = object(await uploadResponse.json());
          const inputImage = [typeof upload.subfolder === "string" ? upload.subfolder : "", text(upload.name)].filter(Boolean).join("/");
          const duration = number(firstPort(values, "duration"));
          const fps = 24;
          workflow = injectVideoWorkflow(await readWorkflow(kind), {
            prompt, seed, ...dimensions, frames: duration * fps + 1, fps,
            inputImage, outputPrefix: `hypit/video-${context.operation}`,
          });
        }
        const submitted = await fetchJson("/prompt", {
          method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ prompt: workflow, client_id: `hypit-${context.operation}` }),
        });
        const id = text(submitted.prompt_id, "ComfyUI response omitted prompt_id");
        const handle: TaskHandle = { id, kind };
        const receipt = { id };
        await context.checkpoint?.({ handle, receipt });
        return { ...wakeAfter(handle, interval), receipt };
      },
      async poll(context) {
        const handle = object(context.handle) as TaskHandle;
        const history = await fetchJson(`/history/${encodeURIComponent(text(handle.id))}`);
        const entryValue = history[handle.id];
        if (entryValue === undefined) return wakeAfter(handle, interval);
        const entry = object(entryValue);
        const status = object(entry.status, "ComfyUI history omitted status");
        if (status.status_str === "error") {
          return { status: "failed", receipt: { id: handle.id }, failure: {
            code: "COMFYUI_GENERATION_FAILED", message: `ComfyUI task ${handle.id} failed`,
          } };
        }
        if (status.completed !== true || status.status_str !== "success") return wakeAfter(handle, interval);
        const outputNode = handle.kind === "image" ? "9" : "47";
        const outputs = object(entry.outputs, "ComfyUI history omitted outputs");
        const output = object(outputs[outputNode], `ComfyUI history omitted output node ${outputNode}`);
        if (!Array.isArray(output.images) || output.images.length === 0) throw new Error("ComfyUI task completed without output media");
        const result = object(output.images[0]);
        return { status: "ready", handle: { ...handle, output: {
          filename: text(result.filename), subfolder: typeof result.subfolder === "string" ? result.subfolder : "",
          type: typeof result.type === "string" ? result.type : "output",
        } } };
      },
      async collect(context) {
        const handle = object(context.handle) as TaskHandle;
        if (handle.output === undefined) throw new Error("ComfyUI output is unavailable");
        const query = new URLSearchParams(handle.output);
        const response = await fetcher(`${base}/view?${query}`, { signal: AbortSignal.timeout(60_000) });
        if (!response.ok) throw new Error(`ComfyUI GET /view returned HTTP ${response.status}`);
        const mediaType = response.headers.get("content-type")?.split(";")[0]?.trim()
          ?? (handle.kind === "image" ? "image/png" : "video/webm");
        if (!mediaType.startsWith(`${handle.kind}/`)) throw new Error(`ComfyUI returned unexpected ${mediaType}`);
        const artifact = await context.resources.put(new Uint8Array(await response.arrayBuffer()), mediaType);
        const value = handle.kind === "image"
          ? sealGeneratedImageSet({ images: [artifact] })
          : sealGeneratedVideoSet({ videos: [artifact] });
        return { status: "completed", result: { value: { kind: "inline", value: canonicalize(value) } } };
      },
    };
  }

  return defineEndpointPackage({
    module: providerModule,
    facet: "comfyui-local",
    instance: options.instance,
    pool: options.pool,
    credentials: {},
    defaultConcurrency: 1,
    actionLimits: { submit: { concurrency: 1 }, poll: { concurrency: 4 }, collect: { concurrency: 1 } },
    pricing: { kind: "local" },
    capabilities: [
      { capability: imageCapability, returns: generationTypes.imageSet, lifecycle: "asynchronous", supports: (request) => support("image", request), endpoint: endpoint("image") },
      { capability: videoCapability, returns: generationTypes.videoSet, lifecycle: "asynchronous", supports: (request) => support("video", request), endpoint: endpoint("video") },
    ],
  });
}
