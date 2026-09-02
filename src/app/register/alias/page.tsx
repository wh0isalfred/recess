import type { Metadata } from "next";
import { AliasStep } from "./AliasStep";

export const metadata: Metadata = {
  title: "Your RECESS name — RECESS",
};

export default function AliasPage() {
  return <AliasStep />;
}
