import assert from "node:assert/strict";
import test from "node:test";
import { canonicalize } from "@hypit/hypit/endpoint-kit";
import { generationTypes } from "@hypit/hypit/generation";
import { EndpointRegistry } from "@hypit/driver-node";
import {
  checkComfyHealth,
  createComfyProvider,
  imageCapability,
  injectImageWorkflow,
  injectVideoWorkflow,
  videoCapability,
} from "../src/provider.js";

const imageTemplate = {
  "3": { class_type: "KSampler", inputs: { seed: 1 } },
  "6": { class_type: "CLIPTextEncode", inputs: { text: "old" } },
  "9": { class_type: "SaveImage", inputs: { filename_prefix: "old" } },
  "13": { class_type: "EmptySD3LatentImage", inputs: { width: 1, height: 1 } },
};
const videoTemplate = {
  "3": { class_type: "KSampler", inputs: { seed: 1 } },
  "6": { class_type: "CLIPTextEncode", inputs: { text: "old" } },
  "47": { class_type: "SaveWEBM", inputs: { filename_prefix: "old", fps: 1 } },
  "55": { class_type: "Wan22ImageToVideoLatent", inputs: { width: 1, height: 1, length: 1 } },
  "57": { class_type: "LoadImage", inputs: { image: "old.png" } },
};

async function resolveAsync(provider: ReturnType<typeof createComfyProvider>, need: never) {
  const registry = new EndpointRegistry();
  await provider.install(registry);
  const resolution = registry.resolve(need);
  assert.equal(resolution.status, "resolved");
  assert.equal(resolution.registration.kind, "asynchronous");
  return resolution.registration.endpoint;
}

test("health accepts CUDA ComfyUI on loopback and rejects a non-local endpoint", async () => {
  const fetcher: typeof fetch = async (input) => {
    assert.equal(String(input), "http://127.0.0.1:8188/system_stats");
    return Response.json({ devices: [{ type: "cuda", name: "NVIDIA GeForce RTX 4060" }] });
  };
  assert.deepEqual(await checkComfyHealth("http://127.0.0.1:8188", fetcher), {
    ok: true,
    device: "NVIDIA GeForce RTX 4060",
  });
  await assert.rejects(
    () => checkComfyHealth("https://example.com", fetcher),
    /loopback HTTP/u,
  );
});

test("workflow injection changes only declared image generation inputs", () => {
  const source = structuredClone(imageTemplate);
  const injected = injectImageWorkflow(source, {
    prompt: "local image", seed: 42, width: 768, height: 1024, outputPrefix: "hypit/image-task",
  });
  assert.equal(injected["6"].inputs.text, "local image");
  assert.equal(injected["3"].inputs.seed, 42);
  assert.deepEqual(injected["13"].inputs, { width: 768, height: 1024 });
  assert.equal(injected["9"].inputs.filename_prefix, "hypit/image-task");
  assert.deepEqual(source, imageTemplate);
});

test("workflow injection maps video prompt, seed, dimensions, frames, fps and uploaded input", () => {
  const injected = injectVideoWorkflow(videoTemplate, {
    prompt: "natural motion", seed: 77, width: 480, height: 864,
    frames: 73, fps: 24, inputImage: "hypit/reference.png", outputPrefix: "hypit/video-task",
  });
  assert.equal(injected["6"].inputs.text, "natural motion");
  assert.equal(injected["3"].inputs.seed, 77);
  assert.deepEqual(injected["55"].inputs, { width: 480, height: 864, length: 73 });
  assert.equal(injected["47"].inputs.fps, 24);
  assert.equal(injected["57"].inputs.image, "hypit/reference.png");
});

test("submit, poll and collect returns a Hypit image Artifact without cloud fallback", async () => {
  const calls: string[] = [];
  const stored = new Map<string, { bytes: Uint8Array; mediaType: string }>();
  const resources = {
    async get(id: string) { return stored.get(id)?.bytes; },
    async put(bytes: Uint8Array, mediaType: string) {
      stored.set("res_result", { bytes, mediaType });
      return { kind: "blob" as const, resource: "res_result", mediaType, size: bytes.byteLength };
    },
  };
  let checkpoint: unknown;
  const provider = createComfyProvider({
    instance: "comfyui.local", pool: "comfyui.local", baseUrl: "http://127.0.0.1:8188",
    localOnly: true,
    readWorkflow: async (kind) => kind === "image" ? imageTemplate : videoTemplate,
    fetch: async (input, init) => {
      const url = new URL(String(input)); calls.push(`${init?.method ?? "GET"} ${url.pathname}`);
      if (url.pathname === "/prompt") return Response.json({ prompt_id: "local-task" });
      if (url.pathname === "/history/local-task") return Response.json({
        "local-task": { status: { status_str: "success", completed: true }, outputs: {
          "9": { images: [{ filename: "image.png", subfolder: "hypit", type: "output" }] },
        } },
      });
      if (url.pathname === "/view") return new Response(new Uint8Array([1, 2, 3]), { headers: { "content-type": "image/png" } });
      throw new Error(`Unexpected request ${url}`);
    },
  });
  const need = {
    id: "need:image", capability: imageCapability, returns: generationTypes.imageSet,
    constraints: canonicalize({ model: "gpt-image-2", result: "image", ports: {
      prompt: ["local image"], aspectRatio: ["3:4"], resolution: ["1K"],
    } }), result: "result:image",
  } as const;
  const endpoint = await resolveAsync(provider, need as never);
  const context = {
    need, command: { kind: "fulfill-need", id: "command:image", need }, operation: "operation:image",
    resources, credentials: {}, checkpoint: async (value: unknown) => { checkpoint = value; },
  } as never;
  const started = await endpoint.start(context); assert.equal(started.status, "pending");
  assert.deepEqual(checkpoint, { handle: { id: "local-task", kind: "image" }, receipt: { id: "local-task" } });
  const ready = await endpoint.poll({ ...context, handle: started.handle } as never); assert.equal(ready.status, "ready");
  const completed = await endpoint.collect!({ ...context, handle: ready.handle } as never); assert.equal(completed.status, "completed");
  assert.equal(completed.result.value.kind, "inline");
  const artifact = (completed.result.value.value as unknown as { images: Array<{ resource: string; mediaType: string }> }).images[0]!;
  assert.equal(artifact.mediaType, "image/png");
  assert.deepEqual(stored.get(artifact.resource)?.bytes, new Uint8Array([1, 2, 3]));
  assert.deepEqual(calls, ["POST /prompt", "GET /history/local-task", "GET /view"]);
});

test("video submission uploads the first frame and collects a video Artifact", async () => {
  const stored = new Map<string, Uint8Array>([["res_source", new Uint8Array([9, 8, 7])]]);
  const resources = {
    async get(id: string) { return stored.get(id); },
    async put(bytes: Uint8Array, mediaType: string) {
      stored.set("res_video_result", bytes);
      return { kind: "blob" as const, resource: "res_video_result", mediaType, size: bytes.byteLength };
    },
  };
  const provider = createComfyProvider({
    instance: "comfyui.local", pool: "comfyui.local", baseUrl: "http://localhost:8188", localOnly: true,
    readWorkflow: async (kind) => kind === "image" ? imageTemplate : videoTemplate,
    fetch: async (input, init) => {
      const url = new URL(String(input));
      if (url.pathname === "/upload/image") {
        assert.equal(init?.method, "POST");
        return Response.json({ name: "reference.png", subfolder: "hypit", type: "input" });
      }
      if (url.pathname === "/prompt") {
        const body = JSON.parse(String(init?.body));
        assert.equal(body.prompt["57"].inputs.image, "hypit/reference.png");
        assert.equal(body.prompt["55"].inputs.length, 97);
        return Response.json({ prompt_id: "video-task" });
      }
      if (url.pathname === "/history/video-task") return Response.json({
        "video-task": { status: { status_str: "success", completed: true }, outputs: {
          "47": { images: [{ filename: "video.webm", subfolder: "hypit", type: "output" }] },
        } },
      });
      if (url.pathname === "/view") return new Response(new Uint8Array([4, 5, 6]), { headers: { "content-type": "video/webm" } });
      throw new Error(`Unexpected request ${url}`);
    },
  });
  const need = {
    id: "need:video", capability: videoCapability, returns: generationTypes.videoSet,
    constraints: canonicalize({ model: "seedance-2-mini", result: "video", ports: {
      prompt: ["natural motion"], aspectRatio: ["9:16"], resolution: ["480p"], duration: [4],
      generateAudio: [false], webSearch: [false], firstFrame: [{
        role: "image", artifact: { kind: "blob", resource: "res_source", mediaType: "image/png", size: 3 }, personReference: false,
      }],
    } }), result: "result:video",
  } as const;
  const endpoint = await resolveAsync(provider, need as never);
  const context = {
    need, command: { kind: "fulfill-need", id: "command:video", need }, operation: "operation:video",
    resources, credentials: {}, checkpoint: async () => undefined,
  } as never;
  const started = await endpoint.start(context);
  const ready = await endpoint.poll({ ...context, handle: started.handle } as never);
  const completed = await endpoint.collect!({ ...context, handle: ready.handle } as never);
  assert.equal(completed.status, "completed");
  const artifact = (completed.result.value.value as unknown as { videos: Array<{ resource: string; mediaType: string }> }).videos[0]!;
  assert.equal(artifact.mediaType, "video/webm");
  assert.deepEqual(stored.get(artifact.resource), new Uint8Array([4, 5, 6]));
});
