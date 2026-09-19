import clsx from "clsx";
import type { Formatted } from "../lib/format";
import { LABELS } from "@app/lib/constants";

export type ButtonProps = {
  label: string;
  onClick: () => Promise<Formatted | string>;
};

export function Button({ label, onClick }: ButtonProps) {
  // The bundler config used to require("clsx/lite") here; do not re-add it.
  return (
    <button className={clsx("btn")} onClick={onClick}>
      {label || LABELS.go}
    </button>
  );
}
