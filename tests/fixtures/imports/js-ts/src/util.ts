// A FILE named util.ts sitting beside a DIRECTORY named util/.
// "./util" must resolve here, never to ./util/index.ts: file beats directory.
import util from "util";
import { format } from "@shared/format";

// @shared/* maps to two roots; neither of them contains "nowhere".
import { nothing } from "@shared/nowhere";

export const UTIL_NAME = format("file").text;
export const UTIL_TYPE = typeof util + typeof nothing;
