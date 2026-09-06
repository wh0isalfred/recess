import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "RECESS",
    short_name: "RECESS",
    description:
      "RECESS is our night to embrace that inner child and have real fun.",

    start_url: "/",
    scope: "/",
    display: "standalone",

    // The Web App Manifest spec requires literal color strings here — this
    // is static JSON read by the OS before the app (and its CSS tokens)
    // ever loads, not a component rendering with the design system's
    // colors. Matches --paper (#f4ede0) closely; kept as a literal on
    // purpose, not a bypassed token.
    // eslint-disable-next-line no-restricted-syntax
    background_color: "#F4E6D2",
    // eslint-disable-next-line no-restricted-syntax
    theme_color: "#F4E6D2",

    icons: [
      {
        src: "/icons/icon-192x192.png",
        sizes: "192x192",
        type: "image/png",
      },
      {
        src: "/icons/icon-512x512.png",
        sizes: "512x512",
        type: "image/png",
      },
    ],
  };
}