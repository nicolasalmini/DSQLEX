defmodule Dsqlex.Parser do
  # Arithmetic operators (split by precedence group)
  @additive_ops [:plus, :minus]
  @multiplicative_ops [:multiply, :divide]
  # Comparison operators
  @comparison_ops [:eq, :neq, :lt, :gt, :lte, :gte]

  def parse(tokens) do
    case parse_select(tokens) do
      {:ok, ast, []} -> {:ok, ast}
      {:ok, _ast, remaining} -> {:error, "Unexpected tokens: #{inspect(remaining)}"}
      error -> error
    end
  end

  # SELECT is optional - if present, consume it; if not, just parse the expression
  defp parse_select([{:keyword, :select} | rest]) do
    case parse_expression(rest) do
      {:ok, expr, rest} -> {:ok, {:select, expr}, rest}
      error -> error
    end
  end
  defp parse_select(tokens) do
    # No SELECT keyword - parse expression directly
    case parse_expression(tokens) do
      {:ok, expr, rest} -> {:ok, {:select, expr}, rest}
      error -> error
    end
  end

  # Expression: starts at the lowest precedence (logical)
  defp parse_expression(tokens), do: parse_logical(tokens)

  # ============================================================
  # LEVEL 1: Logical AND/OR (lowest precedence)
  # - Operates on comparison expressions
  # - Same-op chaining allowed (a AND b AND c)
  # - Mixing AND/OR requires parentheses
  # ============================================================
  defp parse_logical(tokens) do
    with {:ok, left, rest} <- parse_comparison(tokens) do
      maybe_parse_logical_op(left, rest)
    end
  end

  defp maybe_parse_logical_op(left, [{:keyword, :and} | rest]) do
    with {:ok, right, rest} <- parse_comparison(rest) do
      parse_and_chain({:binary_op, :and, left, right}, rest)
    end
  end
  defp maybe_parse_logical_op(left, [{:keyword, :or} | rest]) do
    with {:ok, right, rest} <- parse_comparison(rest) do
      parse_or_chain({:binary_op, :or, left, right}, rest)
    end
  end
  defp maybe_parse_logical_op(left, rest), do: {:ok, left, rest}

  # Continue AND chain
  defp parse_and_chain(left, [{:keyword, :and} | rest]) do
    with {:ok, right, rest} <- parse_comparison(rest) do
      parse_and_chain({:binary_op, :and, left, right}, rest)
    end
  end
  defp parse_and_chain(_left, [{:keyword, :or} | _]) do
    {:error, "Ambiguous expression: mixing AND/OR requires parentheses"}
  end
  defp parse_and_chain(left, rest), do: {:ok, left, rest}

  # Continue OR chain
  defp parse_or_chain(left, [{:keyword, :or} | rest]) do
    with {:ok, right, rest} <- parse_comparison(rest) do
      parse_or_chain({:binary_op, :or, left, right}, rest)
    end
  end
  defp parse_or_chain(_left, [{:keyword, :and} | _]) do
    {:error, "Ambiguous expression: mixing AND/OR requires parentheses"}
  end
  defp parse_or_chain(left, rest), do: {:ok, left, rest}

  # ============================================================
  # LEVEL 2: Comparison operators
  # - Operates on arithmetic expressions
  # - Only ONE comparison allowed (no chaining)
  # ============================================================
  defp parse_comparison(tokens) do
    with {:ok, left, rest} <- parse_arithmetic(tokens) do
      maybe_parse_comparison_op(left, rest)
    end
  end

  defp maybe_parse_comparison_op(left, [{:operator, op} | rest]) when op in @comparison_ops do
    with {:ok, right, rest} <- parse_arithmetic(rest) do
      # Check for chained comparisons (not allowed)
      case rest do
        [{:operator, op2} | _] when op2 in @comparison_ops ->
          {:error, "Cannot chain comparison operators. Use parentheses."}
        _ ->
          {:ok, {:binary_op, op, left, right}, rest}
      end
    end
  end
  # expr IN (val1, val2, ...)
  defp maybe_parse_comparison_op(left, [{:keyword, :in}, {:lparen} | rest]) do
    with {:ok, items, rest} <- parse_in_list(rest) do
      case rest do
        [{:rparen} | rest] -> {:ok, {:in, left, items}, rest}
        _ -> {:error, "Expected closing parenthesis ')' after IN list"}
      end
    end
  end

  # expr NOT IN (val1, val2, ...)
  defp maybe_parse_comparison_op(left, [{:keyword, :not}, {:keyword, :in}, {:lparen} | rest]) do
    with {:ok, items, rest} <- parse_in_list(rest) do
      case rest do
        [{:rparen} | rest] -> {:ok, {:not_in, left, items}, rest}
        _ -> {:error, "Expected closing parenthesis ')' after NOT IN list"}
      end
    end
  end

  # expr NOT LIKE pattern
  defp maybe_parse_comparison_op(left, [{:keyword, :not}, {:keyword, :like} | rest]) do
    with {:ok, pattern, rest} <- parse_primary(rest) do
      {:ok, {:not_like, left, pattern}, rest}
    end
  end

  # expr LIKE pattern
  defp maybe_parse_comparison_op(left, [{:keyword, :like} | rest]) do
    with {:ok, pattern, rest} <- parse_primary(rest) do
      {:ok, {:like, left, pattern}, rest}
    end
  end

  defp maybe_parse_comparison_op(left, rest), do: {:ok, left, rest}

  # ============================================================
  # LEVEL 3: Arithmetic operators
  # - Operates on primaries
  # - Same-group chaining allowed (a + b - c, a * b / c)
  # - Mixing additive (+/-) and multiplicative (*//) requires parentheses
  # ============================================================
  defp parse_arithmetic(tokens) do
    with {:ok, left, rest} <- parse_primary(tokens) do
      maybe_parse_arithmetic_op(left, rest)
    end
  end

  defp maybe_parse_arithmetic_op(left, [{:operator, op} | rest]) when op in @additive_ops do
    with {:ok, right, rest} <- parse_primary(rest) do
      parse_additive_chain({:binary_op, op, left, right}, rest)
    end
  end
  defp maybe_parse_arithmetic_op(left, [{:operator, op} | rest]) when op in @multiplicative_ops do
    with {:ok, right, rest} <- parse_primary(rest) do
      parse_multiplicative_chain({:binary_op, op, left, right}, rest)
    end
  end
  defp maybe_parse_arithmetic_op(left, rest), do: {:ok, left, rest}

  # Continue additive chain (+/-)
  defp parse_additive_chain(left, [{:operator, op} | rest]) when op in @additive_ops do
    with {:ok, right, rest} <- parse_primary(rest) do
      parse_additive_chain({:binary_op, op, left, right}, rest)
    end
  end
  defp parse_additive_chain(_left, [{:operator, op} | _]) when op in @multiplicative_ops do
    {:error, "Ambiguous expression: mixing +/- and *// requires parentheses"}
  end
  defp parse_additive_chain(left, rest), do: {:ok, left, rest}

  # Continue multiplicative chain (*//)
  defp parse_multiplicative_chain(left, [{:operator, op} | rest]) when op in @multiplicative_ops do
    with {:ok, right, rest} <- parse_primary(rest) do
      parse_multiplicative_chain({:binary_op, op, left, right}, rest)
    end
  end
  defp parse_multiplicative_chain(_left, [{:operator, op} | _]) when op in @additive_ops do
    {:error, "Ambiguous expression: mixing +/- and *// requires parentheses"}
  end
  defp parse_multiplicative_chain(left, rest), do: {:ok, left, rest}

  # ============================================================
  # LEVEL 4: Primary expressions (highest precedence)
  # ============================================================
  defp parse_primary([{:number, n} | rest]), do: {:ok, {:number, n}, rest}
  defp parse_primary([{:string, s} | rest]), do: {:ok, {:string, s}, rest}
  defp parse_primary([{:identifier, name} | rest]), do: {:ok, {:identifier, name}, rest}
  defp parse_primary([{:keyword, :null} | rest]), do: {:ok, {:null}, rest}
  defp parse_primary([{:keyword, :true} | rest]), do: {:ok, {:boolean, true}, rest}
  defp parse_primary([{:keyword, :false} | rest]), do: {:ok, {:boolean, false}, rest}

  # Parenthesized expression - resets to top level (logical)
  defp parse_primary([{:lparen} | rest]) do
    with {:ok, expr, rest} <- parse_expression(rest) do
      case rest do
        [{:rparen} | rest] -> {:ok, expr, rest}
        _ -> {:error, "Expected closing parenthesis ')'"}
      end
    end
  end

  # CASE WHEN ... THEN ... [WHEN ... THEN ...] [ELSE ...] END
  defp parse_primary([{:keyword, :case} | rest]) do
    with {:ok, when_clauses, rest} <- parse_when_clauses(rest),
         {:ok, else_clause, rest} <- parse_else_clause(rest),
         {:ok, rest} <- expect_keyword(:end, rest) do
      {:ok, {:case_expr, when_clauses, else_clause}, rest}
    end
  end

  # Function call: FUNCTION_NAME(arg1, arg2, ...)
  defp parse_primary([{:function, name}, {:lparen} | rest]) do
    with {:ok, args, rest} <- parse_function_args(rest) do
      case rest do
        [{:rparen} | rest] -> {:ok, {:call, name, args}, rest}
        _ -> {:error, "Expected closing parenthesis ')' after function arguments"}
      end
    end
  end

  defp parse_primary(tokens), do: {:error, "Unexpected token: #{inspect(tokens)}"}

  # ============================================================
  # IN list helpers
  # ============================================================

  # Parse comma-separated values inside IN (...)
  defp parse_in_list([{:rparen} | _] = tokens), do: {:ok, [], tokens}
  defp parse_in_list(tokens) do
    with {:ok, first, rest} <- parse_primary(tokens) do
      parse_more_in_items([first], rest)
    end
  end

  defp parse_more_in_items(items, [{:comma} | rest]) do
    with {:ok, item, rest} <- parse_primary(rest) do
      parse_more_in_items(items ++ [item], rest)
    end
  end
  defp parse_more_in_items(items, rest), do: {:ok, items, rest}

  # ============================================================
  # Function call helpers
  # ============================================================

  # Parse comma-separated arguments (can be empty)
  defp parse_function_args([{:rparen} | _] = tokens), do: {:ok, [], tokens}
  defp parse_function_args(tokens) do
    with {:ok, first_arg, rest} <- parse_expression(tokens) do
      parse_more_args([first_arg], rest)
    end
  end

  defp parse_more_args(args, [{:comma} | rest]) do
    with {:ok, arg, rest} <- parse_expression(rest) do
      parse_more_args(args ++ [arg], rest)
    end
  end
  defp parse_more_args(args, rest), do: {:ok, args, rest}

  # ============================================================
  # CASE/WHEN helpers
  # ============================================================

  # Parse one or more WHEN clauses
  defp parse_when_clauses(tokens) do
    case parse_when_clause(tokens) do
      {:ok, clause, rest} ->
        parse_more_when_clauses([clause], rest)
      {:error, _} = error ->
        error
    end
  end

  defp parse_more_when_clauses(clauses, [{:keyword, :when} | _] = tokens) do
    case parse_when_clause(tokens) do
      {:ok, clause, rest} ->
        parse_more_when_clauses(clauses ++ [clause], rest)
      {:error, _} = error ->
        error
    end
  end
  defp parse_more_when_clauses(clauses, rest), do: {:ok, clauses, rest}

  # Parse single: WHEN condition THEN result
  defp parse_when_clause([{:keyword, :when} | rest]) do
    with {:ok, condition, rest} <- parse_expression(rest),
         {:ok, rest} <- expect_keyword(:then, rest),
         {:ok, result, rest} <- parse_expression(rest) do
      {:ok, {:when, condition, result}, rest}
    end
  end
  defp parse_when_clause(_tokens), do: {:error, "Expected WHEN clause"}

  # Parse optional: ELSE result
  defp parse_else_clause([{:keyword, :else} | rest]) do
    parse_expression(rest)
  end
  defp parse_else_clause(rest), do: {:ok, nil, rest}

  # Helper to expect a specific keyword
  defp expect_keyword(expected, [{:keyword, actual} | rest]) when expected == actual do
    {:ok, rest}
  end
  defp expect_keyword(expected, tokens) do
    {:error, "Expected #{String.upcase(to_string(expected))}, got: #{inspect(Enum.take(tokens, 1))}"}
  end
end
