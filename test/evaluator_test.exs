defmodule Dsqlex.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Dsqlex.Evaluator

  # Standard test context
  @context %{
    "x" => Decimal.new("100.00"),
    "y" => Decimal.new("20.00"),
    "category" => "B",
    "rate" => Decimal.new("5.00"),
    "status" => "active",
    "group_id" => 33,
    "nullable_field" => nil,
    "flag" => true
  }

  # Helper to build AST nodes
  defp select(expr), do: {:select, expr}
  defp num(n), do: {:number, n}
  defp str(s), do: {:string, s}
  defp ident(name), do: {:identifier, name}
  defp bool(b), do: {:boolean, b}
  defp null(), do: {:null}
  defp binop(op, left, right), do: {:binary_op, op, left, right}
  defp case_expr(whens, else_clause), do: {:case_expr, whens, else_clause}
  defp when_clause(cond, result), do: {:when, cond, result}
  defp call(name, args), do: {:call, name, args}

  describe "evaluate/2 - literals" do
    test "evaluates number as Decimal" do
      ast = select(num("42"))
      assert {:ok, %Decimal{}} = Evaluator.evaluate(ast, @context)
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("42"))
    end

    test "evaluates string" do
      ast = select(str("hello"))
      assert {:ok, "hello"} = Evaluator.evaluate(ast, @context)
    end

    test "evaluates boolean" do
      assert {:ok, true} = Evaluator.evaluate(select(bool(true)), @context)
      assert {:ok, false} = Evaluator.evaluate(select(bool(false)), @context)
    end

    test "evaluates null" do
      assert {:ok, nil} = Evaluator.evaluate(select(null()), @context)
    end
  end

  describe "evaluate/2 - identifiers" do
    test "looks up identifier in context" do
      ast = select(ident("category"))
      assert {:ok, "B"} = Evaluator.evaluate(ast, @context)
    end

    test "returns Decimal for numeric fields" do
      ast = select(ident("x"))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("100.00"))
    end

    test "returns nil for nullable field" do
      ast = select(ident("nullable_field"))
      assert {:ok, nil} = Evaluator.evaluate(ast, @context)
    end

    test "errors on unknown field" do
      ast = select(ident("unknown_field"))
      assert {:error, "Unknown field: unknown_field"} = Evaluator.evaluate(ast, @context)
    end
  end

  describe "evaluate/2 - arithmetic" do
    test "addition" do
      ast = select(binop(:plus, num("10"), num("5")))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("15"))
    end

    test "subtraction" do
      ast = select(binop(:minus, num("10"), num("3")))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("7"))
    end

    test "multiplication" do
      ast = select(binop(:multiply, num("4"), num("5")))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("20"))
    end

    test "division" do
      ast = select(binop(:divide, num("100"), num("5")))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("20"))
    end

    test "division with context values" do
      ast = select(binop(:divide, ident("x"), ident("rate")))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("20"))
    end

    test "nested arithmetic" do
      # (10 + 5) * 2 = 30
      ast = select(binop(:multiply, binop(:plus, num("10"), num("5")), num("2")))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("30"))
    end
  end

  describe "evaluate/2 - comparison" do
    test "equality - true" do
      ast = select(binop(:eq, ident("category"), str("B")))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "equality - false" do
      ast = select(binop(:eq, ident("category"), str("A")))
      assert {:ok, false} = Evaluator.evaluate(ast, @context)
    end

    test "inequality" do
      ast = select(binop(:neq, ident("category"), str("A")))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "less than" do
      ast = select(binop(:lt, num("5"), num("10")))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "greater than" do
      ast = select(binop(:gt, ident("x"), num("50")))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "less than or equal" do
      ast = select(binop(:lte, num("10"), num("10")))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "greater than or equal" do
      ast = select(binop(:gte, ident("group_id"), num("33")))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "numeric comparison with Decimals" do
      ast = select(binop(:gt, ident("x"), ident("y")))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end
  end

  describe "evaluate/2 - logical operators" do
    test "AND - both true" do
      ast = select(binop(:and,
        binop(:eq, ident("category"), str("B")),
        binop(:eq, ident("group_id"), num("33"))
      ))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "AND - one false" do
      ast = select(binop(:and,
        binop(:eq, ident("category"), str("A")),
        binop(:eq, ident("group_id"), num("33"))
      ))
      assert {:ok, false} = Evaluator.evaluate(ast, @context)
    end

    test "OR - one true" do
      ast = select(binop(:or,
        binop(:eq, ident("category"), str("A")),
        binop(:eq, ident("group_id"), num("33"))
      ))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "OR - both false" do
      ast = select(binop(:or,
        binop(:eq, ident("category"), str("A")),
        binop(:eq, ident("group_id"), num("99"))
      ))
      assert {:ok, false} = Evaluator.evaluate(ast, @context)
    end

    test "chained AND" do
      ast = select(binop(:and,
        binop(:and,
          binop(:eq, ident("category"), str("B")),
          binop(:eq, ident("group_id"), num("33"))
        ),
        binop(:eq, ident("status"), str("active"))
      ))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end
  end

  describe "evaluate/2 - CASE/WHEN" do
    test "returns first matching WHEN result" do
      ast = select(case_expr([
        when_clause(binop(:eq, ident("category"), str("A")), str("first")),
        when_clause(binop(:eq, ident("category"), str("B")), str("second"))
      ], nil))

      assert {:ok, "second"} = Evaluator.evaluate(ast, @context)
    end

    test "returns ELSE when no WHEN matches" do
      ast = select(case_expr([
        when_clause(binop(:eq, ident("category"), str("A")), str("first")),
        when_clause(binop(:eq, ident("category"), str("C")), str("third"))
      ], str("other")))

      assert {:ok, "other"} = Evaluator.evaluate(ast, @context)
    end

    test "returns nil when no WHEN matches and no ELSE" do
      ast = select(case_expr([
        when_clause(binop(:eq, ident("category"), str("A")), str("first"))
      ], nil))

      assert {:ok, nil} = Evaluator.evaluate(ast, @context)
    end

    test "evaluates complex WHEN conditions" do
      ast = select(case_expr([
        when_clause(
          binop(:and,
            binop(:eq, ident("category"), str("B")),
            binop(:gt, ident("x"), num("50"))
          ),
          str("big B")
        )
      ], str("other")))

      assert {:ok, "big B"} = Evaluator.evaluate(ast, @context)
    end

    test "conditional division use case" do
      # CASE WHEN category = 'A' THEN y
      #      WHEN category != 'A' THEN x / rate END
      ast = select(case_expr([
        when_clause(binop(:eq, ident("category"), str("A")), ident("y")),
        when_clause(binop(:neq, ident("category"), str("A")),
          binop(:divide, ident("x"), ident("rate")))
      ], nil))

      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("20"))
    end
  end

  describe "evaluate/2 - functions" do
    test "ROUND with precision" do
      ast = select(call(:round, [num("3.14159"), num("2")]))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("3.14"))
    end

    test "ROUND with expression" do
      ast = select(call(:round, [
        binop(:divide, ident("x"), ident("rate")),
        num("2")
      ]))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("20.00"))
    end

    test "COALESCE returns first non-null" do
      ast = select(call(:coalesce, [ident("nullable_field"), num("0")]))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("0"))
    end

    test "COALESCE returns first value if not null" do
      ast = select(call(:coalesce, [ident("y"), num("0")]))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("20.00"))
    end

    test "UPPER" do
      ast = select(call(:upper, [ident("category")]))
      assert {:ok, "B"} = Evaluator.evaluate(ast, @context)

      ast = select(call(:upper, [str("hello")]))
      assert {:ok, "HELLO"} = Evaluator.evaluate(ast, @context)
    end

    test "LOWER" do
      ast = select(call(:lower, [str("HELLO")]))
      assert {:ok, "hello"} = Evaluator.evaluate(ast, @context)
    end

    test "ABS" do
      ast = select(call(:abs, [num("-42")]))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("42"))
    end

    test "CONCAT with two strings" do
      ast = select(call(:concat, [str("hello"), str(" world")]))
      assert {:ok, "hello world"} = Evaluator.evaluate(ast, @context)
    end

    test "CONCAT with multiple arguments" do
      ast = select(call(:concat, [ident("status"), str(" - "), ident("category")]))
      assert {:ok, "active - B"} = Evaluator.evaluate(ast, @context)
    end

    test "CONCAT coerces numbers to strings" do
      ast = select(call(:concat, [str("Value: "), ident("x")]))
      assert {:ok, "Value: 100.00"} = Evaluator.evaluate(ast, @context)
    end

    test "LEAST returns smallest number" do
      ast = select(call(:least, [num("3"), num("1"), num("2")]))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("1"))
    end

    test "GREATEST returns largest number" do
      ast = select(call(:greatest, [num("3"), num("1"), num("2")]))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("3"))
    end

    test "LEAST/GREATEST with a single argument returns it" do
      assert {:ok, r1} = Evaluator.evaluate(select(call(:least, [num("7")])), @context)
      assert Decimal.equal?(r1, Decimal.new("7"))

      assert {:ok, r2} = Evaluator.evaluate(select(call(:greatest, [num("7")])), @context)
      assert Decimal.equal?(r2, Decimal.new("7"))
    end

    test "LEAST returns NULL if any argument is NULL (BigQuery semantics)" do
      ast = select(call(:least, [num("3"), ident("nullable_field"), num("2")]))
      assert {:ok, nil} = Evaluator.evaluate(ast, @context)
    end

    test "GREATEST returns NULL if any argument is NULL (BigQuery semantics)" do
      ast = select(call(:greatest, [num("3"), ident("nullable_field"), num("2")]))
      assert {:ok, nil} = Evaluator.evaluate(ast, @context)
    end

    test "LEAST/GREATEST compare Dates chronologically" do
      context = %{"d1" => ~D[2020-01-01], "d2" => ~D[2019-05-05], "d3" => ~D[2021-12-31]}

      assert {:ok, ~D[2019-05-05]} =
               Evaluator.evaluate(select(call(:least, [ident("d1"), ident("d2"), ident("d3")])), context)

      assert {:ok, ~D[2021-12-31]} =
               Evaluator.evaluate(select(call(:greatest, [ident("d1"), ident("d2"), ident("d3")])), context)
    end

    test "LEAST/GREATEST compare DateTimes chronologically" do
      context = %{
        "t1" => ~U[2020-01-01 10:00:00Z],
        "t2" => ~U[2020-01-01 08:30:00Z]
      }

      assert {:ok, ~U[2020-01-01 08:30:00Z]} =
               Evaluator.evaluate(select(call(:least, [ident("t1"), ident("t2")])), context)

      assert {:ok, ~U[2020-01-01 10:00:00Z]} =
               Evaluator.evaluate(select(call(:greatest, [ident("t1"), ident("t2")])), context)
    end

    test "LEAST/GREATEST compare strings lexicographically" do
      assert {:ok, "a"} = Evaluator.evaluate(select(call(:least, [str("b"), str("a"), str("c")])), @context)
      assert {:ok, "c"} = Evaluator.evaluate(select(call(:greatest, [str("b"), str("a"), str("c")])), @context)
    end

    test "nested functions" do
      # ROUND(COALESCE(x / rate, y), 2)
      ast = select(call(:round, [
        call(:coalesce, [
          binop(:divide, ident("x"), ident("rate")),
          ident("y")
        ]),
        num("2")
      ]))
      assert {:ok, result} = Evaluator.evaluate(ast, @context)
      assert Decimal.equal?(result, Decimal.new("20.00"))
    end
  end

  describe "evaluate/2 - type handling" do
    test "compares Decimal to integer" do
      ast = select(binop(:eq, ident("group_id"), num("33")))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "compares strings" do
      ast = select(binop(:lt, str("apple"), str("banana")))
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end
  end

  describe "evaluate/2 - error handling" do
    test "unknown field returns error" do
      ast = select(ident("nonexistent"))
      assert {:error, _} = Evaluator.evaluate(ast, @context)
    end
  end

  describe "evaluate/3 - resolver" do
    test "resolves unknown identifier via resolver function" do
      resolver = fn "event_a", _visited ->
        {:ok, Decimal.new("42")}
      end

      # event_a + 10
      ast = select(binop(:plus, ident("event_a"), num("10")))
      assert {:ok, result} = Evaluator.evaluate(ast, %{}, resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("52"))
    end

    test "context takes precedence over resolver" do
      resolver = fn _name, _visited ->
        {:ok, Decimal.new("999")}
      end

      ast = select(ident("x"))
      assert {:ok, result} = Evaluator.evaluate(ast, @context, resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("100.00"))
    end

    test "resolver error is propagated" do
      resolver = fn "missing_event", _visited ->
        {:error, "Event not found: missing_event"}
      end

      ast = select(ident("missing_event"))
      assert {:error, "Event not found: missing_event"} = Evaluator.evaluate(ast, %{}, resolver: resolver)
    end

    test "circular reference is detected" do
      resolver = fn "event_a", _visited ->
        {:ok, Decimal.new("1")}
      end

      ast = select(ident("event_a"))
      opts = [resolver: resolver, visited: MapSet.new(["event_a"])]
      assert {:error, "Circular reference detected: event_a"} = Evaluator.evaluate(ast, %{}, opts)
    end

    test "resolver works inside arithmetic expressions" do
      resolver = fn
        "event_a", _visited -> {:ok, Decimal.new("100")}
        "event_b", _visited -> {:ok, Decimal.new("30")}
      end

      # event_a - event_b
      ast = select(binop(:minus, ident("event_a"), ident("event_b")))
      assert {:ok, result} = Evaluator.evaluate(ast, %{}, resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("70"))
    end

    test "resolver works inside CASE/WHEN" do
      resolver = fn "event_a", _visited ->
        {:ok, Decimal.new("50")}
      end

      # CASE WHEN event_a > 10 THEN event_a ELSE 0 END
      ast = select(case_expr([
        when_clause(binop(:gt, ident("event_a"), num("10")), ident("event_a"))
      ], num("0")))

      assert {:ok, result} = Evaluator.evaluate(ast, %{}, resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("50"))
    end
  end

  describe "evaluate/3 - dot-path nested map access" do
    test "simple dot path accesses nested map" do
      ast = {:select, {:identifier, "config.pricing"}}
      context = %{"config" => %{"pricing" => Decimal.new("1.02")}}
      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert Decimal.equal?(result, Decimal.new("1.02"))
    end

    test "multi-level dot path" do
      ast = {:select, {:identifier, "config.pricing.margin_rate"}}
      context = %{"config" => %{"pricing" => %{"margin_rate" => Decimal.new("2.9")}}}
      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert Decimal.equal?(result, Decimal.new("2.9"))
    end

    test "dot path in arithmetic expression" do
      ast = {:select, {:binary_op, :multiply, {:identifier, "base_amount"}, {:identifier, "config.pricing.settlement_rate"}}}
      context = %{
        "base_amount" => Decimal.new("100"),
        "config" => %{"pricing" => %{"settlement_rate" => Decimal.new("1.02")}}
      }
      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert Decimal.equal?(result, Decimal.new("102.00"))
    end

    test "dot path with unknown nested key raises error" do
      ast = {:select, {:identifier, "config.nonexistent"}}
      context = %{"config" => %{"pricing" => Decimal.new("1.02")}}
      assert {:error, "Unknown field: config.nonexistent" <> _} = Evaluator.evaluate(ast, context)
    end

    test "dot path through list of maps sums numeric values" do
      ast = {:select, {:identifier, "adjustments.adjustment_amount"}}
      context = %{
        "adjustments" => [
          %{"adjustment_amount" => Decimal.new("100.00")},
          %{"adjustment_amount" => Decimal.new("50.00")},
          %{"adjustment_amount" => Decimal.new("25.00")}
        ]
      }
      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert Decimal.equal?(result, Decimal.new("175.00"))
    end

    test "dot path through list with nested map access sums values" do
      ast = {:select, {:identifier, "adjustments.config.pricing.margin_rate"}}
      context = %{
        "adjustments" => [
          %{"config" => %{"pricing" => %{"margin_rate" => Decimal.new("1.5")}}},
          %{"config" => %{"pricing" => %{"margin_rate" => Decimal.new("2.5")}}}
        ]
      }
      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert Decimal.equal?(result, Decimal.new("4.0"))
    end

    test "dot path through list returns list for non-numeric values" do
      ast = {:select, {:identifier, "adjustments.status"}}
      context = %{
        "adjustments" => [
          %{"status" => "CO"},
          %{"status" => "PE"}
        ]
      }
      assert {:ok, ["CO", "PE"]} = Evaluator.evaluate(ast, context)
    end

    test "dot path through single map still works" do
      ast = {:select, {:identifier, "order_data.amount"}}
      context = %{
        "order_data" => %{"amount" => Decimal.new("500.00")}
      }
      assert {:ok, result} = Evaluator.evaluate(ast, context)
      assert Decimal.equal?(result, Decimal.new("500.00"))
    end
  end

  describe "evaluate/3 - EVENT() function" do
    # Mock event resolver that looks up formulas and evaluates them
    defp mock_event_resolver(formulas) do
      fn type, subtype, eval_context, opts ->
        key = "#{type}.#{subtype}"
        case Map.fetch(formulas, key) do
          {:ok, formula} ->
            Dsqlex.eval(formula, eval_context, opts)
          :error ->
            {:error, "No formula found for EVENT(#{type}, #{subtype})"}
        end
      end
    end

    test "EVENT with 2 args - evaluates with current context" do
      formulas = %{"ORDER_PLACED.SERVICE_FEE" => "amount * rate"}
      resolver = mock_event_resolver(formulas)

      context = %{
        "amount" => Decimal.new("100"),
        "rate" => Decimal.new("0.05")
      }

      # EVENT(ORDER_PLACED, SERVICE_FEE)
      ast = select(call(:event, [ident("ORDER_PLACED"), ident("SERVICE_FEE")]))
      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("5.000"))
    end

    test "EVENT with 3 args - single map context source" do
      formulas = %{"ORDER_PLACED.ORDER_TOTAL" => "amount"}
      resolver = mock_event_resolver(formulas)

      context = %{
        "amount" => Decimal.new("999"),
        "order_data" => %{"amount" => Decimal.new("500")}
      }

      # EVENT(ORDER_PLACED, ORDER_TOTAL, order_data)
      ast = select(call(:event, [ident("ORDER_PLACED"), ident("ORDER_TOTAL"), ident("order_data")]))
      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("500"))
    end

    test "EVENT with 3 args - list context source (implicit sum)" do
      formulas = %{"RETURN_PROCESSED.RETURN_TOTAL" => "amount"}
      resolver = mock_event_resolver(formulas)

      context = %{
        "adjustments" => [
          %{"amount" => Decimal.new("50")},
          %{"amount" => Decimal.new("30")},
          %{"amount" => Decimal.new("20")}
        ]
      }

      # EVENT(RETURN_PROCESSED, RETURN_TOTAL, adjustments) => 50 + 30 + 20 = 100
      ast = select(call(:event, [ident("RETURN_PROCESSED"), ident("RETURN_TOTAL"), ident("adjustments")]))
      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("100"))
    end

    test "EVENT with empty list context source returns zero" do
      formulas = %{"RETURN_PROCESSED.RETURN_TOTAL" => "amount"}
      resolver = mock_event_resolver(formulas)

      context = %{"adjustments" => []}

      ast = select(call(:event, [ident("RETURN_PROCESSED"), ident("RETURN_TOTAL"), ident("adjustments")]))
      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("0"))
    end

    test "net total pattern: order - sum(adjustments)" do
      formulas = %{
        "ORDER_PLACED.ORDER_TOTAL" => "amount",
        "RETURN_PROCESSED.RETURN_TOTAL" => "amount"
      }
      resolver = mock_event_resolver(formulas)

      context = %{
        "order_data" => %{"amount" => Decimal.new("500")},
        "adjustments" => [
          %{"amount" => Decimal.new("50")},
          %{"amount" => Decimal.new("30")}
        ]
      }

      # EVENT(ORDER_PLACED, ORDER_TOTAL, order_data) - EVENT(RETURN_PROCESSED, RETURN_TOTAL, adjustments)
      ast = select(binop(:minus,
        call(:event, [ident("ORDER_PLACED"), ident("ORDER_TOTAL"), ident("order_data")]),
        call(:event, [ident("RETURN_PROCESSED"), ident("RETURN_TOTAL"), ident("adjustments")])
      ))

      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("420"))
    end

    test "EVENT errors when no event_resolver provided" do
      ast = select(call(:event, [ident("TYPE"), ident("SUBTYPE")]))
      assert {:error, "EVENT() calls require an :event_resolver option"} =
        Evaluator.evaluate(ast, %{})
    end

    test "EVENT errors when formula not found" do
      resolver = mock_event_resolver(%{})
      ast = select(call(:event, [ident("UNKNOWN"), ident("EVENT")]))
      assert {:error, "No formula found for EVENT(UNKNOWN, EVENT)"} =
        Evaluator.evaluate(ast, %{}, event_resolver: resolver)
    end

    test "EVENT errors when context source not found" do
      resolver = mock_event_resolver(%{"T.S" => "x"})
      ast = select(call(:event, [ident("T"), ident("S"), ident("missing_field")]))
      assert {:error, "EVENT context source 'missing_field' not found in context"} =
        Evaluator.evaluate(ast, %{}, event_resolver: resolver)
    end

    test "EVENT errors with wrong number of arguments" do
      resolver = mock_event_resolver(%{})
      ast = select(call(:event, [ident("ONLY_ONE")]))
      assert {:error, "EVENT requires 2 or 3 arguments" <> _} =
        Evaluator.evaluate(ast, %{}, event_resolver: resolver)
    end

    test "EVENT circular reference detection" do
      # event_a calls event_b, event_b calls event_a
      formulas = %{
        "A.X" => "EVENT(B, Y)",
        "B.Y" => "EVENT(A, X)"
      }
      resolver = mock_event_resolver(formulas)

      ast = select(call(:event, [ident("A"), ident("X")]))
      assert {:error, "Circular reference detected: A.X"} =
        Evaluator.evaluate(ast, %{}, event_resolver: resolver)
    end

    test "EVENT in CASE expression" do
      formulas = %{"P.FEE" => "amount * rate"}
      resolver = mock_event_resolver(formulas)

      context = %{
        "currency" => "USD",
        "amount" => Decimal.new("100"),
        "rate" => Decimal.new("0.03")
      }

      # CASE WHEN currency = 'USD' THEN EVENT(P, FEE) ELSE 0 END
      ast = select(case_expr([
        when_clause(binop(:eq, ident("currency"), str("USD")),
          call(:event, [ident("P"), ident("FEE")]))
      ], num("0")))

      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("3.00"))
    end

    test "EVENT arithmetic with scalar and list context" do
      formulas = %{
        "P.REC" => "amount",
        "R.REC" => "amount"
      }
      resolver = mock_event_resolver(formulas)

      context = %{
        "order_data" => %{"amount" => Decimal.new("1000")},
        "adjustments" => [
          %{"amount" => Decimal.new("100")},
          %{"amount" => Decimal.new("200")},
          %{"amount" => Decimal.new("150")}
        ]
      }

      # EVENT(P, REC, order_data) - EVENT(R, REC, adjustments) = 1000 - 450 = 550
      ast = select(binop(:minus,
        call(:event, [ident("P"), ident("REC"), ident("order_data")]),
        call(:event, [ident("R"), ident("REC"), ident("adjustments")])
      ))

      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("550"))
    end
  end

  describe "evaluate/2 - IN and NOT IN" do
    test "string IN list - match" do
      ast = select({:in, ident("category"), [str("A"), str("B"), str("C")]})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "string IN list - no match" do
      ast = select({:in, ident("category"), [str("X"), str("Y")]})
      assert {:ok, false} = Evaluator.evaluate(ast, @context)
    end

    test "number IN list - match" do
      ast = select({:in, ident("x"), [num("50"), num("100.00"), num("200")]})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "number IN list - no match" do
      ast = select({:in, ident("x"), [num("1"), num("2")]})
      assert {:ok, false} = Evaluator.evaluate(ast, @context)
    end

    test "NOT IN - no match returns true" do
      ast = select({:not_in, ident("category"), [str("X"), str("Y")]})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "NOT IN - match returns false" do
      ast = select({:not_in, ident("category"), [str("A"), str("B")]})
      assert {:ok, false} = Evaluator.evaluate(ast, @context)
    end

    test "IN with single item" do
      ast = select({:in, ident("category"), [str("B")]})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end
  end

  describe "evaluate/2 - LIKE and NOT LIKE" do
    test "LIKE with % prefix match" do
      ast = select({:like, ident("status"), str("%tive")})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "LIKE with % suffix match" do
      ast = select({:like, ident("status"), str("act%")})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "LIKE with % both sides" do
      ast = select({:like, ident("status"), str("%ctiv%")})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "LIKE exact match (no wildcards)" do
      ast = select({:like, ident("status"), str("active")})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "LIKE no match" do
      ast = select({:like, ident("status"), str("%xyz%")})
      assert {:ok, false} = Evaluator.evaluate(ast, @context)
    end

    test "LIKE with _ single character wildcard" do
      ast = select({:like, ident("category"), str("_")})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "LIKE _ does not match multiple characters" do
      ast = select({:like, ident("status"), str("_")})
      assert {:ok, false} = Evaluator.evaluate(ast, @context)
    end

    test "LIKE is case-insensitive" do
      ast = select({:like, ident("status"), str("ACTIVE")})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "LIKE is case-insensitive with wildcards" do
      ast = select({:like, ident("status"), str("%CTIV%")})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "NOT LIKE - no match returns true" do
      ast = select({:not_like, ident("status"), str("%xyz%")})
      assert {:ok, true} = Evaluator.evaluate(ast, @context)
    end

    test "NOT LIKE - match returns false" do
      ast = select({:not_like, ident("status"), str("%active%")})
      assert {:ok, false} = Evaluator.evaluate(ast, @context)
    end
  end
end
