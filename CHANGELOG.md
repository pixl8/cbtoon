# CHANGELOG

## v1.0.6

* Stop asserting engine-specific wall-clock times in the date-encoding tests. Lucee emits UTC (`Z`); BoxLang keeps the original offset. The behaviour under test is that date keys are encoded, not dropped.

## v1.0.5

* Encode date-like simple values instead of silently dropping them. CFML `IsDate()` is true for Jira-style ISO timestamps, so they were excluded as primitives and omitted from object encoding with no fallback ([MIS-1183](https://projects.pixl8.london/browse/MIS-1183)).

## v1.0.4

* Harden null handling through encode, decode and `expandPaths`, including struct iteration that no longer skips JSON-null keys.
* Add fixtures and tests for nulls in arrays, tabular cells, list-style objects, and dotted-key expansion.

## v1.0.3

* Further null-value fixes so encode/decode behave consistently across Lucee and BoxLang.

## v1.0.2

* Fix Lucee-specific null handling when reading struct/map entries (Java `Map` nulls vs missing keys).

## v1.0.1

* Treat JSON null struct values as null rather than dropping or coercing them during normalisation.

## v1.0.0

* Initial ColdBox module for TOON encode/decode: JSON and CFML data (structs, arrays, queries, dates) to TOON, and TOON back to CFML or JSON.
* Improve query encoding as tabular TOON using column order.
* CI test matrix across Lucee 5.4 / 6.2 (and BoxLang in later runs) with ForgeBox publish on version tags.
