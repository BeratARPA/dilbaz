import type { Catalog } from "./catalog.ts";
import { trEnCatalog } from "./tr_en.ts";

/** Catalogs by language pair, `<l1>-<l2>`. */
export const catalogs: Readonly<Record<string, Catalog>> = {
  "tr-en": trEnCatalog,
};
