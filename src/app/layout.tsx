import type { Metadata } from "next";
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

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${display.variable} ${ui.variable}`}>
      <body>{children}</body>
    </html>
  );
}
