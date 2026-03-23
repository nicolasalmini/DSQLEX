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

  def evaluate(ast, context, opts \\ []) when is_map(context) do
    try do
      {:ok, do_eval(ast, context, opts)}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # ============================================================
  # SELECT wrapper
  # ============================================================
  defp do_eval({:select, expr}, context, opts), do: do_eval(expr, context, opts)

  # ============================================================
  # Literals
  # ============================================================
  defp do_eval({:number, n}, _context, _opts), do: Decimal.new(n)
  defp do_eval({:string, s}, _context, _opts), do: s
  defp do_eval({:boolean, b}, _context, _opts), do: b
  defp do_eval({:null}, _context, _opts), do: nil

  # ============================================================
  # Identifier - lookup in context
  # ============================================================
  defp do_eval({:identifier, name}, context, opts) do
    case Map.fetch(context, name) do
      {:ok, value} ->
        value

      :error ->
        # Try dot-path access for nested maps (e.g. "spread.recognition.payment_percentage")
        if String.contains?(name, ".") do
          resolve_dot_path(name, context)
        else
          resolver = Keyword.get(opts, :resolver)

          if resolver do
            visited = Keyword.get(opts, :visited, MapSet.new())

            if MapSet.member?(visited, name) do
              raise "Circular reference detected: #{name}"
            end

            case resolver.(name, visited) do
              {:ok, value} -> value
              {:error, reason} -> raise reason
            end
          else
            raise "Unknown field: #{name}"
          end
        end
    end
  end

  defp resolve_dot_path(path, context) do
    parts = String.split(path, ".")

    Enum.reduce(parts, context, fn key, acc ->
      cond do
        is_map(acc) && Map.has_key?(acc, key) -> Map.get(acc, key)
        is_map(acc) -> raise "Unknown field: #{path} (failed at '#{key}')"
        true -> raise "Cannot access '#{key}' on non-map value in path '#{path}'"
      end
    end)
  end

  # ============================================================
  # Binary operations - arithmetic
  # ============================================================
  defp do_eval({:binary_op, :plus, left, right}, context, opts) do
    Decimal.add(to_decimal(do_eval(left, context, opts)), to_decimal(do_eval(right, context, opts)))
  end

  defp do_eval({:binary_op, :minus, left, right}, context, opts) do
    Decimal.sub(to_decimal(do_eval(left, context, opts)), to_decimal(do_eval(right, context, opts)))
  end

  defp do_eval({:binary_op, :multiply, left, right}, context, opts) do
    Decimal.mult(to_decimal(do_eval(left, context, opts)), to_decimal(do_eval(right, context, opts)))
  end

  defp do_eval({:binary_op, :divide, left, right}, context, opts) do
    Decimal.div(to_decimal(do_eval(left, context, opts)), to_decimal(do_eval(right, context, opts)))
  end

  # ============================================================
  # Binary operations - comparison
  # ============================================================
  defp do_eval({:binary_op, :eq, left, right}, context, opts) do
    compare_values(do_eval(left, context, opts), do_eval(right, context, opts)) == :eq
  end

  defp do_eval({:binary_op, :neq, left, right}, context, opts) do
    compare_values(do_eval(left, context, opts), do_eval(right, context, opts)) != :eq
  end

  defp do_eval({:binary_op, :lt, left, right}, context, opts) do
    compare_values(do_eval(left, context, opts), do_eval(right, context, opts)) == :lt
  end

  defp do_eval({:binary_op, :gt, left, right}, context, opts) do
    compare_values(do_eval(left, context, opts), do_eval(right, context, opts)) == :gt
  end

  defp do_eval({:binary_op, :lte, left, right}, context, opts) do
    compare_values(do_eval(left, context, opts), do_eval(right, context, opts)) in [:lt, :eq]
  end

  defp do_eval({:binary_op, :gte, left, right}, context, opts) do
    compare_values(do_eval(left, context, opts), do_eval(right, context, opts)) in [:gt, :eq]
  end

  # ============================================================
  # Binary operations - logical
  # ============================================================
  defp do_eval({:binary_op, :and, left, right}, context, opts) do
    do_eval(left, context, opts) && do_eval(right, context, opts)
  end

  defp do_eval({:binary_op, :or, left, right}, context, opts) do
    do_eval(left, context, opts) || do_eval(right, context, opts)
  end

  # ============================================================
  # CASE expression
  # ============================================================
  defp do_eval({:case_expr, when_clauses, else_clause}, context, opts) do
    eval_when_clauses(when_clauses, else_clause, context, opts)
  end

  # ============================================================
  # Function calls
  # ============================================================
  defp do_eval({:call, :round, [value, precision]}, context, opts) do
    Decimal.round(to_decimal(do_eval(value, context, opts)), do_eval(precision, context, opts) |> Decimal.to_integer())
  end

  defp do_eval({:call, :coalesce, args}, context, opts) do
    Enum.find_value(args, fn arg ->
      result = do_eval(arg, context, opts)
      if result != nil, do: result, else: nil
    end)
  end

  defp do_eval({:call, :upper, [value]}, context, opts) do
    do_eval(value, context, opts) |> to_string() |> String.upcase()
  end

  defp do_eval({:call, :lower, [value]}, context, opts) do
    do_eval(value, context, opts) |> to_string() |> String.downcase()
  end

  defp do_eval({:call, :abs, [value]}, context, opts) do
    Decimal.abs(to_decimal(do_eval(value, context, opts)))
  end

  defp do_eval({:call, :concat, args}, context, opts) do
    args
    |> Enum.map(&do_eval(&1, context, opts))
    |> Enum.map(&to_string/1)
    |> Enum.join()
  end

  # EVENT(type, subtype) — evaluate referenced formula with current context
  defp do_eval({:call, :event, [{:identifier, type}, {:identifier, subtype}]}, context, opts) do
    resolve_event(type, subtype, context, opts)
  end

  # EVENT(type, subtype, context_source) — evaluate referenced formula with sub-entity context
  # If context_source resolves to a list, evaluates per item and sums the results
  defp do_eval({:call, :event, [{:identifier, type}, {:identifier, subtype}, {:identifier, source}]}, context, opts) do
    case Map.fetch(context, source) do
      {:ok, sub_context} when is_list(sub_context) ->
        sub_context
        |> Enum.map(fn item -> resolve_event(type, subtype, item, opts) end)
        |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

      {:ok, sub_context} when is_map(sub_context) ->
        resolve_event(type, subtype, sub_context, opts)

      {:ok, _} ->
        raise "EVENT context source '#{source}' must be a map or list of maps"

      :error ->
        raise "EVENT context source '#{source}' not found in context"
    end
  end

  defp do_eval({:call, :event, _args}, _context, _opts) do
    raise "EVENT requires 2 or 3 arguments: EVENT(type, subtype) or EVENT(type, subtype, context_source)"
  end

  defp resolve_event(type, subtype, eval_context, opts) do
    event_resolver = Keyword.get(opts, :event_resolver)

    unless event_resolver do
      raise "EVENT() calls require an :event_resolver option"
    end

    event_key = "#{type}.#{subtype}"
    visited = Keyword.get(opts, :visited, MapSet.new())

    if MapSet.member?(visited, event_key) do
      raise "Circular reference detected: #{event_key}"
    end

    new_visited = MapSet.put(visited, event_key)
    new_opts = Keyword.put(opts, :visited, new_visited)

    case event_resolver.(type, subtype, eval_context, new_opts) do
      {:ok, result} -> result
      {:error, reason} -> raise reason
    end
  end

  # ============================================================
  # CASE/WHEN helpers
  # ============================================================
  defp eval_when_clauses([], else_clause, context, opts) do
    if else_clause do
      do_eval(else_clause, context, opts)
    else
      nil
    end
  end

  defp eval_when_clauses([{:when, condition, result} | rest], else_clause, context, opts) do
    if do_eval(condition, context, opts) do
      do_eval(result, context, opts)
    else
      eval_when_clauses(rest, else_clause, context, opts)
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
