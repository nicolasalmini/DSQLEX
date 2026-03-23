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
      formulas = %{"PAYMENT_CONFIRMED.PROCESSING_FEE" => "amount_local * rate"}
      resolver = mock_event_resolver(formulas)

      context = %{
        "amount_local" => Decimal.new("100"),
        "rate" => Decimal.new("0.05")
      }

      # EVENT(PAYMENT_CONFIRMED, PROCESSING_FEE)
      ast = select(call(:event, [ident("PAYMENT_CONFIRMED"), ident("PROCESSING_FEE")]))
      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("5.000"))
    end

    test "EVENT with 3 args - single map context source" do
      formulas = %{"PAYMENT_CONFIRMED.PAYMENT_RECOGNITION" => "amount_local"}
      resolver = mock_event_resolver(formulas)

      context = %{
        "amount_local" => Decimal.new("999"),
        "payment_normalized" => %{"amount_local" => Decimal.new("500")}
      }

      # EVENT(PAYMENT_CONFIRMED, PAYMENT_RECOGNITION, payment_normalized)
      ast = select(call(:event, [ident("PAYMENT_CONFIRMED"), ident("PAYMENT_RECOGNITION"), ident("payment_normalized")]))
      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("500"))
    end

    test "EVENT with 3 args - list context source (implicit sum)" do
      formulas = %{"REFUND_CONFIRMED.REFUND_RECOGNITION" => "amount_local"}
      resolver = mock_event_resolver(formulas)

      context = %{
        "refunds_normalized" => [
          %{"amount_local" => Decimal.new("50")},
          %{"amount_local" => Decimal.new("30")},
          %{"amount_local" => Decimal.new("20")}
        ]
      }

      # EVENT(REFUND_CONFIRMED, REFUND_RECOGNITION, refunds_normalized) => 50 + 30 + 20 = 100
      ast = select(call(:event, [ident("REFUND_CONFIRMED"), ident("REFUND_RECOGNITION"), ident("refunds_normalized")]))
      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("100"))
    end

    test "EVENT with empty list context source returns zero" do
      formulas = %{"REFUND_CONFIRMED.REFUND_RECOGNITION" => "amount_local"}
      resolver = mock_event_resolver(formulas)

      context = %{"refunds_normalized" => []}

      ast = select(call(:event, [ident("REFUND_CONFIRMED"), ident("REFUND_RECOGNITION"), ident("refunds_normalized")]))
      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("0"))
    end

    test "chargeback pattern: payment - sum(refunds)" do
      formulas = %{
        "PAYMENT_CONFIRMED.PAYMENT_RECOGNITION" => "amount_local",
        "REFUND_CONFIRMED.REFUND_RECOGNITION" => "amount_local"
      }
      resolver = mock_event_resolver(formulas)

      context = %{
        "payment_normalized" => %{"amount_local" => Decimal.new("500")},
        "refunds_normalized" => [
          %{"amount_local" => Decimal.new("50")},
          %{"amount_local" => Decimal.new("30")}
        ]
      }

      # EVENT(PAYMENT, RECOGNITION, payment_normalized) - EVENT(REFUND, RECOGNITION, refunds_normalized)
      ast = select(binop(:minus,
        call(:event, [ident("PAYMENT_CONFIRMED"), ident("PAYMENT_RECOGNITION"), ident("payment_normalized")]),
        call(:event, [ident("REFUND_CONFIRMED"), ident("REFUND_RECOGNITION"), ident("refunds_normalized")])
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
        "P.REC" => "amount_local",
        "R.REC" => "amount_local"
      }
      resolver = mock_event_resolver(formulas)

      context = %{
        "payment_normalized" => %{"amount_local" => Decimal.new("1000")},
        "refunds_normalized" => [
          %{"amount_local" => Decimal.new("100")},
          %{"amount_local" => Decimal.new("200")},
          %{"amount_local" => Decimal.new("150")}
        ]
      }

      # EVENT(P, REC, payment_normalized) - EVENT(R, REC, refunds_normalized) = 1000 - 450 = 550
      ast = select(binop(:minus,
        call(:event, [ident("P"), ident("REC"), ident("payment_normalized")]),
        call(:event, [ident("R"), ident("REC"), ident("refunds_normalized")])
      ))

      assert {:ok, result} = Evaluator.evaluate(ast, context, event_resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("550"))
    end
  end
end
