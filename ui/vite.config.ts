import {defineConfig} from "vite";
import react from "@vitejs/plugin-react";

// base: "./" makes the built app portable — open it from any static host or subpath.
export default defineConfig({
  plugins: [react()],
  base: "./",
  server: {port: 5173},
});
