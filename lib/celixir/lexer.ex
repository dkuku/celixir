defmodule Celixir.Lexer do
  @moduledoc """
  Tokenizer for the Common Expression Language.
  Converts a CEL source string into a list of tokens.
  """

  # Literals
  @type token_type ::
          :int
          | :uint
          | :float
          | :string
          | :bytes
          | true
          | false
          | :null
          # Identifiers and keywords
          | :ident
          | :in
          # Operators
          | :plus
          | :minus
          | :star
          | :slash
          | :percent
          | :eq
          | :neq
          | :lt
          | :lte
          | :gt
          | :gte
          | :and
          | :or
          | :not
          | :question
          | :colon
          | :dot
          | :comma
          # Delimiters
          | :lparen
          | :rparen
          | :lbracket
          | :rbracket
          | :lbrace
          | :rbrace
          # End
          | :eof

  @type token :: {token_type(), any(), pos_integer()}

  @reserved ~w(as break const continue else for function if import let loop package namespace return var void while)

  @spec tokenize(String.t()) :: {:ok, [token()]} | {:error, String.t()}
  def tokenize(input) do
    tokenize(input, 1, [])
  end

  defp tokenize(<<>>, line, acc), do: {:ok, Enum.reverse([{:eof, nil, line} | acc])}

  # Whitespace
  defp tokenize(<<?\n, rest::binary>>, line, acc), do: tokenize(rest, line + 1, acc)

  defp tokenize(<<c, rest::binary>>, line, acc) when c in [?\s, ?\t, ?\r, ?\f], do: tokenize(rest, line, acc)

  # Single-line comment
  defp tokenize(<<"//", rest::binary>>, line, acc) do
    rest = skip_until_newline(rest)
    tokenize(rest, line, acc)
  end

  # Two-character operators
  defp tokenize(<<"==", rest::binary>>, line, acc), do: tokenize(rest, line, [{:eq, :==, line} | acc])

  defp tokenize(<<"!=", rest::binary>>, line, acc), do: tokenize(rest, line, [{:neq, :!=, line} | acc])

  defp tokenize(<<"<=", rest::binary>>, line, acc), do: tokenize(rest, line, [{:lte, :<=, line} | acc])

  defp tokenize(<<">=", rest::binary>>, line, acc), do: tokenize(rest, line, [{:gte, :>=, line} | acc])

  defp tokenize(<<"&&", rest::binary>>, line, acc), do: tokenize(rest, line, [{:and, :&&, line} | acc])

  defp tokenize(<<"||", rest::binary>>, line, acc), do: tokenize(rest, line, [{:or, :||, line} | acc])

  # Single-character operators
  defp tokenize(<<"+", rest::binary>>, line, acc), do: tokenize(rest, line, [{:plus, :+, line} | acc])

  defp tokenize(<<"-", rest::binary>>, line, acc), do: tokenize(rest, line, [{:minus, :-, line} | acc])

  defp tokenize(<<"*", rest::binary>>, line, acc), do: tokenize(rest, line, [{:star, :*, line} | acc])

  defp tokenize(<<"/", rest::binary>>, line, acc), do: tokenize(rest, line, [{:slash, :/, line} | acc])

  defp tokenize(<<"%", rest::binary>>, line, acc), do: tokenize(rest, line, [{:percent, :%, line} | acc])

  defp tokenize(<<"<", rest::binary>>, line, acc), do: tokenize(rest, line, [{:lt, :<, line} | acc])

  defp tokenize(<<">", rest::binary>>, line, acc), do: tokenize(rest, line, [{:gt, :>, line} | acc])

  defp tokenize(<<"!", rest::binary>>, line, acc), do: tokenize(rest, line, [{:not, :!, line} | acc])

  defp tokenize(<<"?", rest::binary>>, line, acc), do: tokenize(rest, line, [{:question, :question, line} | acc])

  defp tokenize(<<":", rest::binary>>, line, acc), do: tokenize(rest, line, [{:colon, :colon, line} | acc])

  # Float starting with dot: .99 → 0.99
  defp tokenize(<<".", c, _::binary>> = input, line, acc) when c in ?0..?9 do
    # Prepend "0" so read_number can handle it normally
    read_number("0" <> input, line, acc)
  end

  defp tokenize(<<".", rest::binary>>, line, acc), do: tokenize(rest, line, [{:dot, :dot, line} | acc])

  defp tokenize(<<",", rest::binary>>, line, acc), do: tokenize(rest, line, [{:comma, :comma, line} | acc])

  # Delimiters
  defp tokenize(<<"(", rest::binary>>, line, acc), do: tokenize(rest, line, [{:lparen, nil, line} | acc])

  defp tokenize(<<")", rest::binary>>, line, acc), do: tokenize(rest, line, [{:rparen, nil, line} | acc])

  defp tokenize(<<"[", rest::binary>>, line, acc), do: tokenize(rest, line, [{:lbracket, nil, line} | acc])

  defp tokenize(<<"]", rest::binary>>, line, acc), do: tokenize(rest, line, [{:rbracket, nil, line} | acc])

  defp tokenize(<<"{", rest::binary>>, line, acc), do: tokenize(rest, line, [{:lbrace, nil, line} | acc])

  defp tokenize(<<"}", rest::binary>>, line, acc), do: tokenize(rest, line, [{:rbrace, nil, line} | acc])

  # Triple-quoted strings: """ or '''
  defp tokenize(<<?\", ?\", ?\", rest::binary>>, line, acc) do
    case read_triple_string(rest, "\"", line, []) do
      {:ok, value, rest, new_line} ->
        tokenize(rest, new_line, [{:string, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp tokenize(<<?\', ?\', ?\', rest::binary>>, line, acc) do
    case read_triple_string(rest, "'", line, []) do
      {:ok, value, rest, new_line} ->
        tokenize(rest, new_line, [{:string, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  # Bytes triple-quoted: b"""...""" or b'''...'''
  defp tokenize(<<b, ?\", ?\", ?\", rest::binary>>, line, acc) when b in [?b, ?B] do
    case read_triple_string(rest, "\"", line, [], :bytes) do
      {:ok, value, rest2, new_line} ->
        tokenize(rest2, new_line, [{:bytes, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp tokenize(<<b, ?\', ?\', ?\', rest::binary>>, line, acc) when b in [?b, ?B] do
    case read_triple_string(rest, "'", line, [], :bytes) do
      {:ok, value, rest2, new_line} ->
        tokenize(rest2, new_line, [{:bytes, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  # Raw bytes: bR"..." or Br"..." etc.
  defp tokenize(<<b, r, ?\", ?\", ?\", rest::binary>>, line, acc) when b in [?b, ?B] and r in [?r, ?R] do
    case read_raw_triple_string(rest, "\"", line, []) do
      {:ok, value, rest2, new_line} ->
        tokenize(rest2, new_line, [{:bytes, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp tokenize(<<b, r, ?\', ?\', ?\', rest::binary>>, line, acc) when b in [?b, ?B] and r in [?r, ?R] do
    case read_raw_triple_string(rest, "'", line, []) do
      {:ok, value, rest2, new_line} ->
        tokenize(rest2, new_line, [{:bytes, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp tokenize(<<b, r, q, rest::binary>>, line, acc) when b in [?b, ?B] and r in [?r, ?R] and q in [?", ?'] do
    case read_raw_string(rest, <<q>>, line, []) do
      {:ok, value, rest2, new_line} ->
        tokenize(rest2, new_line, [{:bytes, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  # Bytes literal: b"..." or B"..."
  defp tokenize(<<b, q, rest::binary>>, line, acc) when b in [?b, ?B] and q in [?", ?'] do
    quote_char = <<q>>

    case read_string(rest, quote_char, line, [], :bytes) do
      {:ok, value, rest, new_line} ->
        tokenize(rest, new_line, [{:bytes, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  # Raw triple-quoted strings: r"""...""" or r'''...'''
  defp tokenize(<<r, ?\", ?\", ?\", rest::binary>>, line, acc) when r in [?r, ?R] do
    case read_raw_triple_string(rest, "\"", line, []) do
      {:ok, value, rest2, new_line} ->
        tokenize(rest2, new_line, [{:string, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp tokenize(<<r, ?\', ?\', ?\', rest::binary>>, line, acc) when r in [?r, ?R] do
    case read_raw_triple_string(rest, "'", line, []) do
      {:ok, value, rest2, new_line} ->
        tokenize(rest2, new_line, [{:string, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  # Raw strings: r"..." or R"..."
  defp tokenize(<<r, q, rest::binary>>, line, acc) when r in [?r, ?R] and q in [?", ?'] do
    quote_char = <<q>>

    case read_raw_string(rest, quote_char, line, []) do
      {:ok, value, rest, new_line} ->
        tokenize(rest, new_line, [{:string, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  # Strings
  defp tokenize(<<q, rest::binary>>, line, acc) when q in [?", ?'] do
    quote_char = <<q>>

    case read_string(rest, quote_char, line, []) do
      {:ok, value, rest, new_line} ->
        tokenize(rest, new_line, [{:string, value, line} | acc])

      {:error, msg} ->
        {:error, msg}
    end
  end

  # Numbers: hex, float, uint, int
  defp tokenize(<<"0x", rest::binary>>, line, acc), do: read_hex(rest, line, acc)
  defp tokenize(<<"0X", rest::binary>>, line, acc), do: read_hex(rest, line, acc)

  defp tokenize(<<c, _::binary>> = input, line, acc) when c in ?0..?9 do
    read_number(input, line, acc)
  end

  # Identifiers and keywords
  defp tokenize(<<c, _::binary>> = input, line, acc) when c in ?a..?z or c in ?A..?Z or c == ?_ do
    {ident, rest} = read_ident(input, [])

    token =
      case ident do
        "true" -> {true, true, line}
        "false" -> {false, false, line}
        "null" -> {:null, nil, line}
        "in" -> {:in, :in, line}
        reserved when reserved in @reserved -> {:ident, reserved, line}
        _ -> {:ident, ident, line}
      end

    tokenize(rest, line, [token | acc])
  end

  # Backtick-quoted identifiers: `foo.bar` → ident token
  defp tokenize(<<"`", rest::binary>>, line, acc) do
    case read_backtick_ident(rest, line, []) do
      {:ok, ident, rest2} ->
        tokenize(rest2, line, [{:ident, ident, line} | acc])

      {:error, _} = err ->
        err
    end
  end

  defp tokenize(<<c, _::binary>>, line, _acc) do
    {:error, "line #{line}: unexpected character '#{<<c>>}'"}
  end

  # --- Helpers ---

  defp skip_until_newline(<<?\n, rest::binary>>), do: <<?\n, rest::binary>>
  defp skip_until_newline(<<_, rest::binary>>), do: skip_until_newline(rest)
  defp skip_until_newline(<<>>), do: <<>>

  defp read_ident(<<c, rest::binary>>, acc) when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ do
    read_ident(rest, [c | acc])
  end

  defp read_ident(rest, acc), do: {acc |> Enum.reverse() |> List.to_string(), rest}

  defp read_backtick_ident(<<>>, line, _acc), do: {:error, "line #{line}: unterminated backtick identifier"}

  defp read_backtick_ident(<<"`", rest::binary>>, _line, acc) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp read_backtick_ident(<<?\n, _::binary>>, line, _acc), do: {:error, "line #{line}: newline in backtick identifier"}

  defp read_backtick_ident(<<c::utf8, rest::binary>>, line, acc) do
    read_backtick_ident(rest, line, [<<c::utf8>> | acc])
  end

  defp read_hex(input, line, acc) do
    {digits, rest} = read_hex_digits(input, [])

    if digits == [] do
      {:error, "line #{line}: expected hex digits after 0x"}
    else
      value = digits |> Enum.reverse() |> List.to_string() |> String.to_integer(16)

      case rest do
        <<u, rest2::binary>> when u in [?u, ?U] ->
          tokenize(rest2, line, [{:uint, value, line} | acc])

        _ ->
          tokenize(rest, line, [{:int, value, line} | acc])
      end
    end
  end

  defp read_hex_digits(<<c, rest::binary>>, acc) when c in ?0..?9 or c in ?a..?f or c in ?A..?F do
    read_hex_digits(rest, [c | acc])
  end

  defp read_hex_digits(rest, acc), do: {acc, rest}

  defp read_number(input, line, acc) do
    {int_digits, rest} = read_digits(input, [])

    case rest do
      # Float: digits.digits or digits.digitsE...
      <<?., c, _rest_after::binary>> when c in ?0..?9 ->
        # skip the dot
        <<_dot, rest2::binary>> = rest
        {frac_digits, rest3} = read_digits(rest2, [])
        {exp_str, rest4} = read_exponent(rest3)

        float_str = List.to_string(int_digits) <> "." <> List.to_string(frac_digits) <> exp_str
        value = String.to_float(float_str)
        tokenize(rest4, line, [{:float, value, line} | acc])

      # Float: digitsE...
      <<e, _rest_after::binary>> when e in [?e, ?E] ->
        {exp_str, rest2} = read_exponent(rest)
        float_str = List.to_string(int_digits) <> ".0" <> exp_str
        value = String.to_float(float_str)
        tokenize(rest2, line, [{:float, value, line} | acc])

      # Uint
      <<u, rest2::binary>> when u in [?u, ?U] ->
        value = int_digits |> List.to_string() |> String.to_integer()
        tokenize(rest2, line, [{:uint, value, line} | acc])

      # Int
      _ ->
        value = int_digits |> List.to_string() |> String.to_integer()
        tokenize(rest, line, [{:int, value, line} | acc])
    end
  end

  defp read_digits(<<c, rest::binary>>, acc) when c in ?0..?9, do: read_digits(rest, [c | acc])
  defp read_digits(rest, acc), do: {Enum.reverse(acc), rest}

  defp read_exponent(<<e, ?+, rest::binary>>) when e in [?e, ?E] do
    {digits, rest2} = read_digits(rest, [])
    {"e+" <> List.to_string(digits), rest2}
  end

  defp read_exponent(<<e, ?-, rest::binary>>) when e in [?e, ?E] do
    {digits, rest2} = read_digits(rest, [])
    {"e-" <> List.to_string(digits), rest2}
  end

  defp read_exponent(<<e, rest::binary>>) when e in [?e, ?E] do
    {digits, rest2} = read_digits(rest, [])
    {"e" <> List.to_string(digits), rest2}
  end

  defp read_exponent(rest), do: {"", rest}

  # String reading with escape sequences
  defp read_string(input, quote, line, acc), do: read_string(input, quote, line, acc, :string)

  defp read_string(<<>>, _quote, line, _acc, _mode), do: {:error, "line #{line}: unterminated string"}

  defp read_string(<<?\n, _::binary>>, _quote, line, _acc, _mode), do: {:error, "line #{line}: newline in string literal"}

  defp read_string(input, quote, line, acc, mode) do
    qlen = byte_size(quote)

    case input do
      <<^quote::binary-size(qlen), rest::binary>> ->
        {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest, line}

      <<"\\", rest::binary>> ->
        case read_escape(rest, line, mode) do
          {:ok, char, rest2} -> read_string(rest2, quote, line, [char | acc], mode)
          {:error, _} = err -> err
        end

      <<c::utf8, rest::binary>> ->
        read_string(rest, quote, line, [<<c::utf8>> | acc], mode)
    end
  end

  defp read_raw_string(<<>>, _quote, line, _acc), do: {:error, "line #{line}: unterminated string"}

  defp read_raw_string(input, quote, line, acc) do
    qlen = byte_size(quote)

    case input do
      <<^quote::binary-size(qlen), rest::binary>> ->
        {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest, line}

      <<?\n, rest::binary>> ->
        read_raw_string(rest, quote, line + 1, ["\n" | acc])

      <<c::utf8, rest::binary>> ->
        read_raw_string(rest, quote, line, [<<c::utf8>> | acc])
    end
  end

  defp read_raw_triple_string(input, quote, line, acc) do
    triple = String.duplicate(quote, 3)

    case input do
      <<>> ->
        {:error, "line #{line}: unterminated raw triple-quoted string"}

      <<^triple::binary-size(3), rest::binary>> ->
        {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest, line}

      <<?\n, rest::binary>> ->
        read_raw_triple_string(rest, quote, line + 1, ["\n" | acc])

      <<c::utf8, rest::binary>> ->
        read_raw_triple_string(rest, quote, line, [<<c::utf8>> | acc])
    end
  end

  defp read_triple_string(input, quote, line, acc), do: read_triple_string(input, quote, line, acc, :string)

  defp read_triple_string(input, quote, line, acc, mode) do
    triple = String.duplicate(quote, 3)

    case input do
      <<>> ->
        {:error, "line #{line}: unterminated triple-quoted string"}

      <<^triple::binary-size(3), rest::binary>> ->
        {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest, line}

      <<?\n, rest::binary>> ->
        read_triple_string(rest, quote, line + 1, ["\n" | acc], mode)

      <<"\\", rest::binary>> ->
        case read_escape(rest, line, mode) do
          {:ok, char, rest2} -> read_triple_string(rest2, quote, line, [char | acc], mode)
          {:error, _} = err -> err
        end

      <<c::utf8, rest::binary>> ->
        read_triple_string(rest, quote, line, [<<c::utf8>> | acc], mode)
    end
  end

  defp read_escape(<<"a", rest::binary>>, _line, _mode), do: {:ok, "\a", rest}
  defp read_escape(<<"b", rest::binary>>, _line, _mode), do: {:ok, "\b", rest}
  defp read_escape(<<"f", rest::binary>>, _line, _mode), do: {:ok, "\f", rest}
  defp read_escape(<<"n", rest::binary>>, _line, _mode), do: {:ok, "\n", rest}
  defp read_escape(<<"r", rest::binary>>, _line, _mode), do: {:ok, "\r", rest}
  defp read_escape(<<"t", rest::binary>>, _line, _mode), do: {:ok, "\t", rest}
  defp read_escape(<<"v", rest::binary>>, _line, _mode), do: {:ok, "\v", rest}
  defp read_escape(<<"\\", rest::binary>>, _line, _mode), do: {:ok, "\\", rest}
  defp read_escape(<<"?", rest::binary>>, _line, _mode), do: {:ok, "?", rest}
  defp read_escape(<<"\"", rest::binary>>, _line, _mode), do: {:ok, "\"", rest}
  defp read_escape(<<"'", rest::binary>>, _line, _mode), do: {:ok, "'", rest}
  defp read_escape(<<"`", rest::binary>>, _line, _mode), do: {:ok, "`", rest}

  # Octal escape: \[0-3][0-7][0-7] — must come before \0 handler
  # In string mode, produces UTF-8 encoded code point; in bytes mode, raw byte
  defp read_escape(<<o1, o2, o3, rest::binary>>, _line, mode) when o1 in ?0..?3 and o2 in ?0..?7 and o3 in ?0..?7 do
    value = (o1 - ?0) * 64 + (o2 - ?0) * 8 + (o3 - ?0)
    if mode == :bytes, do: {:ok, <<value>>, rest}, else: {:ok, <<value::utf8>>, rest}
  end

  # Null byte: \0 (not followed by octal digits — handled above)
  defp read_escape(<<"0", rest::binary>>, _line, _mode), do: {:ok, <<0>>, rest}

  # Hex escape: \xHH
  # In string mode, produces UTF-8 encoded code point; in bytes mode, raw byte
  defp read_escape(<<x, h1, h2, rest::binary>>, _line, mode) when x in [?x, ?X] do
    with {:ok, v} <- hex_value(<<h1, h2>>) do
      if mode == :bytes, do: {:ok, <<v>>, rest}, else: {:ok, <<v::utf8>>, rest}
    end
  end

  # Unicode escape: \uHHHH
  defp read_escape(<<"u", h1, h2, h3, h4, rest::binary>>, _line, _mode) do
    with {:ok, v} <- hex_value(<<h1, h2, h3, h4>>) do
      {:ok, <<v::utf8>>, rest}
    end
  end

  # Unicode escape: \UHHHHHHHH
  defp read_escape(<<"U", h1, h2, h3, h4, h5, h6, h7, h8, rest::binary>>, _line, _mode) do
    with {:ok, v} <- hex_value(<<h1, h2, h3, h4, h5, h6, h7, h8>>) do
      {:ok, <<v::utf8>>, rest}
    end
  end

  defp read_escape(<<c, _::binary>>, line, _mode), do: {:error, "line #{line}: invalid escape sequence '\\#{<<c>>}'"}

  defp read_escape(<<>>, line, _mode), do: {:error, "line #{line}: unterminated escape sequence"}

  defp hex_value(hex_str) do
    case Integer.parse(hex_str, 16) do
      {v, ""} -> {:ok, v}
      _ -> {:error, "invalid hex escape"}
    end
  end
end
