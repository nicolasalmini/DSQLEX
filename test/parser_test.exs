defmodule Dsqlex.ParserTest do
  use ExUnit.Case, async: true

  alias Dsqlex.{Lexer, Parser}

  # Helper to parse a string directly
  defp parse(input) do
    with {:ok, tokens} <- Lexer.tokenize(input) do
      Parser.parse(tokens)
    end
  end

  describe "parse/1 - literals" do
    test "parses number" do
      assert {:ok, {:select, {:number, "42"}}} = parse("SELECT 42")
      assert {:ok, {:select, {:number, "3.14"}}} = parse("SELECT 3.14")
    end

    test "parses string" do
      assert {:ok, {:select, {:string, "hello"}}} = parse("SELECT 'hello'")
      assert {:ok, {:select, {:string, ""}}} = parse("SELECT ''")
    end

    test "parses identifier" do
      assert {:ok, {:select, {:identifier, "my_var"}}} = parse("SELECT my_var")
      assert {:ok, {:select, {:identifier, "x"}}} = parse("SELECT x")
    end

    test "parses boolean" do
      assert {:ok, {:select, {:boolean, true}}} = parse("SELECT TRUE")
      assert {:ok, {:select, {:boolean, false}}} = parse("SELECT FALSE")
    end

    test "parses null" do
      assert {:ok, {:select, {:null}}} = parse("SELECT NULL")
    end
  end

  describe "parse/1 - arithmetic operators" do
    test "parses single addition" do
      assert {:ok, {:select, {:binary_op, :plus, {:number, "1"}, {:number, "2"}}}} =
        parse("SELECT 1 + 2")
    end

    test "parses single subtraction" do
      assert {:ok, {:select, {:binary_op, :minus, {:number, "5"}, {:number, "3"}}}} =
        parse("SELECT 5 - 3")
    end

    test "parses single multiplication" do
      assert {:ok, {:select, {:binary_op, :multiply, {:number, "2"}, {:number, "3"}}}} =
        parse("SELECT 2 * 3")
    end

    test "parses single division" do
      assert {:ok, {:select, {:binary_op, :divide, {:identifier, "a"}, {:identifier, "b"}}}} =
        parse("SELECT a / b")
    end

    test "allows same-group additive chains without parentheses" do
      # Left-associative: ((a - b) - c) - d
      {:ok, {:select, ast}} = parse("SELECT a - b - c - d")
      assert {:binary_op, :minus,
               {:binary_op, :minus,
                 {:binary_op, :minus, {:identifier, "a"}, {:identifier, "b"}},
                 {:identifier, "c"}},
               {:identifier, "d"}} = ast

      # Left-associative: ((1 + 2) + 3)
      {:ok, {:select, ast}} = parse("SELECT 1 + 2 + 3")
      assert {:binary_op, :plus,
               {:binary_op, :plus, {:number, "1"}, {:number, "2"}},
               {:number, "3"}} = ast

      # Mixed +/- in the same chain is allowed
      {:ok, {:select, ast}} = parse("SELECT a + b - c + d")
      assert {:binary_op, :plus,
               {:binary_op, :minus,
                 {:binary_op, :plus, {:identifier, "a"}, {:identifier, "b"}},
                 {:identifier, "c"}},
               {:identifier, "d"}} = ast
    end

    test "allows same-group multiplicative chains without parentheses" do
      # Left-associative: ((a * b) * c)
      {:ok, {:select, ast}} = parse("SELECT a * b * c")
      assert {:binary_op, :multiply,
               {:binary_op, :multiply, {:identifier, "a"}, {:identifier, "b"}},
               {:identifier, "c"}} = ast

      # Mixed *// in the same chain is allowed
      {:ok, {:select, ast}} = parse("SELECT a * b / c")
      assert {:binary_op, :divide,
               {:binary_op, :multiply, {:identifier, "a"}, {:identifier, "b"}},
               {:identifier, "c"}} = ast
    end

    test "rejects mixing additive and multiplicative without parentheses" do
      assert {:error, "Ambiguous expression: mixing +/- and *//" <> _} =
        parse("SELECT 1 + 2 * 3")
      assert {:error, "Ambiguous expression: mixing +/- and *//" <> _} =
        parse("SELECT a / b + c")
      assert {:error, "Ambiguous expression: mixing +/- and *//" <> _} =
        parse("SELECT a - b - c - d / e")
      # Inner parens don't cure the outer mix
      assert {:error, "Ambiguous expression: mixing +/- and *//" <> _} =
        parse("SELECT a - b - (c - d) / e")
    end

    test "allows chained arithmetic with parentheses" do
      assert {:ok, {:select, {:binary_op, :plus, {:binary_op, :plus, _, _}, _}}} =
        parse("SELECT (1 + 2) + 3")

      assert {:ok, {:select, {:binary_op, :multiply, {:binary_op, :plus, _, _}, _}}} =
        parse("SELECT (1 + 2) * 3")
    end

    test "allows cross-group when properly grouped with parentheses" do
      # (a - b - c - d) / e
      {:ok, {:select, ast}} = parse("SELECT (a - b - c - d) / e")
      assert {:binary_op, :divide,
               {:binary_op, :minus,
                 {:binary_op, :minus,
                   {:binary_op, :minus, {:identifier, "a"}, {:identifier, "b"}},
                   {:identifier, "c"}},
                 {:identifier, "d"}},
               {:identifier, "e"}} = ast

      # (a / e) - b - c - d
      {:ok, {:select, ast}} = parse("SELECT (a / e) - b - c - d")
      assert {:binary_op, :minus,
               {:binary_op, :minus,
                 {:binary_op, :minus,
                   {:binary_op, :divide, {:identifier, "a"}, {:identifier, "e"}},
                   {:identifier, "b"}},
                 {:identifier, "c"}},
               {:identifier, "d"}} = ast

      # a - b - ((c - d) / e)
      {:ok, {:select, ast}} = parse("SELECT a - b - ((c - d) / e)")
      assert {:binary_op, :minus,
               {:binary_op, :minus, {:identifier, "a"}, {:identifier, "b"}},
               {:binary_op, :divide,
                 {:binary_op, :minus, {:identifier, "c"}, {:identifier, "d"}},
                 {:identifier, "e"}}} = ast
    end
  end

  describe "parse/1 - comparison operators" do
    test "parses equality" do
      assert {:ok, {:select, {:binary_op, :eq, {:identifier, "x"}, {:number, "1"}}}} =
        parse("SELECT x = 1")
    end

    test "parses inequality" do
      assert {:ok, {:select, {:binary_op, :neq, {:identifier, "x"}, {:string, "test"}}}} =
        parse("SELECT x != 'test'")
    end

    test "parses less than" do
      assert {:ok, {:select, {:binary_op, :lt, {:identifier, "x"}, {:number, "10"}}}} =
        parse("SELECT x < 10")
    end

    test "parses greater than" do
      assert {:ok, {:select, {:binary_op, :gt, {:identifier, "x"}, {:number, "0"}}}} =
        parse("SELECT x > 0")
    end

    test "parses less than or equal" do
      assert {:ok, {:select, {:binary_op, :lte, {:identifier, "x"}, {:number, "100"}}}} =
        parse("SELECT x <= 100")
    end

    test "parses greater than or equal" do
      assert {:ok, {:select, {:binary_op, :gte, {:identifier, "x"}, {:number, "0"}}}} =
        parse("SELECT x >= 0")
    end

    test "rejects chained comparisons" do
      assert {:error, "Cannot chain comparison" <> _} = parse("SELECT 1 < 2 < 3")
    end
  end

  describe "parse/1 - logical operators" do
    test "parses single AND" do
      assert {:ok, {:select, {:binary_op, :and, _, _}}} =
        parse("SELECT a = 1 AND b = 2")
    end

    test "parses single OR" do
      assert {:ok, {:select, {:binary_op, :or, _, _}}} =
        parse("SELECT a = 1 OR b = 2")
    end

    test "allows chaining same logical operator" do
      {:ok, {:select, ast}} = parse("SELECT a = 1 AND b = 2 AND c = 3")
      # Should be left-associative: ((a=1 AND b=2) AND c=3)
      assert {:binary_op, :and, {:binary_op, :and, _, _}, _} = ast

      {:ok, {:select, ast}} = parse("SELECT a = 1 OR b = 2 OR c = 3")
      assert {:binary_op, :or, {:binary_op, :or, _, _}, _} = ast
    end

    test "rejects mixing AND/OR without parentheses" do
      assert {:error, "Ambiguous expression: mixing AND/OR" <> _} =
        parse("SELECT a = 1 AND b = 2 OR c = 3")

      assert {:error, "Ambiguous expression: mixing AND/OR" <> _} =
        parse("SELECT a = 1 OR b = 2 AND c = 3")
    end

    test "allows mixing AND/OR with parentheses" do
      assert {:ok, {:select, {:binary_op, :or, {:binary_op, :and, _, _}, _}}} =
        parse("SELECT (a = 1 AND b = 2) OR c = 3")

      assert {:ok, {:select, {:binary_op, :and, _, {:binary_op, :or, _, _}}}} =
        parse("SELECT a = 1 AND (b = 2 OR c = 3)")
    end
  end

  describe "parse/1 - parentheses" do
    test "parses parenthesized expression" do
      assert {:ok, {:select, {:number, "42"}}} = parse("SELECT (42)")
    end

    test "parses nested parentheses" do
      assert {:ok, {:select, {:binary_op, :plus, _, _}}} = parse("SELECT ((1 + 2))")
    end

    test "rejects unclosed parenthesis" do
      assert {:error, "Expected closing parenthesis" <> _} = parse("SELECT (1 + 2")
    end
  end

  describe "parse/1 - CASE/WHEN" do
    test "parses simple CASE WHEN" do
      {:ok, {:select, ast}} = parse("SELECT CASE WHEN x = 1 THEN 'one' END")

      assert {:case_expr, [when_clause], nil} = ast
      assert {:when, {:binary_op, :eq, _, _}, {:string, "one"}} = when_clause
    end

    test "parses CASE WHEN with ELSE" do
      {:ok, {:select, ast}} = parse("SELECT CASE WHEN x = 1 THEN 'one' ELSE 'other' END")

      assert {:case_expr, [_when], {:string, "other"}} = ast
    end

    test "parses multiple WHEN clauses" do
      {:ok, {:select, ast}} = parse("""
        SELECT CASE
          WHEN x = 1 THEN 'one'
          WHEN x = 2 THEN 'two'
          WHEN x = 3 THEN 'three'
        END
      """)

      assert {:case_expr, when_clauses, nil} = ast
      assert length(when_clauses) == 3
    end

    test "parses nested CASE" do
      {:ok, {:select, ast}} = parse("""
        SELECT CASE
          WHEN x = 1 THEN CASE WHEN y = 2 THEN 'nested' ELSE 'inner' END
          ELSE 'outer'
        END
      """)

      assert {:case_expr, [{:when, _, {:case_expr, _, _}}], {:string, "outer"}} = ast
    end

    test "rejects CASE without WHEN" do
      assert {:error, _} = parse("SELECT CASE END")
    end

    test "rejects CASE without END" do
      assert {:error, "Expected END" <> _} = parse("SELECT CASE WHEN x = 1 THEN 'one'")
    end
  end

  describe "parse/1 - function calls" do
    test "parses function with single argument" do
      assert {:ok, {:select, {:call, :upper, [{:identifier, "x"}]}}} =
        parse("SELECT UPPER(x)")
    end

    test "parses function with multiple arguments" do
      assert {:ok, {:select, {:call, :round, [{:identifier, "x"}, {:number, "2"}]}}} =
        parse("SELECT ROUND(x, 2)")
    end

    test "parses nested function calls" do
      {:ok, {:select, ast}} = parse("SELECT ROUND(COALESCE(x, 0), 2)")

      assert {:call, :round, [{:call, :coalesce, _}, {:number, "2"}]} = ast
    end

    test "parses function with expression argument" do
      {:ok, {:select, ast}} = parse("SELECT ROUND(a / b, 2)")

      assert {:call, :round, [{:binary_op, :divide, _, _}, {:number, "2"}]} = ast
    end

    test "rejects function without closing paren" do
      assert {:error, "Expected closing parenthesis" <> _} = parse("SELECT ROUND(x, 2")
    end
  end

  describe "parse/1 - SELECT is optional" do
    test "parses expression without SELECT" do
      {:ok, tokens} = Lexer.tokenize("42")
      assert {:ok, {:select, {:number, "42"}}} = Parser.parse(tokens)
    end

    test "parses complex expression without SELECT" do
      {:ok, tokens} = Lexer.tokenize("x / y")
      assert {:ok, {:select, {:binary_op, :divide, _, _}}} = Parser.parse(tokens)
    end

    test "parses CASE without SELECT" do
      {:ok, tokens} = Lexer.tokenize("CASE WHEN x = 1 THEN 'yes' ELSE 'no' END")
      assert {:ok, {:select, {:case_expr, _, _}}} = Parser.parse(tokens)
    end
  end

  describe "parse/1 - IN and NOT IN" do
    test "parses simple IN" do
      assert {:ok, {:select, {:in, {:identifier, "x"}, [{:string, "a"}, {:string, "b"}]}}} =
        parse("x IN ('a', 'b')")
    end

    test "parses IN with numbers" do
      assert {:ok, {:select, {:in, {:identifier, "x"}, [{:number, "1"}, {:number, "2"}, {:number, "3"}]}}} =
        parse("x IN (1, 2, 3)")
    end

    test "parses NOT IN" do
      assert {:ok, {:select, {:not_in, {:identifier, "x"}, [{:string, "a"}, {:string, "b"}]}}} =
        parse("x NOT IN ('a', 'b')")
    end

    test "parses IN with single item" do
      assert {:ok, {:select, {:in, {:identifier, "x"}, [{:string, "a"}]}}} =
        parse("x IN ('a')")
    end

    test "parses IN combined with AND" do
      assert {:ok, {:select, {:binary_op, :and, {:in, _, _}, {:binary_op, :gt, _, _}}}} =
        parse("x IN ('a', 'b') AND y > 10")
    end

    test "rejects IN without closing paren" do
      assert {:error, _} = parse("x IN ('a', 'b'")
    end
  end

  describe "parse/1 - IS and IS NOT" do
    test "parses IS NULL" do
      assert {:ok, {:select, {:binary_op, :eq, {:identifier, "x"}, {:null}}}} =
        parse("x IS NULL")
    end

    test "parses IS NOT NULL" do
      assert {:ok, {:select, {:binary_op, :neq, {:identifier, "x"}, {:null}}}} =
        parse("x IS NOT NULL")
    end

    test "parses IS TRUE" do
      assert {:ok, {:select, {:binary_op, :eq, {:identifier, "flag"}, {:boolean, true}}}} =
        parse("flag IS TRUE")
    end

    test "parses IS NOT TRUE" do
      assert {:ok, {:select, {:binary_op, :neq, {:identifier, "flag"}, {:boolean, true}}}} =
        parse("flag IS NOT TRUE")
    end

    test "parses IS FALSE" do
      assert {:ok, {:select, {:binary_op, :eq, {:identifier, "flag"}, {:boolean, false}}}} =
        parse("flag IS FALSE")
    end

    test "parses IS NOT FALSE" do
      assert {:ok, {:select, {:binary_op, :neq, {:identifier, "flag"}, {:boolean, false}}}} =
        parse("flag IS NOT FALSE")
    end

    test "IS NULL combined with AND" do
      assert {:ok, {:select, {:binary_op, :and, {:binary_op, :eq, {:identifier, "x"}, {:null}}, {:binary_op, :eq, _, _}}}} =
        parse("x IS NULL AND y = 1")
    end
  end

  describe "parse/1 - LIKE and NOT LIKE" do
    test "parses simple LIKE" do
      assert {:ok, {:select, {:like, {:identifier, "name"}, {:string, "%test%"}}}} =
        parse("name LIKE '%test%'")
    end

    test "parses NOT LIKE" do
      assert {:ok, {:select, {:not_like, {:identifier, "name"}, {:string, "%test%"}}}} =
        parse("name NOT LIKE '%test%'")
    end

    test "parses LIKE combined with AND" do
      assert {:ok, {:select, {:binary_op, :and, {:like, _, _}, {:binary_op, :eq, _, _}}}} =
        parse("name LIKE '%test%' AND status = 'active'")
    end
  end

  describe "parse/1 - error handling" do
    test "rejects unexpected tokens after expression" do
      assert {:error, "Unexpected tokens" <> _} = parse("SELECT 1 2")
    end
  end
end
