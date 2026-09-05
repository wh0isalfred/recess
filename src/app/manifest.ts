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

    background_color: "#F4E6D2",
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