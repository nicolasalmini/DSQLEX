defmodule Dsqlex.IntegrationTest do
  use ExUnit.Case, async: true

  alias Dsqlex.{Lexer, Parser, Evaluator}

  @moduledoc """
  End-to-end integration tests that verify the complete pipeline:
  String → Lexer → Parser → Evaluator → Result
  """

  # Sample data context for testing
  @sample_context %{
    "price" => Decimal.new("500.00"),
    "quantity" => Decimal.new("100.00"),
    "category" => "B",
    "rate" => Decimal.new("5.00"),
    "status" => "completed",
    "group_id" => 33,
    "label" => "hello world",
    "tax" => Decimal.new("10.00"),
    "discount" => Decimal.new("2.00"),
    "bonus" => nil
  }

  # Helper to run full pipeline
  defp run(expression, context \\ @sample_context) do
    with {:ok, tokens} <- Lexer.tokenize(expression),
         {:ok, ast} <- Parser.parse(tokens),
         {:ok, result} <- Evaluator.evaluate(ast, context) do
      {:ok, result}
    end
  end

  describe "simple expressions" do
    test "select a field" do
      assert {:ok, result} = run("SELECT price")
      assert Decimal.equal?(result, Decimal.new("500.00"))
    end

    test "select a literal" do
      assert {:ok, result} = run("SELECT 42")
      assert Decimal.equal?(result, Decimal.new("42"))
    end

    test "select a string" do
      assert {:ok, "hello"} = run("SELECT 'hello'")
    end
  end

  describe "arithmetic calculations" do
    test "simple division" do
      assert {:ok, result} = run("SELECT price / rate")
      assert Decimal.equal?(result, Decimal.new("100"))
    end

    test "addition" do
      assert {:ok, result} = run("SELECT price + quantity")
      assert Decimal.equal?(result, Decimal.new("600.00"))
    end

    test "complex arithmetic with parentheses" do
      assert {:ok, result} = run("SELECT (price + tax) / rate")
      assert Decimal.equal?(result, Decimal.new("102"))
    end

    test "nested parentheses" do
      assert {:ok, result} = run("SELECT ((price / rate) + discount)")
      assert Decimal.equal?(result, Decimal.new("102.00"))
    end
  end

  describe "comparisons and logic" do
    test "equality check" do
      assert {:ok, true} = run("SELECT category = 'B'")
      assert {:ok, false} = run("SELECT category = 'A'")
    end

    test "numeric comparison" do
      assert {:ok, true} = run("SELECT price > 100")
      assert {:ok, false} = run("SELECT price < 100")
    end

    test "AND condition" do
      assert {:ok, true} = run("SELECT category = 'B' AND group_id = 33")
      assert {:ok, false} = run("SELECT category = 'A' AND group_id = 33")
    end

    test "OR condition" do
      assert {:ok, true} = run("SELECT category = 'A' OR group_id = 33")
      assert {:ok, false} = run("SELECT category = 'A' OR group_id = 99")
    end

    test "chained AND" do
      assert {:ok, true} = run("SELECT category = 'B' AND group_id = 33 AND status = 'completed'")
    end

    test "mixed AND/OR with parentheses" do
      assert {:ok, true} = run("SELECT (category = 'A' OR category = 'B') AND group_id = 33")
      assert {:ok, true} = run("SELECT category = 'B' AND (group_id = 33 OR group_id = 55)")
    end
  end

  describe "CASE/WHEN - the main use case" do
    test "conditional selection - category B" do
      result = run("""
        SELECT CASE
          WHEN category = 'A' THEN quantity
          WHEN category != 'A' THEN (price / rate)
        END
      """)

      assert {:ok, value} = result
      assert Decimal.equal?(value, Decimal.new("100"))
    end

    test "conditional selection - category A" do
      a_context = Map.put(@sample_context, "category", "A")

      result = run("""
        SELECT CASE
          WHEN category = 'A' THEN quantity
          WHEN category != 'A' THEN (price / rate)
        END
      """, a_context)

      assert {:ok, value} = result
      assert Decimal.equal?(value, Decimal.new("100.00"))
    end

    test "multiple conditions with ELSE" do
      result = run("""
        SELECT CASE
          WHEN status = 'pending' THEN 'waiting'
          WHEN status = 'completed' THEN 'done'
          ELSE 'unknown'
        END
      """)

      assert {:ok, "done"} = result
    end

    test "complex condition in WHEN" do
      result = run("""
        SELECT CASE
          WHEN category = 'B' AND price > 100 THEN 'large B item'
          ELSE 'other'
        END
      """)

      assert {:ok, "large B item"} = result
    end

    test "nested CASE" do
      result = run("""
        SELECT CASE
          WHEN category = 'B' THEN
            CASE
              WHEN price > 1000 THEN 'large'
              ELSE 'small'
            END
          ELSE 'other'
        END
      """)

      assert {:ok, "small"} = result
    end
  end

  describe "functions" do
    test "ROUND calculation result" do
      result = run("SELECT ROUND(price / rate, 2)")
      assert {:ok, value} = result
      assert Decimal.equal?(value, Decimal.new("100.00"))
    end

    test "COALESCE with null" do
      result = run("SELECT COALESCE(bonus, 0)")
      assert {:ok, value} = result
      assert Decimal.equal?(value, Decimal.new("0"))
    end

    test "COALESCE with non-null" do
      result = run("SELECT COALESCE(quantity, 0)")
      assert {:ok, value} = result
      assert Decimal.equal?(value, Decimal.new("100.00"))
    end

    test "UPPER" do
      assert {:ok, "HELLO WORLD"} = run("SELECT UPPER(label)")
    end

    test "nested functions" do
      result = run("SELECT ROUND(COALESCE((price / rate), quantity), 2)")
      assert {:ok, value} = result
      assert Decimal.equal?(value, Decimal.new("100.00"))
    end

    test "function in CASE result" do
      result = run("""
        SELECT CASE
          WHEN category = 'B' THEN ROUND(price / rate, 2)
          ELSE quantity
        END
      """)

      assert {:ok, value} = result
      assert Decimal.equal?(value, Decimal.new("100.00"))
    end

    test "CONCAT strings" do
      result = run("CONCAT('Hello', ' ', 'World')")
      assert {:ok, "Hello World"} = result
    end

    test "CONCAT with fields" do
      result = run("CONCAT(label, ' in ', category)")
      assert {:ok, "hello world in B"} = result
    end

    test "CONCAT in CASE" do
      result = run("""
        CASE
          WHEN category = 'B' THEN CONCAT('Category: ', category)
          ELSE CONCAT('Other: ', category)
        END
      """)
      assert {:ok, "Category: B"} = result
    end
  end

  describe "advanced calculation scenarios" do
    test "net value after deductions" do
      result = run("SELECT (price - tax) / rate")
      assert {:ok, value} = result
      assert Decimal.equal?(value, Decimal.new("98"))
    end

    test "percentage calculation" do
      result = run("SELECT (tax / price) * 100")
      assert {:ok, value} = result
      assert Decimal.equal?(value, Decimal.new("2.00"))
    end

    test "conditional value selection" do
      result = run("""
        SELECT CASE
          WHEN category = 'A' THEN discount
          ELSE (tax / rate)
        END
      """)

      assert {:ok, value} = result
      assert Decimal.equal?(value, Decimal.new("2"))
    end

    test "complex conditional rule" do
      result = run("""
        SELECT CASE
          WHEN category = 'A' AND quantity > 50 THEN ROUND(quantity * 1.1, 2)
          WHEN category != 'A' AND price > 100 THEN ROUND((price / rate) * 1.05, 2)
          ELSE 0
        END
      """)

      assert {:ok, value} = result
      # category=B, price=500 > 100, so: (500/5) * 1.05 = 105.00
      assert Decimal.equal?(value, Decimal.new("105.00"))
    end
  end

  describe "error handling" do
    test "lexer error - unterminated string" do
      assert {:error, "Unterminated string"} = run("SELECT 'hello")
    end

    test "parser error - missing parenthesis" do
      assert {:error, "Expected closing parenthesis" <> _} = run("SELECT (1 + 2")
    end

    test "parser error - ambiguous expression" do
      assert {:error, "Ambiguous expression" <> _} = run("SELECT 1 + 2 + 3")
    end

    test "evaluator error - unknown field" do
      assert {:error, "Unknown field: nonexistent"} = run("SELECT nonexistent")
    end
  end

  describe "cross-event references" do
    # Simulates a registry of event formulas (like an ETS table)
    @event_formulas %{
      "event_a" => "x + y",
      "event_b" => "z - event_a",
      "event_c" => "event_a + event_b",
      "event_circular" => "event_circular + 1"
    }

    @ref_context %{
      "x" => Decimal.new("100"),
      "y" => Decimal.new("20"),
      "z" => Decimal.new("200")
    }

    defp make_resolver(formulas, context) do
      fn name, visited ->
        case Map.fetch(formulas, name) do
          {:ok, formula} ->
            new_visited = MapSet.put(visited, name)
            opts = [resolver: make_resolver(formulas, context), visited: new_visited]
            Dsqlex.eval(formula, context, opts)

          :error ->
            {:error, "Unknown event: #{name}"}
        end
      end
    end

    test "event_b references event_a" do
      # event_a = x + y = 120
      # event_b = z - event_a = 200 - 120 = 80
      resolver = make_resolver(@event_formulas, @ref_context)
      assert {:ok, result} = Dsqlex.eval("event_b", @ref_context, resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("80"))
    end

    test "event_c references both event_a and event_b" do
      # event_a = 120, event_b = 80
      # event_c = event_a + event_b = 200
      resolver = make_resolver(@event_formulas, @ref_context)
      assert {:ok, result} = Dsqlex.eval("event_c", @ref_context, resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("200"))
    end

    test "direct event reference" do
      # event_a = x + y = 120
      resolver = make_resolver(@event_formulas, @ref_context)
      assert {:ok, result} = Dsqlex.eval("event_a", @ref_context, resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("120"))
    end

    test "circular reference is detected" do
      resolver = make_resolver(@event_formulas, @ref_context)
      assert {:error, "Circular reference detected: event_circular"} =
        Dsqlex.eval("event_circular", @ref_context, resolver: resolver)
    end

    test "unknown event returns error" do
      resolver = make_resolver(@event_formulas, @ref_context)
      assert {:error, "Unknown event: nonexistent_event"} =
        Dsqlex.eval("nonexistent_event", @ref_context, resolver: resolver)
    end

    test "event reference in arithmetic expression" do
      # (event_a * 2) = 240
      resolver = make_resolver(@event_formulas, @ref_context)
      assert {:ok, result} = Dsqlex.eval("event_a * 2", @ref_context, resolver: resolver)
      assert Decimal.equal?(result, Decimal.new("240"))
    end

    test "event reference in CASE expression" do
      resolver = make_resolver(@event_formulas, @ref_context)

      result = Dsqlex.eval("""
        CASE
          WHEN event_a > 100 THEN event_b
          ELSE 0
        END
      """, @ref_context, resolver: resolver)

      assert {:ok, value} = result
      assert Decimal.equal?(value, Decimal.new("80"))
    end
  end

  describe "edge cases" do
    test "empty string literal" do
      assert {:ok, ""} = run("SELECT ''")
    end

    test "zero values" do
      assert {:ok, value} = run("SELECT 0")
      assert Decimal.equal?(value, Decimal.new("0"))
    end

    test "negative result" do
      assert {:ok, value} = run("SELECT 10 - 20")
      assert Decimal.equal?(value, Decimal.new("-10"))
    end

    test "decimal precision maintained" do
      assert {:ok, value} = run("SELECT 1 / 3")
      # Decimal division maintains precision
      assert %Decimal{} = value
    end

    test "whitespace handling" do
      assert {:ok, _} = run("SELECT    price   /   rate")
      assert {:ok, _} = run("SELECT\n  price\n  /\n  rate")
    end

    test "case insensitive keywords" do
      assert {:ok, _} = run("select price")
      assert {:ok, _} = run("SELECT CASE when category = 'B' then price ELSE 0 end")
    end

    test "SELECT is optional" do
      # All these should work without SELECT
      assert {:ok, _} = run("price")
      assert {:ok, _} = run("price / rate")
      assert {:ok, _} = run("(price / rate) + discount")
      assert {:ok, _} = run("CASE WHEN category = 'B' THEN price ELSE quantity END")
      assert {:ok, _} = run("ROUND(price, 2)")
    end
  end
end
