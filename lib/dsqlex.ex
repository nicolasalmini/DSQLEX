defmodule Dsqlex do
  @moduledoc """
  DSQLEX - A SQL-like DSL for evaluating calculations in Elixir.

  ## Usage

      # Define a calculation expression (SELECT is optional)
      expression = "CASE WHEN category = 'A' THEN x ELSE (y / z) END"

      # Create a context with your data
      context = %{
        "x" => Decimal.new("100.00"),
        "y" => Decimal.new("500.00"),
        "category" => "B",
        "z" => Decimal.new("5.00")
      }

      # Evaluate!
      {:ok, result} = Dsqlex.eval(expression, context)
      # => {:ok, Decimal.new("100")}

  ## Supported Features

  - **Arithmetic:** `+`, `-`, `*`, `/`
  - **Comparison:** `=`, `!=`, `<`, `>`, `<=`, `>=`
  - **Logical:** `AND`, `OR` (same-operator chaining allowed)
  - **Control flow:** `CASE WHEN ... THEN ... ELSE ... END`
  - **Functions:** `ROUND()`, `COALESCE()`, `UPPER()`, `LOWER()`, `ABS()`, `CONCAT()`
  - **List aggregation:** `SUM(list, expr)`, `COUNT(list)`, `COUNT(list, cond)`, `ANY(list, cond)`, `ALL(list, cond)`
  - **Literals:** Numbers, strings, booleans, NULL

  ## List Aggregation

  `list` is a field (dot paths allowed) holding a list of maps. The second argument is
  evaluated once per element: bare identifiers read the element, and `ROOT.<path>` reads
  the context the expression was evaluated against (in nested aggregations `ROOT` is
  still that outermost context). `ROOT` is undefined outside an aggregation.

      context = %{
        "cutoff_date" => "2024-03-10",
        "items" => [
          %{"amount" => Decimal.new("100"), "shipped_on" => "2024-03-01"},
          %{"amount" => Decimal.new("40"), "shipped_on" => "2024-03-15"}
        ]
      }

      Dsqlex.eval("SUM(items, CASE WHEN shipped_on <= ROOT.cutoff_date THEN amount ELSE 0 END)", context)
      # => {:ok, Decimal.new("100")}

  - `SUM` returns a Decimal (zero for an empty list). A nil element result is an error
    naming the element index; return `0` for elements that contribute nothing.
  - `COUNT(list)` counts elements, `COUNT(list, cond)` counts elements whose condition is truthy.
  - `ANY` is false and `ALL` is true for an empty list.
  - Conditions follow the usual truthiness: only `NULL` and `FALSE` are falsy.
  - The list argument must resolve to a list of maps and must not itself pass through a list.

  ## Strict Lists

  Without the option, a dot path through a list (`items.amount`) maps the rest of the path
  over the elements and sums the results when all are numeric, otherwise returns the list.
  Pass `strict_lists: true` to make that an error that points at the list functions, and to
  reject list values in comparisons, arithmetic, `ROUND`, `ABS`, `CONCAT`, `UPPER`, `LOWER`,
  `LIKE`, `IN`, `LEAST` and `GREATEST`:

      Dsqlex.eval("items.amount", context, strict_lists: true)
      # => {:error, "Cannot read 'amount' through list field 'items'; use SUM(items, amount) or another list function (COUNT, ANY, ALL)"}

  ## Parentheses Rule

  To avoid ambiguity, expressions that mix operator groups require parentheses:

      # Valid
      "1 + 2"
      "1 + 2 + 3"
      "(1 + 2) * 3"
      "a = 1 AND b = 2 AND c = 3"

      # Invalid (ambiguous)
      "1 + 2 * 3"
      "a = 1 AND b = 2 OR c = 3"
  """

  alias Dsqlex.{Lexer, Parser, Evaluator}

  @doc """
  Evaluates an expression against a context.

  The `SELECT` keyword is optional.

  ## Parameters

  - `expression` - A string containing the expression
  - `context` - A map of field names (strings) to values
  - `opts` - Evaluation options:
    - `:strict_lists` - reject dot paths through lists and list values in scalar
      operations (default `false`)
    - `:event_resolver` - function used to evaluate `EVENT()` calls

  ## Returns

  - `{:ok, result}` - The computed result
  - `{:error, reason}` - If lexing, parsing, or evaluation fails

  ## Examples

      iex> Dsqlex.eval("1 + 2", %{})
      {:ok, Decimal.new("3")}

      iex> Dsqlex.eval("x * 2", %{"x" => Decimal.new("50")})
      {:ok, Decimal.new("100")}
  """
  def eval(expression, context, opts \\ []) when is_binary(expression) and is_map(context) do
    with {:ok, tokens} <- Lexer.tokenize(expression),
         {:ok, ast} <- Parser.parse(tokens),
         {:ok, result} <- Evaluator.evaluate(ast, context, opts) do
      {:ok, result}
    end
  end

  @doc """
  Parses an expression and returns the AST without evaluating.

  Useful for validating expressions before storing them.
  The `SELECT` keyword is optional.

  ## Examples

      iex> Dsqlex.parse("x / y")
      {:ok, {:select, {:binary_op, :divide, {:identifier, "x"}, {:identifier, "y"}}}}
  """
  def parse(expression) when is_binary(expression) do
    with {:ok, tokens} <- Lexer.tokenize(expression) do
      Parser.parse(tokens)
    end
  end

  @doc """
  Tokenizes an expression without parsing.

  Useful for debugging or inspecting the lexer output.
  """
  def tokenize(expression) when is_binary(expression) do
    Lexer.tokenize(expression)
  end
end
