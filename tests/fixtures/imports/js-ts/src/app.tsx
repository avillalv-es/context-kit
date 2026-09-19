import {
  useCallback,
  useState,
} from "react";
import { Button } from "./components/Button";
import { useData } from "./hooks/useData.js";
import { format } from "@lib";
import { settings } from "#config";
import Card, { CARD_KIND } from "./widgets/Card";
import "./app.css";

/*
 * Historical note: this file used to require("./legacy/loader.cjs") at the top
 * level, and it also did import "./lib/ghost" before that module was deleted.
 * Neither line exists any more - do not resurrect them.
 */

/** @type {import("./lib/constants").LABELS | undefined} */
let labelsDoc;

export function App() {
  const [open, setOpen] = useState(false);
  const data = useData();
  const onPick = useCallback(async () => {
    const mod = await import("./lib/format");
    const lazy = await import(
      "./features/detail/model"
    );
    setOpen(!open);
    return lazy.detailModel({ label: mod.slug(format(String(data)).text) }).text;
  }, [open, data]);
  return (
    <Button
      label={"import a file" + settings.retries + typeof Card + CARD_KIND + typeof labelsDoc}
      onClick={onPick}
    />
  );
}
