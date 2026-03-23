defmodule Dsqlex.Evaluator do
  @moduledoc """
  Evaluates a parsed AST against a context (map of field names to values).

  Example:
      context = %{
        "x" => Decimal.new("100.00"),
        "y" => Decimal.new("20.00"),
        "category" => "B",
        "z" => Decimal.new("5.00")
      }

      {:ok, ast} = Dsqlex.Parser.parse(tokens)
      {:ok, result} = Dsqlex.Evaluator.evaluate(ast, context)
  """

  def evaluate(ast, context) when is_map(context) do
    try do
      {:ok, do_eval(ast, context)}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # ============================================================
  # SELECT wrapper
  # ============================================================
  defp do_eval({:select, expr}, context), do: do_eval(expr, context)

  # ============================================================
  # Literals
  # ============================================================
  defp do_eval({:number, n}, _context), do: Decimal.new(n)
  defp do_eval({:string, s}, _context), do: s
  defp do_eval({:boolean, b}, _context), do: b
  defp do_eval({:null}, _context), do: nil

  # ============================================================
  # Identifier - lookup in context
  # ============================================================
  defp do_eval({:identifier, name}, context) do
    case Map.fetch(context, name) do
      {:ok, value} -> value
      :error -> raise "Unknown field: #{name}"
    end
  end

  # ============================================================
  # Binary operations - arithmetic
  # ============================================================
  defp do_eval({:binary_op, :plus, left, right}, context) do
    Decimal.add(to_decimal(do_eval(left, context)), to_decimal(do_eval(right, context)))
  end

  defp do_eval({:binary_op, :minus, left, right}, context) do
    Decimal.sub(to_decimal(do_eval(left, context)), to_decimal(do_eval(right, context)))
  end

  defp do_eval({:binary_op, :multiply, left, right}, context) do
    Decimal.mult(to_decimal(do_eval(left, context)), to_decimal(do_eval(right, context)))
  end

  defp do_eval({:binary_op, :divide, left, right}, context) do
    Decimal.div(to_decimal(do_eval(left, context)), to_decimal(do_eval(right, context)))
  end

  # ============================================================
  # Binary operations - comparison
  # ============================================================
  defp do_eval({:binary_op, :eq, left, right}, context) do
    compare_values(do_eval(left, context), do_eval(right, context)) == :eq
  end

  defp do_eval({:binary_op, :neq, left, right}, context) do
    compare_values(do_eval(left, context), do_eval(right, context)) != :eq
  end

  defp do_eval({:binary_op, :lt, left, right}, context) do
    compare_values(do_eval(left, context), do_eval(right, context)) == :lt
  end

  defp do_eval({:binary_op, :gt, left, right}, context) do
    compare_values(do_eval(left, context), do_eval(right, context)) == :gt
  end

  defp do_eval({:binary_op, :lte, left, right}, context) do
    compare_values(do_eval(left, context), do_eval(right, context)) in [:lt, :eq]
  end

  defp do_eval({:binary_op, :gte, left, right}, context) do
    compare_values(do_eval(left, context), do_eval(right, context)) in [:gt, :eq]
  end

  # ============================================================
  # Binary operations - logical
  # ============================================================
  defp do_eval({:binary_op, :and, left, right}, context) do
    do_eval(left, context) && do_eval(right, context)
  end

  defp do_eval({:binary_op, :or, left, right}, context) do
    do_eval(left, context) || do_eval(right, context)
  end

  # ============================================================
  # CASE expression
  # ============================================================
  defp do_eval({:case_expr, when_clauses, else_clause}, context) do
    eval_when_clauses(when_clauses, else_clause, context)
  end

  # ============================================================
  # Function calls
  # ============================================================
  defp do_eval({:call, :round, [value, precision]}, context) do
    Decimal.round(to_decimal(do_eval(value, context)), do_eval(precision, context) |> Decimal.to_integer())
  end

  defp do_eval({:call, :coalesce, args}, context) do
    Enum.find_value(args, fn arg ->
      result = do_eval(arg, context)
      if result != nil, do: result, else: nil
    end)
  end

  defp do_eval({:call, :upper, [value]}, context) do
    do_eval(value, context) |> to_string() |> String.upcase()
  end

  defp do_eval({:call, :lower, [value]}, context) do
    do_eval(value, context) |> to_string() |> String.downcase()
  end

  defp do_eval({:call, :abs, [value]}, context) do
    Decimal.abs(to_decimal(do_eval(value, context)))
  end

  defp do_eval({:call, :concat, args}, context) do
    args
    |> Enum.map(&do_eval(&1, context))
    |> Enum.map(&to_string/1)
    |> Enum.join()
  end

  # ============================================================
  # CASE/WHEN helpers
  # ============================================================
  defp eval_when_clauses([], else_clause, context) do
    if else_clause do
      do_eval(else_clause, context)
    else
      nil
    end
  end

  defp eval_when_clauses([{:when, condition, result} | rest], else_clause, context) do
    if do_eval(condition, context) do
      do_eval(result, context)
    else
      eval_when_clauses(rest, else_clause, context)
    end
  end

  # ============================================================
  # Helpers
  # ============================================================
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(s) when is_binary(s), do: Decimal.new(s)

  defp compare_values(%Decimal{} = a, %Decimal{} = b), do: Decimal.compare(a, b)
  defp compare_values(%Decimal{} = a, b), do: Decimal.compare(a, to_decimal(b))
  defp compare_values(a, %Decimal{} = b), do: Decimal.compare(to_decimal(a), b)
  defp compare_values(a, b) when is_binary(a) and is_binary(b) do
    cond do
      a == b -> :eq
      a < b -> :lt
      a > b -> :gt
    end
  end
  defp compare_values(a, b) when a == b, do: :eq
  defp compare_values(a, b) when a < b, do: :lt
  defp compare_values(a, b) when a > b, do: :gt
end
