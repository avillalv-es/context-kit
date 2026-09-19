import { useEffect, useState } from "react";
import {
  format,
  VERSION,
} from "../lib";
import { HOOK_LIMIT } from "./constants";
import { VERSION as LIB_VERSION } from "../lib/constants"
import * as models from "../types/models";

const USAGE = 'import { format } from "../lib/format"';

export function useData(): string {
  const [rows, setRows] = useState<string>(VERSION + LIB_VERSION);
  useEffect(() => {
    setRows(format(USAGE).text.slice(0, HOOK_LIMIT));
  }, []);
  return rows;
}

export type Row = models.Model;
