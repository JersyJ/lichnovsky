import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://lichnovsky.eu",
  // Content-Security-Policy as a <meta> tag with hashes of the page's inline scripts and styles
  // (build only). Everything else comes from this origin; nginx adds frame-ancestors, which a
  // <meta> policy can't carry.
  // No Markdown here; Shiki's inline styles would also clash with the CSP.
  markdown: { syntaxHighlight: false },
  security: {
    csp: {
      directives: [
        "default-src 'self'",
        "img-src 'self' data:",
        "object-src 'none'",
        "base-uri 'none'",
        "form-action 'none'",
      ],
      scriptDirective: { resources: ["'self'"] },
      styleDirective: { resources: ["'self'"] },
    },
  },
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
