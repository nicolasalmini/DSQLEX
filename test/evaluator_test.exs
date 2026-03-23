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
end
