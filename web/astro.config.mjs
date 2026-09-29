import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://lichnovsky.eu",
  vite: {
    server: {
      // Same URLs as in production (nginx.conf), answered by the public status page.
      proxy: {
        "/status-data": {
          target: "https://status.lichnovsky.eu",
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/status-data/, "/api/status-page"),
        },
      },
    },
  },
});
