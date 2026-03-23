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
  - **Literals:** Numbers, strings, booleans, NULL

  ## Parentheses Rule

  To avoid ambiguity, complex expressions require parentheses:

      # Valid
      "1 + 2"
      "(1 + 2) * 3"
      "a = 1 AND b = 2 AND c = 3"

      # Invalid (ambiguous)
      "1 + 2 + 3"
      "a = 1 AND b = 2 OR c = 3"
  """

  alias Dsqlex.{Lexer, Parser, Evaluator}

  @doc """
  Evaluates an expression against a context.

  The `SELECT` keyword is optional.

  ## Parameters

  - `expression` - A string containing the expression
  - `context` - A map of field names (strings) to values

  ## Returns

  - `{:ok, result}` - The computed result
  - `{:error, reason}` - If lexing, parsing, or evaluation fails

  ## Examples

      iex> Dsqlex.eval("1 + 2", %{})
      {:ok, Decimal.new("3")}

      iex> Dsqlex.eval("x * 2", %{"x" => Decimal.new("50")})
      {:ok, Decimal.new("100")}
  """
  def eval(expression, context) when is_binary(expression) and is_map(context) do
    with {:ok, tokens} <- Lexer.tokenize(expression),
         {:ok, ast} <- Parser.parse(tokens),
         {:ok, result} <- Evaluator.evaluate(ast, context) do
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
