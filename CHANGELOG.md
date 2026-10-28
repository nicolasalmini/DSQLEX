# Changelog

## 0.2.0

- Add list aggregation functions `SUM(list, expr)`, `COUNT(list)`, `COUNT(list, cond)`, `ANY(list, cond)` and `ALL(list, cond)`. The expression is evaluated once per element of a list of maps; `ROOT.<path>` reads the enclosing context. A nil element result in `SUM` is an error naming the element index.
- Add the `strict_lists` evaluation option (default `false`). When enabled, a dot path through a list and a list value in a scalar operation are errors instead of an implicit sum or list result. Without it, behaviour is unchanged.
- Support unary minus (`amount * -1`).
- `SUM`, `COUNT`, `ANY` and `ALL` are now reserved function names; a context field with one of these names can no longer be referenced as a bare identifier.

## 0.1.3

- Propagate NULL through arithmetic (`+`, `-`, `*`, `/`), `ROUND`, and `ABS`. A nil operand now yields nil instead of raising in `to_decimal/1`.

## 0.1.2

- Add `LEAST` and `GREATEST` functions with BigQuery NULL semantics (result is NULL if any argument is NULL). Support numbers, strings, dates, datetimes, and times.

## 0.1.1

- Add support for predicate-style identifiers ending in `?`, such as `enabled?`.

## 0.1.0

- Initial release.
