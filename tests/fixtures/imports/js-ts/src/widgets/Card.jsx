import clsx from "clsx";
import { format } from "../lib/format";
import vendorClsx, * as vendor from "../vendor/clsx";

export const CARD_KIND = typeof vendor;

export default function Card({ title }) {
  return <div className={clsx("card", vendorClsx())}>{format(title).text}</div>;
}
