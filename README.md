# DSQLEX

A SQL-like DSL (Domain Specific Language) for evaluating dynamic calculations in Elixir.

**DSQLEX** allows users to define calculation expressions using familiar SQL syntax, which can be stored, validated, and evaluated at runtime against structured data.

## Features

- 🧮 **Arithmetic operations**: `+`, `-`, `*`, `/` with Decimal precision
- 🔍 **Comparisons**: `=`, `!=`, `<`, `>`, `<=`, `>=`
- 🔗 **Logical operators**: `AND`, `OR` with same-operator chaining
- 🔀 **Conditional logic**: `CASE WHEN ... THEN ... ELSE ... END`
- 📦 **Built-in functions**: `ROUND()`, `COALESCE()`, `UPPER()`, `LOWER()`, `ABS()`, `CONCAT()`
- ✅ **Validation**: Parse expressions before storing to catch syntax errors early
- 🎯 **Unambiguous syntax**: Parentheses required for complex expressions
- 💬 **Comments**: SQL-style line comments (`-- ...`, `# ...`) and block comments (`/* ... */`)

## Installation

Add `dsqlex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dsqlex, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Define your data context
context = %{
  "price" => Decimal.new("500.00"),
  "quantity" => Decimal.new("4"),
  "category" => "B",
  "rate" => Decimal.new("5.00")
}

# Evaluate a simple expression (SELECT is optional)
{:ok, result} = Dsqlex.eval("price / rate", context)
# => {:ok, Decimal.new("100")}

# Evaluate a conditional expression
{:ok, result} = Dsqlex.eval("""
  CASE 
    WHEN category = 'A' THEN quantity 
    WHEN category != 'A' THEN (price / rate) 
  END
""", context)
# => {:ok, Decimal.new("100")}
```

## API

### `Dsqlex.eval(expression, context)`

Evaluates an expression against a context and returns the result. The `SELECT` keyword is optional.

```elixir
{:ok, result} = Dsqlex.eval("x * 2", %{"x" => Decimal.new("50")})
# => {:ok, Decimal.new("100")}

{:error, reason} = Dsqlex.eval("unknown_field", %{})
# => {:error, "Unknown field: unknown_field"}
```

### `Dsqlex.parse(expression)`

Parses an expression and returns the AST without evaluating. Useful for validating expressions before storing them in a database.

```elixir
{:ok, ast} = Dsqlex.parse("x / y")
# => {:ok, {:select, {:binary_op, :divide, {:identifier, "x"}, {:identifier, "y"}}}}

{:ok, ast} = Dsqlex.parse("1 + 2 + 3")
# => {:ok, {:select, {:binary_op, :plus, {:binary_op, :plus, {:number, "1"}, {:number, "2"}}, {:number, "3"}}}}


{:error, reason} = Dsqlex.parse("1 + 2 * 3")
# => {:error, "Ambiguous expression: mixing +/- and *// requires parentheses"}
```

### `Dsqlex.tokenize(expression)`

Tokenizes an expression without parsing. Useful for debugging.

```elixir
{:ok, tokens} = Dsqlex.tokenize("1 + 2")
# => {:ok, [number: "1", operator: :plus, number: "2"]}
```

## Supported Syntax

### Literals

| Type | Examples |
|------|----------|
| Numbers | `42`, `3.14`, `0.5` |
| Strings | `'hello'`, `'world'` |
| Booleans | `TRUE`, `FALSE` |
| Null | `NULL` |

### Comments

| Style | Description |
|-------|-------------|
| `-- ...` | SQL line comment, runs to end of line |
| `# ...` | MySQL-style line comment, runs to end of line |
| `/* ... */` | Block comment, may span multiple lines |

Comments are stripped at the lexer stage and never reach the parser, so they may
appear anywhere whitespace is allowed and may contain any characters (including
non-ASCII text) in their bodies.

```sql
status_id NOT IN (
  1,  -- pending review
  2,  -- archived – soft-deleted
  3   -- naïve test
)
```

### Arithmetic Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `+` | Addition | `SELECT a + b` |
| `-` | Subtraction | `SELECT a - b` |
| `*` | Multiplication | `SELECT a * b` |
| `/` | Division | `SELECT a / b` |

### Comparison Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `=` | Equal | `SELECT a = b` |
| `!=` | Not equal | `SELECT a != b` |
| `<` | Less than | `SELECT a < b` |
| `>` | Greater than | `SELECT a > b` |
| `<=` | Less than or equal | `SELECT a <= b` |
| `>=` | Greater than or equal | `SELECT a >= b` |

### Logical Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `AND` | Logical AND | `SELECT a = 1 AND b = 2` |
| `OR` | Logical OR | `SELECT a = 1 OR b = 2` |

**Note:** You can chain the same operator (`a AND b AND c`), but mixing `AND`/`OR` requires parentheses.

### CASE/WHEN

```sql
CASE 
  WHEN condition1 THEN result1
  WHEN condition2 THEN result2
  ELSE default_result
END
```

### Functions

| Function | Description | Example |
|----------|-------------|---------|
| `ROUND(value, precision)` | Round to decimal places | `ROUND(x, 2)` |
| `COALESCE(a, b, ...)` | Return first non-null | `COALESCE(a, b, 0)` |
| `UPPER(string)` | Convert to uppercase | `UPPER(x)` |
| `LOWER(string)` | Convert to lowercase | `LOWER(x)` |
| `ABS(number)` | Absolute value | `ABS(x)` |
| `CONCAT(a, b, ...)` | Concatenate strings | `CONCAT(a, ' ', b)` |

## The Parentheses Rule

To eliminate ambiguity and ensure calculation correctness, DSQLEX requires parentheses when mixing operator groups:

```elixir
# ✅ Valid - single operation
"SELECT a + b"
"SELECT a = 1"

# ✅ Valid - chaining the same operator group
"SELECT a + b + c"        # additive chain, left-associative: (a+b)+c
"SELECT a - b + c"        # additive chain
"SELECT a * b / c"        # multiplicative chain, left-associative: (a*b)/c

# ✅ Valid - parentheses make intent clear
"SELECT (a + b) * c"
"SELECT (a = 1 AND b = 2) OR c = 3"

# ✅ Valid - same logical operator can chain
"SELECT a = 1 AND b = 2 AND c = 3"
"SELECT a = 1 OR b = 2 OR c = 3"

# ❌ Invalid - mixing operator groups requires parentheses
"SELECT a + b * c"        # mixing additive and multiplicative
"SELECT a = 1 AND b = 2 OR c = 3"  # mixing AND/OR
```

This design choice prioritizes **correctness over convenience** — mixed-precedence expressions must use parentheses to make the intended order of operations explicit.

## Examples

### Conditional Selection

```elixir
expression = """
  CASE 
    WHEN category = 'A' THEN x 
    WHEN category != 'A' THEN (y / z) 
  END
"""

context = %{
  "x" => Decimal.new("100.00"),
  "y" => Decimal.new("500.00"),
  "category" => "B",
  "z" => Decimal.new("5.00")
}

{:ok, result} = Dsqlex.eval(expression, context)
# => {:ok, Decimal.new("100")}
```

### Tiered Calculation

```elixir
expression = """
  CASE 
    WHEN x > 1000 THEN ROUND(x * 0.02, 2)
    WHEN x > 100 THEN ROUND(x * 0.03, 2)
    ELSE ROUND(x * 0.05, 2)
  END
"""

{:ok, result} = Dsqlex.eval(expression, %{"x" => Decimal.new("500")})
# => {:ok, Decimal.new("15.00")}
```

### Null Handling

```elixir
expression = "ROUND(COALESCE(x, 0) + y, 2)"

context = %{
  "x" => nil,
  "y" => Decimal.new("99.99")
}

{:ok, result} = Dsqlex.eval(expression, context)
# => {:ok, Decimal.new("99.99")}
```

### Conditional Text

```elixir
expression = """
  CASE 
    WHEN status = 'active' THEN UPPER(label)
    ELSE 'INACTIVE'
  END
"""

{:ok, result} = Dsqlex.eval(expression, %{"status" => "active", "label" => "hello world"})
# => {:ok, "HELLO WORLD"}
```

## Architecture

DSQLEX uses a classic three-stage pipeline:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   String    │ ──► │   Tokens    │ ──► │     AST     │ ──► Result
│             │     │             │     │             │
│  "SELECT    │     │ [{:keyword, │     │ {:select,   │
│   a + b"    │     │   :select}, │     │  {:binary_  │
│             │     │  ...]       │     │   op, ...}} │
└─────────────┘     └─────────────┘     └─────────────┘
     Lexer              Parser            Evaluator
```

- **Lexer** (`Dsqlex.Lexer`): Converts string to tokens
- **Parser** (`Dsqlex.Parser`): Converts tokens to AST
- **Evaluator** (`Dsqlex.Evaluator`): Walks AST with context to produce result

## Testing

```bash
mix test
```

The test suite includes 162 tests covering:
- Lexer token generation
- Parser AST construction
- Evaluator computations
- End-to-end integration tests
- Error handling at every stage

## License

MIT
