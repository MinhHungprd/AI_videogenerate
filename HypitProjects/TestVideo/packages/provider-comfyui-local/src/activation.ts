import {
  createRuntimeEndpointAdapterFacet,
  runtimeConfigBoolean,
  runtimeConfigExact,
  runtimeConfigObject,
  runtimeConfigPositiveInteger,
  runtimeConfigString,
} from "@hypit/hypit/runtime-kit";
import { createComfyProvider, providerModule } from "./provider.js";

export default {
  format: "hypit.node-package@1" as const,
  hostFacets: [createRuntimeEndpointAdapterFacet({
    use: providerModule.name,
    activate(context) {
      const config = runtimeConfigObject(context.config, "ComfyUI local provider");
      runtimeConfigExact(config, ["baseUrl", "workflowRoot", "localOnly", "pollIntervalMs"], "ComfyUI local provider");
      const baseUrl = runtimeConfigString(config.baseUrl, "ComfyUI baseUrl");
      const workflowRoot = runtimeConfigString(config.workflowRoot, "ComfyUI workflowRoot");
      const localOnly = runtimeConfigBoolean(config.localOnly, "ComfyUI localOnly");
      if (!baseUrl || !workflowRoot || !context.pool) {
        throw new Error("ComfyUI local provider requires baseUrl, workflowRoot and pool");
      }
      return { endpoint: createComfyProvider({
        instance: context.instance,
        pool: context.pool,
        baseUrl,
        workflowRoot,
        localOnly: localOnly === true,
        pollIntervalMs: runtimeConfigPositiveInteger(config.pollIntervalMs, "ComfyUI pollIntervalMs") ?? 2_000,
      }) };
    },
  })],
};
