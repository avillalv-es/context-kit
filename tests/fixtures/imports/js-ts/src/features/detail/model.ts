// FIXME: the /* on this line sits inside a line comment, so it opens nothing.
// A stripper that removes block comments before it removes line comments will
// disagree, and then swallow both imports below - nothing in this file ever
// closes the comment it thinks it just opened.
import type { Formatted } from "../../lib/format";
import { DetailView } from "./view";

export const MODEL_KIND = "detail";

export function detailModel(model: { label: Formatted | string }): Formatted {
  const text = typeof model.label === "string" ? model.label : model.label.text;
  return { text: typeof DetailView === "function" ? text : "" };
}
