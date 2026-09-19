import {
  useCallback,
  useState,
} from "react";
import { Button } from "./components/Button";
import { useData } from "./hooks/useData.js";
import { format } from "@lib";

/*
 * Historical note: this file used to require("./legacy/loader.cjs") at the top
 * level, and it also did import "./lib/ghost" before that module was deleted.
 * Neither line exists any more - do not resurrect them.
 */
export function App() {
  const [open, setOpen] = useState(false);
  const data = useData();
  const onPick = useCallback(async () => {
    const mod = await import("./lib/format");
    setOpen(!open);
    return mod.slug(format(String(data)).text);
  }, [open, data]);
  return <Button label="import a file" onClick={onPick} />;
}
