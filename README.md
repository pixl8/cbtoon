# cbtoon

**cbtoon** is a ColdFusion Markup Language (CFML) library for [Token-Oriented Object Notation (TOON)](https://github.com/toon-format/toon) — a compact, line-oriented format aimed at the same data model as JSON (objects, arrays, strings, numbers, booleans, and null). It is often used to cut token usage when passing structured data to LLMs while keeping explicit array lengths and tabular headers for easier validation.

The normative rules are defined in the [TOON specification](https://github.com/toon-format/spec/blob/main/SPEC.md) (v3.x). This module implements encode/decode aligned with that model; behaviour is verified with TestBox against fixtures under `tests/fixtures/`.

## Requirements

- Lucee 5.4+ (CI also runs Lucee 6.2)
- [CommandBox](https://www.ortussolutions.com/products/commandbox) for local development, tests, and packaging

## Installation

### For ColdBox applications

From the project root:

```bash
box install cbtoon
```

Use wirebox reference `cbtoon@cbtoon` to get an instance of the library. e.g.
```cfc
toon = getModel( "cbtoon@cbtoon" );
// or
property name="toon" inject="cbtoon@cbtoon";
// etc.
```

## Public API (`models/CbToon.cfc`)

| Method | Description |
|--------|-------------|
| `encodeFromJson( string json, struct options = {} )` | Parses JSON, normalizes to the JSON data model, returns a TOON string. |
| `encodeFromCfml( any data, struct options = {} )` | Normalizes CFML values (structs, arrays, **queries**, dates, numbers, booleans, null) and returns TOON. Queries become an array of row structs (column list order). |
| `decodeToCfml( string toon, struct options = {} )` | Parses TOON into CFML structs, arrays, and simple values. |
| `decodeToJson( string toon, struct options = {} )` | `decodeToCfml` then `SerializeJSON` on the result. |
| `defaultEncodeOptions()` | `{ indent: 2, delimiter: "comma", keyFolding: "off" }` |
| `defaultDecodeOptions()` | `{ indent: 2, strict: true, expandPaths: "off" }` |

### Encode options

- **indent** — spaces per nesting level (default `2`).
- **delimiter** — `"comma"` (default), `"tab"`, or `"pipe"` for document and array delimiters as per the spec.
- **keyFolding** — reserved; only `"off"` is honoured today (safe folding from the spec is not implemented yet).

### Decode options

- **indent** — must match the document (default `2`).
- **strict** — when `true` (default), enforces row counts, list lengths, indentation multiples, and related rules from the spec.
- **expandPaths** — `"off"` (default) or `"safe"` to split dotted keys into nested structs where all segments are safe identifiers (see spec §13.4). Merging semantics follow a simplified version of the spec; quoted keys are not tracked separately for expansion.

## Usage examples

```cfml
toon = new cbtoon.models.CbToon();

// JSON → TOON
txt = toon.encodeFromJson( '{"users":[{"id":1,"name":"Ada"}]}' );

// CFML → TOON (tabular arrays of uniform objects collapse to table form when possible)
txt = toon.encodeFromCfml( local.myStruct );

// Query → TOON (rows become an array of structs)
txt = toon.encodeFromCfml( { "rows": qMyQuery } );

// TOON → CFML
data = toon.decodeToCfml( txt );

// TOON → JSON string
json = toon.decodeToJson( txt );
```

## Tests and CI

```bash
./runtests.sh
```

Or start the test server and run TestBox:

```bash
box server start directory="./tests/" serverConfigFile="./tests/server-cbtoontests.json"
box testbox run verbose=true
```

GitHub Actions (`.github/workflows/ci.yml`) runs the same TestBox suite on Lucee 5.4 and 6.2.

## Implementation notes

- **Numbers in encode** — `IsNumeric` is checked before `IsBoolean` so values such as `1` are not emitted as booleans on engines where both predicates overlap.
- **JSON `DeserializeJSON`** — on Lucee, bare numeric `1` inside JSON arrays may deserialize as a boolean in some cases. If you need a literal integer `1` in a list, build the array in CFML (for example `JavaCast( "int", 1 )`) or avoid ambiguous literals in JSON; see the spec and your engine’s JSON behaviour.
- **Object key order** — encoders emit keys in the order returned by `structKeyArray`; that order depends on the CFML engine and how the struct was built (e.g. JSON deserialization may sort keys).

## Code of conduct

Participation in this project is governed by the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).

## Licence

MIT — see [LICENSE.txt](LICENSE.txt).
