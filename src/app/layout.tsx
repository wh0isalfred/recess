import type { Metadata } from "next";
import { Anton, Inter } from "next/font/google";
import "./globals.css";

/**
 * Display type stands in for the roughened condensed face in the approved
 * screens. Anton is the closest free match and is NOT final — swapping it is
 * this line plus --font-display.
 */
const display = Anton({
  subsets: ["latin"],
  weight: "400",
  variable: "--font-display",
  display: "swap",
});

const ui = Inter({
  subsets: ["latin"],
  variable: "--font-ui",
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
