import type { Metadata } from "next";
import Script from "next/script";
import { Archivo, Archivo_Black } from "next/font/google";
import "./globals.css";

/**
 * One superfamily, two roles.
 *
 * Archivo Black carries the poster voice — RECESS, CHECK IN, ROOM 03, #024 —
 * and Archivo carries everything a person actually has to read. They share a
 * skeleton, so the interface reads as one voice rather than a display face
 * arguing with a body face. RECESS gets its personality from scale, colour
 * and paper, which leaves the typography free to be disciplined.
 */
const display = Archivo_Black({
  subsets: ["latin"],
  weight: "400",
  variable: "--font-display-family",
  display: "swap",
});

const ui = Archivo({
  subsets: ["latin"],
  variable: "--font-ui-family",
  display: "swap",
});

export const metadata: Metadata = {
  title: "RECESS",
  description: "Our night to embrace that inner child and have real fun.",
};

/**
 * Runs before hydration, so the arrival entrance never flashes.
 *
 * Sets `html[data-arrival="fresh"]` on the first arrival of a browser session
 * only, never under prefers-reduced-motion, and only on `/`. Session scope
 * means moving around the product does not replay it, and the whole memory is
 * one sessionStorage key — nothing reaches the database.
 *
 * It lives here rather than in page.tsx because a `beforeInteractive` script
 * has to sit in the root layout; rendered inside a page it would not run on a
 * client-side navigation back to `/`.
 */
const ARRIVAL_GUARD = `(function(){try{if(location.pathname!=="/")return;var k="recess.arrival";if(!sessionStorage.getItem(k)&&!matchMedia("(prefers-reduced-motion: reduce)").matches){document.documentElement.dataset.arrival="fresh"}sessionStorage.setItem(k,"1")}catch(e){}})()`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={`${display.variable} ${ui.variable}`}
    >
      <body>
        <Script
          id="recess-arrival-guard"
          strategy="beforeInteractive"
          dangerouslySetInnerHTML={{ __html: ARRIVAL_GUARD }}
        />
        {children}
      </body>
    </html>
  );
}
