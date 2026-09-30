import { assert, assertEquals } from "@std/assert";
import { dirname, fromFileUrl, join } from "@std/path";
import { moduleName, pairs, readCatalog, render } from "./generate.ts";
import { catalogs } from "./index.ts";

const here = dirname(fromFileUrl(import.meta.url));

for (const pair of pairs) {
  Deno.test(`${pair}: the catalog module matches its pair pack`, async () => {
    const expected = render(pair, await readCatalog(pair));
    const actual = await Deno.readTextFile(
      join(here, `${moduleName(pair)}.ts`),
    );
    assert(
      actual.replaceAll("\r\n", "\n") === expected,
      `${pair} changed: run \`deno run -A _shared/catalogs/generate.ts\``,
    );
  });
}

Deno.test("every pair's catalog is served, with unique codes", () => {
  assertEquals(Object.keys(catalogs).sort(), [...pairs].sort());
  for (const catalog of Object.values(catalogs)) {
    const codes = catalog.errorTags.map((tag) => tag.code);
    assertEquals(new Set(codes).size, codes.length, catalog.pack);
    for (const tag of catalog.errorTags) {
      assert(tag.description && tag.example.includes("→"), tag.code);
    }
  }
});
