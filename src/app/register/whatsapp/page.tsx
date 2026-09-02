import type { Metadata } from "next";
import { WhatsAppStep } from "./WhatsAppStep";

export const metadata: Metadata = {
  title: "Register — RECESS",
};

export default function WhatsAppPage() {
  return <WhatsAppStep />;
}
