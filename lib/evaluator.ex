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
  # (optional) SELECT wrapper
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
        # Try dot-path access for nested maps (e.g. "config.pricing.margin_rate")
        if String.contains?(name, ".") do
          resolve_dot_path(name, context, opts)
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

  # ============================================================
  # Binary operations - arithmetic
  # ============================================================
  defp do_eval({:binary_op, :plus, left, right}, context, opts) do
    decimal_binop(&Decimal.add/2, left, right, context, opts)
  end

  defp do_eval({:binary_op, :minus, left, right}, context, opts) do
    decimal_binop(&Decimal.sub/2, left, right, context, opts)
  end

  defp do_eval({:binary_op, :multiply, left, right}, context, opts) do
    decimal_binop(&Decimal.mult/2, left, right, context, opts)
  end

  defp do_eval({:binary_op, :divide, left, right}, context, opts) do
    decimal_binop(&Decimal.div/2, left, right, context, opts)
  end

  defp do_eval({:unary_op, :minus, operand}, context, opts) do
    case eval_scalar(operand, context, opts) do
      nil -> nil
      value -> Decimal.negate(to_decimal(value))
    end
  end

  # ============================================================
  # Binary operations - comparison
  # ============================================================
  defp do_eval({:binary_op, :eq, left, right}, context, opts) do
    compare_values(eval_scalar(left, context, opts), eval_scalar(right, context, opts)) == :eq
  end

  defp do_eval({:binary_op, :neq, left, right}, context, opts) do
    compare_values(eval_scalar(left, context, opts), eval_scalar(right, context, opts)) != :eq
  end

  defp do_eval({:binary_op, :lt, left, right}, context, opts) do
    compare_values(eval_scalar(left, context, opts), eval_scalar(right, context, opts)) == :lt
  end

  defp do_eval({:binary_op, :gt, left, right}, context, opts) do
    compare_values(eval_scalar(left, context, opts), eval_scalar(right, context, opts)) == :gt
  end

  defp do_eval({:binary_op, :lte, left, right}, context, opts) do
    compare_values(eval_scalar(left, context, opts), eval_scalar(right, context, opts)) in [:lt, :eq]
  end

  defp do_eval({:binary_op, :gte, left, right}, context, opts) do
    compare_values(eval_scalar(left, context, opts), eval_scalar(right, context, opts)) in [:gt, :eq]
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
  # IN / NOT IN
  # ============================================================
  defp do_eval({:in, expr, items}, context, opts) do
    value = eval_scalar(expr, context, opts)
    Enum.any?(items, fn item -> compare_values(value, eval_scalar(item, context, opts)) == :eq end)
  end

  defp do_eval({:not_in, expr, items}, context, opts) do
    value = eval_scalar(expr, context, opts)
    not Enum.any?(items, fn item -> compare_values(value, eval_scalar(item, context, opts)) == :eq end)
  end

  # ============================================================
  # LIKE / NOT LIKE (case-insensitive, MySQL/MariaDB default)
  # ============================================================
  defp do_eval({:like, expr, pattern_expr}, context, opts) do
    value = eval_scalar(expr, context, opts) |> to_string()
    pattern = eval_scalar(pattern_expr, context, opts) |> to_string()
    like_match?(value, pattern)
  end

  defp do_eval({:not_like, expr, pattern_expr}, context, opts) do
    value = eval_scalar(expr, context, opts) |> to_string()
    pattern = eval_scalar(pattern_expr, context, opts) |> to_string()
    not like_match?(value, pattern)
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
    case {eval_scalar(value, context, opts), eval_scalar(precision, context, opts)} do
      {nil, _} -> nil
      {_, nil} -> nil
      {v, p} -> Decimal.round(to_decimal(v), to_decimal(p) |> Decimal.to_integer())
    end
  end

  defp do_eval({:call, :coalesce, args}, context, opts) do
    Enum.find_value(args, fn arg ->
      result = do_eval(arg, context, opts)
      if result != nil, do: result, else: nil
    end)
  end

  defp do_eval({:call, :upper, [value]}, context, opts) do
    eval_scalar(value, context, opts) |> to_string() |> String.upcase()
  end

  defp do_eval({:call, :lower, [value]}, context, opts) do
    eval_scalar(value, context, opts) |> to_string() |> String.downcase()
  end

  defp do_eval({:call, :abs, [value]}, context, opts) do
    case eval_scalar(value, context, opts) do
      nil -> nil
      v -> Decimal.abs(to_decimal(v))
    end
  end

  defp do_eval({:call, :concat, args}, context, opts) do
    args
    |> Enum.map(&eval_scalar(&1, context, opts))
    |> Enum.map(&to_string/1)
    |> Enum.join()
  end

  # LEAST/GREATEST — return the smallest/largest argument.
  # Following BigQuery semantics: if ANY argument is NULL, the result is NULL.
  defp do_eval({:call, :least, args}, context, opts) do
    pick_extreme(:least, args, context, opts)
  end

  defp do_eval({:call, :greatest, args}, context, opts) do
    pick_extreme(:greatest, args, context, opts)
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

  # ============================================================
  # List aggregations - evaluate an expression once per element of a list of maps.
  # Bare identifiers resolve in the element; ROOT.<path> resolves in the formula's root context.
  # ============================================================
  defp do_eval({:call, :sum, [{:identifier, source}, expr]}, context, opts) do
    aggregate(:sum, source, expr, context, opts)
  end

  defp do_eval({:call, :sum, _args}, _context, _opts) do
    raise "SUM requires (list_field, expression)"
  end

  defp do_eval({:call, :count, [{:identifier, source}]}, context, opts) do
    aggregate(:count, source, {:boolean, true}, context, opts)
  end

  defp do_eval({:call, :count, [{:identifier, source}, condition]}, context, opts) do
    aggregate(:count, source, condition, context, opts)
  end

  defp do_eval({:call, :count, _args}, _context, _opts) do
    raise "COUNT requires (list_field) or (list_field, condition)"
  end

  defp do_eval({:call, :any, [{:identifier, source}, condition]}, context, opts) do
    aggregate(:any, source, condition, context, opts)
  end

  defp do_eval({:call, :any, _args}, _context, _opts) do
    raise "ANY requires (list_field, condition)"
  end

  defp do_eval({:call, :all, [{:identifier, source}, condition]}, context, opts) do
    aggregate(:all, source, condition, context, opts)
  end

  defp do_eval({:call, :all, _args}, _context, _opts) do
    raise "ALL requires (list_field, condition)"
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
    new_opts = opts |> Keyword.put(:visited, new_visited) |> Keyword.delete(:aggregation_root)

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

  # LEAST/GREATEST: NULL propagates (BigQuery semantics). Otherwise reduce by comparison.
  defp pick_extreme(_kind, [], _context, _opts) do
    raise "LEAST/GREATEST requires at least one argument"
  end

  defp pick_extreme(kind, args, context, opts) do
    values = Enum.map(args, &eval_scalar(&1, context, opts))

    if Enum.any?(values, &is_nil/1) do
      nil
    else
      target = if kind == :least, do: :lt, else: :gt

      Enum.reduce(values, fn value, acc ->
        if compare_values(value, acc) == target, do: value, else: acc
      end)
    end
  end

  defp decimal_binop(fun, left, right, context, opts) do
    left_val = eval_scalar(left, context, opts)
    right_val = eval_scalar(right, context, opts)

    if is_nil(left_val) or is_nil(right_val) do
      nil
    else
      fun.(to_decimal(left_val), to_decimal(right_val))
    end
  end

  defp eval_scalar(node, context, opts) do
    value = do_eval(node, context, opts)

    if is_list(value) and Keyword.get(opts, :strict_lists, false) do
      raise "List value where a scalar was expected (#{operand_name(node)}); use SUM, COUNT, ANY or ALL"
    end

    value
  end

  defp operand_name({:identifier, name}), do: name
  defp operand_name(_node), do: "expression"

  defp aggregate(fun, source, expr, context, opts) do
    name = fun |> Atom.to_string() |> String.upcase()
    root = Keyword.get(opts, :aggregation_root, context)
    element_opts = Keyword.put(opts, :aggregation_root, root)

    results =
      source
      |> aggregation_list(name, context, opts)
      |> Stream.with_index()
      |> Stream.map(fn {element, index} ->
        {do_eval(expr, Map.put(element, "ROOT", root), element_opts), index}
      end)

    case fun do
      :sum ->
        Enum.reduce(results, Decimal.new(0), fn {value, index}, acc ->
          Decimal.add(acc, sum_operand(value, source, index))
        end)

      :count -> results |> Enum.count(fn {value, _index} -> value end) |> Decimal.new()
      :any -> Enum.any?(results, fn {value, _index} -> value end)
      :all -> Enum.all?(results, fn {value, _index} -> value end)
    end
  end

  defp aggregation_list(source, name, context, opts) do
    case do_eval({:identifier, source}, context, Keyword.put(opts, :strict_lists, true)) do
      list when is_list(list) ->
        case Enum.find_index(list, fn element -> not is_map(element) or is_struct(element) end) do
          nil -> list
          index -> raise "#{name} source '#{source}' element #{index} is not a map"
        end

      other ->
        raise "#{name} source '#{source}' must be a list of maps (got #{type_name(other)})"
    end
  end

  defp sum_operand(nil, source, index) do
    raise "SUM(#{source}, …) element #{index} evaluated to nil; return 0 for elements that contribute nothing"
  end

  defp sum_operand(value, source, index) do
    if decimal_like?(value) do
      to_decimal(value)
    else
      raise "SUM(#{source}, …) element #{index} evaluated to a non-numeric value (#{inspect(value)})"
    end
  end

  defp type_name(nil), do: "nil"
  defp type_name(%module{}), do: inspect(module)
  defp type_name(value) when is_map(value), do: "map"
  defp type_name(value) when is_binary(value), do: "string"
  defp type_name(value) when is_boolean(value), do: "boolean"
  defp type_name(value) when is_number(value), do: "number"
  defp type_name(value), do: inspect(value)

  defp to_decimal(nil), do: nil
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(s) when is_binary(s), do: Decimal.new(s)

  defp compare_values(nil, nil), do: :eq
  defp compare_values(nil, _), do: :neq
  defp compare_values(_, nil), do: :neq
  defp compare_values(%Decimal{} = a, %Decimal{} = b), do: Decimal.compare(a, b)
  defp compare_values(%Decimal{} = a, b), do: Decimal.compare(a, to_decimal(b))
  defp compare_values(a, %Decimal{} = b), do: Decimal.compare(to_decimal(a), b)
  defp compare_values(%Date{} = a, %Date{} = b), do: Date.compare(a, b)
  defp compare_values(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b)
  defp compare_values(%NaiveDateTime{} = a, %NaiveDateTime{} = b), do: NaiveDateTime.compare(a, b)
  defp compare_values(%Time{} = a, %Time{} = b), do: Time.compare(a, b)
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

  # Convert a SQL LIKE pattern to an Elixir regex and test (case-insensitive)
  # % = any sequence of characters, _ = any single character
  defp like_match?(value, pattern) do
    # 1. Replace LIKE wildcards with placeholders before escaping
    # 2. Escape remaining regex-special chars
    # 3. Replace placeholders with regex equivalents
    regex_str =
      pattern
      |> String.replace("%", "\x00PCT\x00")
      |> String.replace("_", "\x00UND\x00")
      |> Regex.escape()
      |> String.replace("\x00PCT\x00", ".*")
      |> String.replace("\x00UND\x00", ".")

    {:ok, regex} = Regex.compile("^#{regex_str}$", "i")
    Regex.match?(regex, value)
  end

  defp resolve_dot_path(path, context, opts) do
    parts = String.split(path, ".")
    resolve_dot_parts(parts, context, path, Keyword.get(opts, :strict_lists, false))
  end

  defp resolve_dot_parts([], acc, _path, _strict), do: acc

  defp resolve_dot_parts([key | rest], acc, path, strict) when is_map(acc) do
    case Map.fetch(acc, key) do
      {:ok, value} -> resolve_dot_parts(rest, value, path, strict)
      :error -> raise "Unknown field: #{path} (failed at '#{key}')"
    end
  end

  defp resolve_dot_parts(remaining, acc, path, true) when is_list(acc) do
    parts = String.split(path, ".")
    list_field = parts |> Enum.take(length(parts) - length(remaining)) |> Enum.join(".")
    rest = Enum.join(remaining, ".")

    raise "Cannot read '#{rest}' through list field '#{list_field}'; " <>
            "use SUM(#{list_field}, #{rest}) or another list function (COUNT, ANY, ALL)"
  end

  defp resolve_dot_parts([_key | _] = remaining, acc, path, false) when is_list(acc) do
    results = Enum.map(acc, fn item -> resolve_dot_parts(remaining, item, path, false) end)

    if Enum.all?(results, &decimal_like?/1) do
      results
      |> Enum.map(&to_decimal/1)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    else
      results
    end
  end

  defp resolve_dot_parts([key | _rest], _acc, path, _strict) do
    raise "Cannot access '#{key}' on non-map value in path '#{path}'"
  end

  defp decimal_like?(%Decimal{}), do: true
  defp decimal_like?(n) when is_number(n), do: true
  defp decimal_like?(s) when is_binary(s) do
    case Decimal.parse(s) do
      {_, ""} -> true
      _ -> false
    end
  end
  defp decimal_like?(_), do: false
end
