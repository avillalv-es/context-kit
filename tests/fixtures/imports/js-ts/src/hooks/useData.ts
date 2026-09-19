import { useEffect, useState } from "react";
import {
  format,
  VERSION,
} from "../lib";

const USAGE = 'import { format } from "../lib/format"';

export function useData(): string {
  const [rows, setRows] = useState<string>(VERSION);
  useEffect(() => {
    setRows(format(USAGE).text);
  }, []);
  return rows;
}
