import { defineConfig } from "tsup";

export default defineConfig([
  {
    entry: { index: "src/index.ts" },
    format: ["esm", "cjs"],
    dts: true,
    sourcemap: true,
    clean: true,
  },
  {
    entry: { "index.iife": "src/index.ts" },
    format: ["iife"],
    globalName: "MisarReachSDK",
    outDir: "dist",
    minify: true,
    sourcemap: false,
  },
]);
