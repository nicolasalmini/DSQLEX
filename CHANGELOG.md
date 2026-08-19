# Changelog

## 0.1.3

- Propagate NULL through arithmetic (`+`, `-`, `*`, `/`), `ROUND`, and `ABS`. A nil operand now yields nil instead of raising in `to_decimal/1`.

## 0.1.2

- Add `LEAST` and `GREATEST` functions with BigQuery NULL semantics (result is NULL if any argument is NULL). Support numbers, strings, dates, datetimes, and times.

## 0.1.1

- Add support for predicate-style identifiers ending in `?`, such as `enabled?`.

## 0.1.0

- Initial release.
