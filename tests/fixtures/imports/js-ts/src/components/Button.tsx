import clsx from "clsx";
import type { Formatted } from "../lib/format";
import { LABELS } from "@app/lib/constants";
// A scoped npm package, not in tsconfig paths. It mirrors src/vendor/clsx.ts
// exactly, so an extractor that treats @x/y as a repo path invents an edge.
import scoped from "@vendor/clsx";
import Card from "../widgets/Card.jsx"; // trailing comment must not eat the specifier

export type ButtonProps = {
  label: string;
  onClick: () => Promise<Formatted | string>;
};

export function Button({ label, onClick }: ButtonProps) {
  // The bundler config used to require("clsx/lite") here; do not re-add it.
  return (
    <button className={clsx("btn")} onClick={onClick} title={String(Card) + String(scoped)}>
      {label || LABELS.go}
    </button>
  );
}
