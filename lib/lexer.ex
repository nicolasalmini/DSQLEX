defmodule Dsqlex.Lexer do

  def tokenize(expr) when is_binary(expr) do
    case do_tokenize(expr, []) do
      {:ok, tokens} -> {:ok, Enum.reverse(tokens)}
      error -> error
    end
  end

  # base case: empty string (done)
  defp do_tokenize("", tokens), do: {:ok, tokens}

  # handle whitespaces
  defp do_tokenize(<<char, rest::binary>>, tokens) when char in [?\s, ?\n, ?\t] do
    do_tokenize(rest, tokens)
  end

  # handle commas
  defp do_tokenize(<<",", rest::binary>>, tokens), do: do_tokenize(rest, [{:comma} | tokens])

  # handle ' '
  defp do_tokenize(<<"'", rest::binary>>, tokens) do
    case consume_string(rest) do
      {:ok, string_content, rest} -> do_tokenize(rest, [{:string, string_content} | tokens])
      {:error, reason} -> {:error, reason}
    end
  end

  # handle numbers
  defp do_tokenize(<<c, _rest::binary>> = input, tokens) when c in ?0..?9 do
    {number_str, rest} = consume_number(input)
    do_tokenize(rest, [{:number, number_str} | tokens])
  end

  defp do_tokenize(<<c, _rest::binary>> = input, tokens) when c in ?a..?z or c in ?A..?Z or c == ?_ do
    {word, rest} = consume_identifier(input)
    token = classify_word(word)
    do_tokenize(rest, [token | tokens])
  end

  defp do_tokenize(<<"!=", rest::binary>>, tokens), do: do_tokenize(rest, [{:operator, :neq} | tokens])
  defp do_tokenize(<<"<=", rest::binary>>, tokens), do: do_tokenize(rest, [{:operator, :lte} | tokens])
  defp do_tokenize(<<">=", rest::binary>>, tokens), do: do_tokenize(rest, [{:operator, :gte} | tokens])
  defp do_tokenize(<<"(", rest::binary>>, tokens), do: do_tokenize(rest, [{:lparen} | tokens])
  defp do_tokenize(<<")", rest::binary>>, tokens), do: do_tokenize(rest, [{:rparen} | tokens])
  defp do_tokenize(<<"+", rest::binary>>, tokens), do: do_tokenize(rest, [{:operator, :plus} | tokens])
  defp do_tokenize(<<"-", rest::binary>>, tokens), do: do_tokenize(rest, [{:operator, :minus} | tokens])
  defp do_tokenize(<<"*", rest::binary>>, tokens), do: do_tokenize(rest, [{:operator, :multiply} | tokens])
  defp do_tokenize(<<"/", rest::binary>>, tokens), do: do_tokenize(rest, [{:operator, :divide} | tokens])
  defp do_tokenize(<<"=", rest::binary>>, tokens), do: do_tokenize(rest, [{:operator, :eq} | tokens])
  defp do_tokenize(<<"<", rest::binary>>, tokens), do: do_tokenize(rest, [{:operator, :lt} | tokens])
  defp do_tokenize(<<">", rest::binary>>, tokens), do: do_tokenize(rest, [{:operator, :gt} | tokens])

  # catch-all for unrecognized characters (e.g. trailing dot while user is still typing)
  defp do_tokenize(<<char, _rest::binary>>, _tokens), do: {:error, "Unexpected character: '#{<<char>>}'"}

  # handle numbers
  defp consume_number(input), do: consume_number(input, "")

  defp consume_number(<<c, rest::binary>>, acc) when c in ?0..?9 do
    consume_number(rest, acc <> <<c>>)
  end

  defp consume_number(<<".", c, rest::binary>>, acc) when c in ?0..?9 do
    consume_number(rest, acc <> "." <> <<c>>)
  end

  defp consume_number(rest, acc), do: {acc, rest}

  # handle identifiers
  defp consume_identifier(input), do: consume_identifier(input, "")

  defp consume_identifier(<<c, rest::binary>>, acc) when c in ?a..?z or c in ?A..?Z or c == ?_ or c in ?0..?9 do
    consume_identifier(rest, acc <> <<c>>)
  end

  # dot-access: consume '.' when followed by a letter or underscore (e.g. spread.recognition.payment_percentage)
  defp consume_identifier(<<".", c, rest::binary>>, acc) when c in ?a..?z or c in ?A..?Z or c == ?_ do
    consume_identifier(rest, acc <> "." <> <<c>>)
  end

  defp consume_identifier(rest, acc), do: {acc, rest}

  defp consume_string(input), do: consume_string(input, "")
  defp consume_string(<<"'", rest::binary>>, acc), do: {:ok, acc, rest}
  defp consume_string(<<c, rest::binary>>, acc) do
    consume_string(rest, acc <> <<c>>)
  end
  defp consume_string(_rest, _acc), do: {:error, "Unterminated string"}


  defp classify_word(word) do
    case String.upcase(word) do
      "SELECT"   -> {:keyword, :select}
      "CASE"     -> {:keyword, :case}
      "WHEN"     -> {:keyword, :when}
      "THEN"     -> {:keyword, :then}
      "ELSE"     -> {:keyword, :else}
      "END"      -> {:keyword, :end}
      "AND"      -> {:keyword, :and}
      "OR"       -> {:keyword, :or}
      "NOT"      -> {:keyword, :not}
      "NULL"     -> {:keyword, :null}
      "TRUE"     -> {:keyword, :true}
      "FALSE"    -> {:keyword, :false}
      "UPPER"    -> {:function, :upper}
      "LOWER"    -> {:function, :lower}
      "ROUND"    -> {:function, :round}
      "COALESCE" -> {:function, :coalesce}
      "NVL"      -> {:function, :coalesce} # alias for COALESCE
      "ABS"      -> {:function, :abs}
      "CONCAT"   -> {:function, :concat}
      "EVENT"    -> {:function, :event}
      _ ->          {:identifier, word}
    end
  end
end
