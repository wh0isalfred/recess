import type { Metadata } from "next";
import { NameStep } from "./NameStep";

export const metadata: Metadata = {
  title: "Register — RECESS",
};

export default function RegisterPage() {
  return <NameStep />;
}
