defmodule Dsqlex.LexerTest do
  use ExUnit.Case, async: true

  alias Dsqlex.Lexer

  describe "tokenize/1 - operators" do
    test "single character operators" do
      assert {:ok, [{:operator, :plus}]} = Lexer.tokenize("+")
      assert {:ok, [{:operator, :minus}]} = Lexer.tokenize("-")
      assert {:ok, [{:operator, :multiply}]} = Lexer.tokenize("*")
      assert {:ok, [{:operator, :divide}]} = Lexer.tokenize("/")
      assert {:ok, [{:operator, :eq}]} = Lexer.tokenize("=")
      assert {:ok, [{:operator, :lt}]} = Lexer.tokenize("<")
      assert {:ok, [{:operator, :gt}]} = Lexer.tokenize(">")
    end

    test "multi-character operators" do
      assert {:ok, [{:operator, :neq}]} = Lexer.tokenize("!=")
      assert {:ok, [{:operator, :lte}]} = Lexer.tokenize("<=")
      assert {:ok, [{:operator, :gte}]} = Lexer.tokenize(">=")
    end

    test "multi-char operators take precedence over single-char" do
      assert {:ok, [{:operator, :lte}, {:operator, :gt}]} = Lexer.tokenize("<=>")
    end
  end

  describe "tokenize/1 - delimiters" do
    test "parentheses" do
      assert {:ok, [{:lparen}, {:rparen}]} = Lexer.tokenize("()")
    end

    test "comma" do
      assert {:ok, [{:comma}]} = Lexer.tokenize(",")
    end
  end

  describe "tokenize/1 - numbers" do
    test "integers" do
      assert {:ok, [{:number, "123"}]} = Lexer.tokenize("123")
      assert {:ok, [{:number, "0"}]} = Lexer.tokenize("0")
      assert {:ok, [{:number, "999999"}]} = Lexer.tokenize("999999")
    end

    test "decimals" do
      assert {:ok, [{:number, "3.14"}]} = Lexer.tokenize("3.14")
      assert {:ok, [{:number, "0.5"}]} = Lexer.tokenize("0.5")
      assert {:ok, [{:number, "100.00"}]} = Lexer.tokenize("100.00")
    end

    test "number followed by operator" do
      assert {:ok, [{:number, "10"}, {:operator, :plus}, {:number, "20"}]} =
        Lexer.tokenize("10+20")
    end
  end

  describe "tokenize/1 - strings" do
    test "simple string" do
      assert {:ok, [{:string, "hello"}]} = Lexer.tokenize("'hello'")
      assert {:ok, [{:string, "hello world"}]} = Lexer.tokenize("'hello world'")
    end

    test "empty string" do
      assert {:ok, [{:string, ""}]} = Lexer.tokenize("''")
    end

    test "string with numbers" do
      assert {:ok, [{:string, "abc123"}]} = Lexer.tokenize("'abc123'")
    end

    test "unterminated string returns error" do
      assert {:error, "Unterminated string"} = Lexer.tokenize("'hello")
    end
  end

  describe "tokenize/1 - identifiers" do
    test "simple identifier" do
      assert {:ok, [{:identifier, "my_var"}]} = Lexer.tokenize("my_var")
    end

    test "identifier with numbers" do
      assert {:ok, [{:identifier, "field1"}]} = Lexer.tokenize("field1")
      assert {:ok, [{:identifier, "var2_name"}]} = Lexer.tokenize("var2_name")
    end

    test "identifier starting with underscore" do
      assert {:ok, [{:identifier, "_private"}]} = Lexer.tokenize("_private")
    end
  end

  describe "tokenize/1 - keywords" do
    test "SQL keywords" do
      assert {:ok, [{:keyword, :select}]} = Lexer.tokenize("SELECT")
      assert {:ok, [{:keyword, :case}]} = Lexer.tokenize("CASE")
      assert {:ok, [{:keyword, :when}]} = Lexer.tokenize("WHEN")
      assert {:ok, [{:keyword, :then}]} = Lexer.tokenize("THEN")
      assert {:ok, [{:keyword, :else}]} = Lexer.tokenize("ELSE")
      assert {:ok, [{:keyword, :end}]} = Lexer.tokenize("END")
    end

    test "logical keywords" do
      assert {:ok, [{:keyword, :and}]} = Lexer.tokenize("AND")
      assert {:ok, [{:keyword, :or}]} = Lexer.tokenize("OR")
      assert {:ok, [{:keyword, :not}]} = Lexer.tokenize("NOT")
    end

    test "literal keywords" do
      assert {:ok, [{:keyword, :null}]} = Lexer.tokenize("NULL")
      assert {:ok, [{:keyword, :true}]} = Lexer.tokenize("TRUE")
      assert {:ok, [{:keyword, :false}]} = Lexer.tokenize("FALSE")
    end

    test "keywords are case-insensitive" do
      assert {:ok, [{:keyword, :select}]} = Lexer.tokenize("select")
      assert {:ok, [{:keyword, :select}]} = Lexer.tokenize("Select")
      assert {:ok, [{:keyword, :select}]} = Lexer.tokenize("sElEcT")
    end
  end

  describe "tokenize/1 - functions" do
    test "built-in functions" do
      assert {:ok, [{:function, :upper}]} = Lexer.tokenize("UPPER")
      assert {:ok, [{:function, :lower}]} = Lexer.tokenize("LOWER")
      assert {:ok, [{:function, :round}]} = Lexer.tokenize("ROUND")
      assert {:ok, [{:function, :coalesce}]} = Lexer.tokenize("COALESCE")
      assert {:ok, [{:function, :abs}]} = Lexer.tokenize("ABS")
    end

    test "NVL is alias for COALESCE" do
      assert {:ok, [{:function, :coalesce}]} = Lexer.tokenize("NVL")
    end

    test "EVENT function" do
      assert {:ok, [{:function, :event}]} = Lexer.tokenize("EVENT")
      assert {:ok, [{:function, :event}]} = Lexer.tokenize("event")
      assert {:ok, [{:function, :event}]} = Lexer.tokenize("Event")
    end

    test "functions are case-insensitive" do
      assert {:ok, [{:function, :round}]} = Lexer.tokenize("round")
      assert {:ok, [{:function, :round}]} = Lexer.tokenize("Round")
    end
  end

  describe "tokenize/1 - dot-path identifiers" do
    test "simple dot path" do
      assert {:ok, [{:identifier, "spread.recognition"}]} = Lexer.tokenize("spread.recognition")
    end

    test "multi-level dot path" do
      assert {:ok, [{:identifier, "spread.recognition.payment_percentage"}]} =
        Lexer.tokenize("spread.recognition.payment_percentage")
    end

    test "dot path in expression" do
      assert {:ok, [
        {:identifier, "amount_ext"},
        {:operator, :multiply},
        {:identifier, "spread.recognition.settlement_percentage"}
      ]} = Lexer.tokenize("amount_ext * spread.recognition.settlement_percentage")
    end

    test "dot not consumed when followed by number (decimal)" do
      assert {:ok, [{:number, "1.5"}]} = Lexer.tokenize("1.5")
    end
  end

  describe "tokenize/1 - whitespace handling" do
    test "ignores spaces" do
      assert {:ok, [{:number, "1"}, {:operator, :plus}, {:number, "2"}]} =
        Lexer.tokenize("1 + 2")
    end

    test "ignores tabs" do
      assert {:ok, [{:number, "1"}, {:operator, :plus}, {:number, "2"}]} =
        Lexer.tokenize("1\t+\t2")
    end

    test "ignores newlines" do
      assert {:ok, [{:number, "1"}, {:operator, :plus}, {:number, "2"}]} =
        Lexer.tokenize("1\n+\n2")
    end

    test "handles multiple spaces" do
      assert {:ok, [{:keyword, :select}, {:identifier, "x"}]} =
        Lexer.tokenize("SELECT    x")
    end
  end

  describe "tokenize/1 - complex expressions" do
    test "simple arithmetic" do
      assert {:ok, tokens} = Lexer.tokenize("SELECT (x / y)")

      assert tokens == [
        {:keyword, :select},
        {:lparen},
        {:identifier, "x"},
        {:operator, :divide},
        {:identifier, "y"},
        {:rparen}
      ]
    end

    test "CASE WHEN expression" do
      input = "SELECT CASE WHEN category = 'A' THEN x ELSE y END"
      assert {:ok, tokens} = Lexer.tokenize(input)

      assert tokens == [
        {:keyword, :select},
        {:keyword, :case},
        {:keyword, :when},
        {:identifier, "category"},
        {:operator, :eq},
        {:string, "A"},
        {:keyword, :then},
        {:identifier, "x"},
        {:keyword, :else},
        {:identifier, "y"},
        {:keyword, :end}
      ]
    end

    test "function call with arguments" do
      assert {:ok, tokens} = Lexer.tokenize("ROUND(x, 2)")

      assert tokens == [
        {:function, :round},
        {:lparen},
        {:identifier, "x"},
        {:comma},
        {:number, "2"},
        {:rparen}
      ]
    end

    test "nested function calls" do
      assert {:ok, tokens} = Lexer.tokenize("ROUND(COALESCE(x, 0), 2)")

      assert tokens == [
        {:function, :round},
        {:lparen},
        {:function, :coalesce},
        {:lparen},
        {:identifier, "x"},
        {:comma},
        {:number, "0"},
        {:rparen},
        {:comma},
        {:number, "2"},
        {:rparen}
      ]
    end

    test "comparison with AND/OR" do
      assert {:ok, tokens} = Lexer.tokenize("category = 'A' AND x > 100")

      assert tokens == [
        {:identifier, "category"},
        {:operator, :eq},
        {:string, "A"},
        {:keyword, :and},
        {:identifier, "x"},
        {:operator, :gt},
        {:number, "100"}
      ]
    end
  end

  describe "tokenize/1 - IN and LIKE" do
    test "IN keyword" do
      assert {:ok, tokens} = Lexer.tokenize("x IN ('a', 'b')")

      assert tokens == [
        {:identifier, "x"},
        {:keyword, :in},
        {:lparen},
        {:string, "a"},
        {:comma},
        {:string, "b"},
        {:rparen}
      ]
    end

    test "NOT IN keywords" do
      assert {:ok, tokens} = Lexer.tokenize("x NOT IN (1, 2, 3)")

      assert tokens == [
        {:identifier, "x"},
        {:keyword, :not},
        {:keyword, :in},
        {:lparen},
        {:number, "1"},
        {:comma},
        {:number, "2"},
        {:comma},
        {:number, "3"},
        {:rparen}
      ]
    end

    test "LIKE keyword" do
      assert {:ok, tokens} = Lexer.tokenize("name LIKE '%test%'")

      assert tokens == [
        {:identifier, "name"},
        {:keyword, :like},
        {:string, "%test%"}
      ]
    end

    test "NOT LIKE keywords" do
      assert {:ok, tokens} = Lexer.tokenize("name NOT LIKE '%test%'")

      assert tokens == [
        {:identifier, "name"},
        {:keyword, :not},
        {:keyword, :like},
        {:string, "%test%"}
      ]
    end

    test "IN and LIKE are case insensitive" do
      assert {:ok, tokens1} = Lexer.tokenize("x in ('a')")
      assert {:ok, tokens2} = Lexer.tokenize("x IN ('a')")
      assert tokens1 == tokens2

      assert {:ok, tokens3} = Lexer.tokenize("x like '%a'")
      assert {:ok, tokens4} = Lexer.tokenize("x LIKE '%a'")
      assert tokens3 == tokens4
    end
  end

  describe "tokenize/1 - empty input" do
    test "empty string returns empty list" do
      assert {:ok, []} = Lexer.tokenize("")
    end

    test "only whitespace returns empty list" do
      assert {:ok, []} = Lexer.tokenize("   ")
      assert {:ok, []} = Lexer.tokenize("\n\t ")
    end
  end

  describe "tokenize/1 - comments" do
    test "double-dash line comment is skipped to end of input" do
      assert {:ok, [{:identifier, "x"}]} = Lexer.tokenize("x -- this is a comment")
    end

    test "double-dash line comment ends at newline" do
      assert {:ok, tokens} = Lexer.tokenize("x -- comment\n+ y")

      assert tokens == [
        {:identifier, "x"},
        {:operator, :plus},
        {:identifier, "y"}
      ]
    end

    test "hash line comment is skipped" do
      assert {:ok, [{:identifier, "x"}]} = Lexer.tokenize("# top comment\nx # trailing comment")
    end

    test "block comment is skipped inline" do
      assert {:ok, tokens} = Lexer.tokenize("x /* inline */ + y")

      assert tokens == [
        {:identifier, "x"},
        {:operator, :plus},
        {:identifier, "y"}
      ]
    end

    test "block comment may span multiple lines" do
      assert {:ok, tokens} = Lexer.tokenize("x /*\n  multi\n  line\n*/ + y")

      assert tokens == [
        {:identifier, "x"},
        {:operator, :plus},
        {:identifier, "y"}
      ]
    end

    test "unterminated block comment returns error" do
      assert {:error, "Unterminated block comment"} = Lexer.tokenize("x /* never closes")
    end

    test "comment bodies may contain non-ASCII characters" do
      expr = """
      status_id NOT IN (
        1,  -- pending review
        2,  -- archived – soft-deleted
        3,  -- naïve test
        4   -- staging
      )
      """

      assert {:ok, tokens} = Lexer.tokenize(expr)
      assert {:identifier, "status_id"} in tokens
      assert {:keyword, :not} in tokens
      assert {:keyword, :in} in tokens
      assert {:number, "1"} in tokens
      assert {:number, "4"} in tokens
      refute Enum.any?(tokens, &match?({:operator, :minus}, &1))
    end

    test "minus operator is unaffected when not doubled" do
      assert {:ok, tokens} = Lexer.tokenize("x - y")

      assert tokens == [
        {:identifier, "x"},
        {:operator, :minus},
        {:identifier, "y"}
      ]
    end

    test "divide operator is unaffected when not followed by *" do
      assert {:ok, tokens} = Lexer.tokenize("x / y")

      assert tokens == [
        {:identifier, "x"},
        {:operator, :divide},
        {:identifier, "y"}
      ]
    end
  end

  describe "tokenize/1 - error messages" do
    test "non-ASCII character outside comments returns a UTF-8 valid error" do
      assert {:error, message} = Lexer.tokenize("ô")
      assert String.valid?(message)
      assert message == "Unexpected character: 'ô'"
    end

    test "invalid UTF-8 byte returns a UTF-8 valid hex byte error" do
      # 0xC3 alone is the lead byte of a 2-byte UTF-8 sequence; on its own it is invalid.
      assert {:error, message} = Lexer.tokenize(<<0xC3>>)
      assert String.valid?(message)
      assert message == "Unexpected byte: 0xC3"
    end
  end
end
