import assert from "node:assert/strict";
import test from "node:test";
import activation from "../src/activation.js";

test("activation requires explicit local-only configuration and exposes the configured endpoint", () => {
  const facet = activation.hostFacets[0]!;
  assert.throws(() => facet.implementation.activate({
    instance: "comfyui.local", pool: "comfyui.local",
    config: { baseUrl: "http://127.0.0.1:8188", workflowRoot: "D:/AI/workflows", localOnly: false },
  } as never), /LOCAL_GENERATION_ONLY=true/u);
  const result = facet.implementation.activate({
    instance: "comfyui.local", pool: "comfyui.local",
    config: { baseUrl: "http://127.0.0.1:8188", workflowRoot: "D:/AI/workflows", localOnly: true },
  } as never);
  assert.equal(result.endpoint.instance.id, "comfyui.local");
  assert.equal(result.endpoint.pricing?.kind, "local");
});
