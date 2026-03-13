defmodule Celixir.Conformance.TextprotoParser do
  @moduledoc """
  Parser for cel-spec textproto conformance test files.

  Parses the SimpleTestFile textproto format into structured Elixir data:

      %{
        name: "basic",
        description: "...",
        sections: [
          %{
            name: "self_eval_zeroish",
            description: "...",
            tests: [
              %{
                name: "self_eval_int_zero",
                expr: "0",
                value: {:int64, 0},
                bindings: %{},
                disable_check: false
              }
            ]
          }
        ]
      }
  """

  @doc "Parse a textproto file content string into structured test data."
  def parse(content) do
    lines = String.split(content, "\n")
    tokens = tokenize(lines)
    parse_file(tokens)
  end

  # Tokenization - convert lines to a flat list of tokens
  defp tokenize(lines) do
    Enum.flat_map(lines, &tokenize_line/1)
  end

  defp tokenize_line(line) do
    line = String.trim(line)
    # Skip comments and empty lines
    if line == "" or String.starts_with?(line, "#") do
      []
    else
      scan(line, [])
    end
  end

  defp scan("", acc), do: Enum.reverse(acc)
  defp scan(<<" ", rest::binary>>, acc), do: scan(String.trim_leading(rest), acc)
  defp scan(<<"\t", rest::binary>>, acc), do: scan(String.trim_leading(rest), acc)

  defp scan(<<"{", rest::binary>>, acc), do: scan(rest, [{:lbrace} | acc])
  defp scan(<<"}", rest::binary>>, acc), do: scan(rest, [{:rbrace} | acc])
  defp scan(<<":", rest::binary>>, acc), do: scan(String.trim_leading(rest), [{:colon} | acc])
  # skip commas
  defp scan(<<",", rest::binary>>, acc), do: scan(String.trim_leading(rest), acc)

  # Handle ## comments (textproto uses # for comments too)
  defp scan(<<"#", _::binary>>, acc), do: Enum.reverse(acc)

  # Quoted string with double quotes
  defp scan(<<"\"", rest::binary>>, acc) do
    {str, rest2} = scan_string(rest, "\"", [])
    scan(rest2, [{:string, str} | acc])
  end

  # Quoted string with single quotes
  defp scan(<<"'", rest::binary>>, acc) do
    {str, rest2} = scan_string(rest, "'", [])
    scan(rest2, [{:string, str} | acc])
  end

  # Negative infinity
  defp scan(<<"-inf", rest::binary>>, acc), do: scan(rest, [{:ident, "-inf"} | acc])

  # Negative number
  defp scan(<<"-", c, _::binary>> = input, acc) when c in ?0..?9 do
    {num, rest} = scan_number(input)
    scan(rest, [{:number, num} | acc])
  end

  # Number
  defp scan(<<c, _::binary>> = input, acc) when c in ?0..?9 do
    {num, rest} = scan_number(input)
    scan(rest, [{:number, num} | acc])
  end

  # Identifier/keyword
  defp scan(<<c, _::binary>> = input, acc) when c in ?a..?z or c in ?A..?Z or c == ?_ do
    {ident, rest} = scan_ident(input)
    scan(rest, [{:ident, ident} | acc])
  end

  defp scan(<<_c, rest::binary>>, acc), do: scan(rest, acc)

  defp scan_string(<<>>, _delim, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), ""}

  defp scan_string(<<"\\", ?x, h1, h2, rest::binary>>, delim, acc) do
    byte = String.to_integer(<<h1, h2>>, 16)
    scan_string(rest, delim, [<<byte>> | acc])
  end

  defp scan_string(<<"\\", ?u, h1, h2, h3, h4, rest::binary>>, delim, acc) do
    codepoint = String.to_integer(<<h1, h2, h3, h4>>, 16)
    scan_string(rest, delim, [<<codepoint::utf8>> | acc])
  end

  defp scan_string(<<"\\", ?U, h1, h2, h3, h4, h5, h6, h7, h8, rest::binary>>, delim, acc) do
    codepoint = String.to_integer(<<h1, h2, h3, h4, h5, h6, h7, h8>>, 16)
    scan_string(rest, delim, [<<codepoint::utf8>> | acc])
  end

  defp scan_string(<<"\\", c, rest::binary>>, delim, acc) when c in ?1..?3 do
    <<o1, o2, rest2::binary>> = rest
    byte = String.to_integer(<<c, o1, o2>>, 8)
    scan_string(rest2, delim, [<<byte>> | acc])
  end

  defp scan_string(<<"\\", c, rest::binary>>, delim, acc) do
    char =
      case c do
        ?\\ -> "\\"
        ?" -> "\""
        ?' -> "'"
        ?n -> "\n"
        ?t -> "\t"
        ?r -> "\r"
        ?a -> "\a"
        ?b -> "\b"
        ?f -> "\f"
        ?v -> "\v"
        ?0 -> <<0>>
        _ -> <<c>>
      end

    scan_string(rest, delim, [char | acc])
  end

  defp scan_string(<<c, rest::binary>>, delim, acc) do
    if <<c>> == delim do
      {IO.iodata_to_binary(Enum.reverse(acc)), rest}
    else
      scan_string(rest, delim, [<<c>> | acc])
    end
  end

  defp scan_number(input) do
    {num_str, rest} =
      take_while(input, fn c ->
        c in ?0..?9 or c == ?. or c == ?e or c == ?E or c == ?+ or c == ?-
      end)

    num =
      if String.contains?(num_str, ".") or String.contains?(num_str, "e") or
           String.contains?(num_str, "E") do
        {f, _} = Float.parse(num_str)
        f
      else
        {i, _} = Integer.parse(num_str)
        i
      end

    {num, rest}
  end

  defp scan_ident(input) do
    take_while(input, fn c ->
      c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_
    end)
  end

  defp take_while(<<>>, _pred), do: {"", ""}

  defp take_while(<<c, rest::binary>> = input, pred) do
    if pred.(c) do
      {more, final_rest} = take_while(rest, pred)
      {<<c, more::binary>>, final_rest}
    else
      {"", input}
    end
  end

  # Parsing tokens into structured data

  defp parse_file(tokens) do
    {fields, _rest} = parse_fields(tokens)

    %{
      name: get_string(fields, "name"),
      description: get_string(fields, "description"),
      sections: fields |> get_all("section") |> Enum.map(&parse_section/1)
    }
  end

  defp parse_section(fields) do
    %{
      name: get_string(fields, "name"),
      description: get_string(fields, "description"),
      tests: fields |> get_all("test") |> Enum.map(&parse_test/1)
    }
  end

  defp parse_test(fields) do
    %{
      name: get_string(fields, "name"),
      description: get_string(fields, "description"),
      expr: get_string(fields, "expr"),
      container: get_string(fields, "container"),
      value: parse_expected_value(fields),
      eval_error: has_field?(fields, "eval_error"),
      bindings: parse_bindings(fields),
      disable_check: get_bool(fields, "disable_check"),
      check_only: get_bool(fields, "check_only"),
      type_env: parse_type_env(fields),
      deduced_type: parse_deduced_type(fields)
    }
  end

  defp parse_expected_value(fields) do
    # Check direct value block first, then typed_result.result
    case get_block(fields, "value") do
      nil ->
        case get_block(fields, "typed_result") do
          nil ->
            nil

          typed_result_fields ->
            case get_block(typed_result_fields, "result") do
              nil -> nil
              result_fields -> extract_typed_value(result_fields)
            end
        end

      value_fields ->
        extract_typed_value(value_fields)
    end
  end

  defp extract_typed_value(fields) do
    cond do
      has_scalar?(fields, "int64_value") ->
        {:int64, get_number(fields, "int64_value")}

      has_scalar?(fields, "uint64_value") ->
        {:uint64, get_number(fields, "uint64_value")}

      has_scalar?(fields, "double_value") ->
        {:double, get_double(fields, "double_value")}

      has_scalar?(fields, "bool_value") ->
        {:bool, get_bool(fields, "bool_value")}

      has_scalar?(fields, "string_value") ->
        {:string, get_string(fields, "string_value")}

      has_scalar?(fields, "bytes_value") ->
        {:bytes, get_string(fields, "bytes_value")}

      has_field?(fields, "null_value") ->
        {:null, nil}

      has_field?(fields, "list_value") ->
        list_fields = get_block(fields, "list_value") || []
        values = list_fields |> get_all("values") |> Enum.map(&extract_typed_value/1)
        {:list, values}

      has_field?(fields, "map_value") ->
        map_fields = get_block(fields, "map_value") || []

        entries =
          map_fields
          |> get_all("entries")
          |> Enum.map(fn entry_fields ->
            key_fields = get_block(entry_fields, "key") || []
            val_fields = get_block(entry_fields, "value") || []
            {extract_typed_value(key_fields), extract_typed_value(val_fields)}
          end)

        {:map, entries}

      has_field?(fields, "type_value") ->
        {:type, get_string(fields, "type_value")}

      has_field?(fields, "enum_value") ->
        # Enum values — in legacy mode, treat as int
        enum_fields = get_block(fields, "enum_value") || []
        {:int64, get_number(enum_fields, "value") || 0}

      has_field?(fields, "object_value") ->
        obj_fields = get_block(fields, "object_value") || []
        extract_object_value(obj_fields)

      true ->
        nil
    end
  end

  # Handle protobuf Any-typed object_value blocks.
  # The tokenizer strips brackets/dots, so [type.googleapis.com/google.protobuf.Duration] { ... }
  # becomes a block named "Duration" (the last ident before the brace).
  @wrapper_type_names ~w(
    BoolValue Int32Value Int64Value UInt32Value UInt64Value
    FloatValue DoubleValue StringValue BytesValue
  )

  @wrapper_type_map %{
    "BoolValue" => "google.protobuf.BoolValue",
    "Int32Value" => "google.protobuf.Int32Value",
    "Int64Value" => "google.protobuf.Int64Value",
    "UInt32Value" => "google.protobuf.UInt32Value",
    "UInt64Value" => "google.protobuf.UInt64Value",
    "FloatValue" => "google.protobuf.FloatValue",
    "DoubleValue" => "google.protobuf.DoubleValue",
    "StringValue" => "google.protobuf.StringValue",
    "BytesValue" => "google.protobuf.BytesValue"
  }

  defp extract_object_value(obj_fields) do
    cond do
      has_field?(obj_fields, "Duration") ->
        dur_fields = get_block(obj_fields, "Duration") || []
        seconds = get_number(dur_fields, "seconds") || 0
        nanos = get_number(dur_fields, "nanos") || 0
        {:duration, seconds, nanos}

      has_field?(obj_fields, "Timestamp") ->
        ts_fields = get_block(obj_fields, "Timestamp") || []
        seconds = get_number(ts_fields, "seconds") || 0
        nanos = get_number(ts_fields, "nanos") || 0
        {:timestamp, seconds, nanos}

      # Wrapper types (Int32Value, StringValue, etc.)
      (wrapper_name = Enum.find(@wrapper_type_names, &has_field?(obj_fields, &1))) != nil ->
        wrapper_fields = get_block(obj_fields, wrapper_name) || []
        full_name = Map.fetch!(@wrapper_type_map, wrapper_name)
        inner = extract_wrapper_value(wrapper_fields, full_name)
        {:object, full_name, inner}

      # Value type
      has_field?(obj_fields, "Value") ->
        val_fields = get_block(obj_fields, "Value") || []
        {:object, "google.protobuf.Value", extract_value_fields(val_fields)}

      # Struct type
      has_field?(obj_fields, "Struct") ->
        struct_fields = get_block(obj_fields, "Struct") || []
        {:object, "google.protobuf.Struct", extract_struct_fields(struct_fields)}

      # ListValue type
      has_field?(obj_fields, "ListValue") ->
        list_fields = get_block(obj_fields, "ListValue") || []
        {:object, "google.protobuf.ListValue", extract_list_value_fields(list_fields)}

      # TestAllTypes
      has_field?(obj_fields, "TestAllTypes") ->
        tat_fields = get_block(obj_fields, "TestAllTypes") || []
        {:object, "TestAllTypes", extract_raw_fields(tat_fields)}

      true ->
        nil
    end
  end

  defp extract_wrapper_value(fields, _full_name) do
    %{"value" => extract_scalar_value(fields)}
  end

  defp extract_scalar_value(fields) do
    if has_scalar?(fields, "value") do
      case List.keyfind(fields, "value", 0) do
        {_, {:scalar, v}} -> v
        _ -> nil
      end
    end
  end

  defp extract_value_fields(fields) do
    cond do
      has_scalar?(fields, "number_value") ->
        %{"number_value" => get_number(fields, "number_value")}

      has_scalar?(fields, "string_value") ->
        %{"string_value" => get_string(fields, "string_value")}

      has_scalar?(fields, "bool_value") ->
        %{"bool_value" => get_bool(fields, "bool_value")}

      has_field?(fields, "null_value") ->
        %{"null_value" => nil}

      has_field?(fields, "list_value") ->
        list_block = get_block(fields, "list_value") || []
        %{"list_value" => extract_list_value_fields(list_block)}

      has_field?(fields, "struct_value") ->
        struct_block = get_block(fields, "struct_value") || []
        %{"struct_value" => extract_struct_fields(struct_block)}

      true ->
        %{}
    end
  end

  defp extract_struct_fields(fields) do
    # Struct has multiple `fields { key: "k" value { ... } }` blocks — these are map entries.
    entries =
      fields
      |> get_all("fields")
      |> Enum.map(fn entry_fields ->
        key = get_string(entry_fields, "key")
        val_fields = get_block(entry_fields, "value") || []
        {key, extract_value_fields(val_fields)}
      end)

    %{"fields" => Map.new(entries)}
  end

  defp extract_list_value_fields(fields) do
    values =
      fields
      |> get_all("values")
      |> Enum.map(fn val_fields ->
        extract_value_fields(val_fields)
      end)

    %{"values" => values}
  end

  # Known field names that contain ListValue messages
  @list_value_fields ~w(list_value)
  # Known field names that contain Struct messages
  @struct_fields ~w(single_struct struct_value)
  # Known field names that contain Value messages
  @value_fields ~w(single_value)
  # Known field names that contain enum values
  @enum_fields ~w(standalone_enum single_nested_enum repeated_nested_enum)

  # Known proto enum ident-to-int mappings
  @enum_ident_values %{
    "FOO" => 0,
    "BAR" => 1,
    "BAZ" => 2,
    "GOO" => 0,
    "GAR" => 1,
    "GAZ" => 2
  }

  defp extract_raw_fields(fields) do
    # Group by field name to detect repeated fields
    grouped = Enum.group_by(fields, fn {name, _} -> name end, fn {_, val} -> val end)

    Map.new(grouped, fn
      {name, [single]} ->
        case single do
          {:scalar, v} -> {name, maybe_convert_enum_field(name, v)}
          {:block, block} -> {name, extract_raw_block_for(name, block)}
        end

      {name, multiples} ->
        # Repeated field — keep as list of extracted values
        vals =
          Enum.map(multiples, fn
            {:block, block} -> extract_raw_block_for(name, block)
            {:scalar, v} -> maybe_convert_enum_field(name, v)
          end)

        {name, vals}
    end)
  end

  # Convert enum ident strings to integers for enum fields
  defp maybe_convert_enum_field(name, v) when is_binary(v) and name in @enum_fields do
    Map.get(@enum_ident_values, v, v)
  end

  defp maybe_convert_enum_field(_name, v), do: v

  # Route block extraction based on the field name
  defp extract_raw_block_for(name, block) do
    cond do
      name in @list_value_fields -> extract_list_value_fields(block)
      name in @struct_fields -> extract_struct_fields(block)
      name in @value_fields -> extract_value_fields(block)
      true -> extract_raw_fields(block)
    end
  end

  defp parse_type_env(fields) do
    fields
    |> get_all("type_env")
    |> Enum.map(&parse_type_env_entry/1)
  end

  defp parse_type_env_entry(fields) do
    name = get_string(fields, "name")

    cond do
      has_field?(fields, "ident") ->
        ident_fields = get_block(fields, "ident") || []
        type_fields = get_block(ident_fields, "type") || []
        %{name: name, kind: :ident, type: parse_cel_type(type_fields)}

      has_field?(fields, "function") ->
        func_fields = get_block(fields, "function") || []
        overloads = parse_function_overloads(func_fields)
        %{name: name, kind: :function, overloads: overloads}
    end
  end

  defp parse_function_overloads(func_fields) do
    func_fields
    |> get_all("overloads")
    |> Enum.map(fn overload_fields ->
      id = get_string(overload_fields, "overload_id")
      result_type_fields = get_block(overload_fields, "result_type") || []
      params = overload_fields |> get_all("params") |> Enum.map(&parse_cel_type/1)

      %{
        id: id,
        params: params,
        result_type: parse_cel_type(result_type_fields)
      }
    end)
  end

  defp parse_deduced_type(fields) do
    case get_block(fields, "typed_result") do
      nil ->
        nil

      typed_result_fields ->
        case get_block(typed_result_fields, "deduced_type") do
          nil -> nil
          type_fields -> parse_cel_type(type_fields)
        end
    end
  end

  @primitive_map %{
    "BOOL" => :bool,
    "INT64" => :int,
    "UINT64" => :uint,
    "DOUBLE" => :double,
    "STRING" => :string,
    "BYTES" => :bytes
  }

  @well_known_map %{
    "DURATION" => :duration,
    "TIMESTAMP" => :timestamp
  }

  defp parse_cel_type(fields) do
    cond do
      has_scalar?(fields, "primitive") ->
        prim = get_scalar(fields, "primitive")
        Map.get(@primitive_map, prim, prim)

      has_field?(fields, "null") ->
        :null_type

      has_field?(fields, "dyn") ->
        :dyn

      has_scalar?(fields, "message_type") ->
        {:message, get_string(fields, "message_type")}

      has_scalar?(fields, "well_known") ->
        wk = get_scalar(fields, "well_known")
        {:well_known, Map.get(@well_known_map, wk, wk)}

      has_scalar?(fields, "wrapper") ->
        w = get_scalar(fields, "wrapper")
        {:wrapper, Map.get(@primitive_map, w, w)}

      has_field?(fields, "list_type") ->
        list_fields = get_block(fields, "list_type") || []
        elem_fields = get_block(list_fields, "elem_type") || []
        {:list, parse_cel_type(elem_fields)}

      has_field?(fields, "map_type") ->
        map_fields = get_block(fields, "map_type") || []
        key_fields = get_block(map_fields, "key_type") || []
        val_fields = get_block(map_fields, "value_type") || []
        {:map, parse_cel_type(key_fields), parse_cel_type(val_fields)}

      has_field?(fields, "abstract_type") ->
        abs_fields = get_block(fields, "abstract_type") || []
        abs_name = get_string(abs_fields, "name")
        param_types = abs_fields |> get_all("parameter_types") |> Enum.map(&parse_cel_type/1)
        {:abstract, abs_name, param_types}

      has_scalar?(fields, "type_param") ->
        {:type_param, get_string(fields, "type_param")}

      true ->
        nil
    end
  end

  defp parse_bindings(fields) do
    case get_all(fields, "bindings") do
      [] ->
        %{}

      binding_list ->
        Map.new(binding_list, fn bf ->
          key = get_string(bf, "key")
          # Bindings have value: { value: { int64_value: ... } } (nested)
          outer_value = get_block(bf, "value") || []
          inner_value = get_block(outer_value, "value") || outer_value
          value = extract_typed_value(inner_value)
          {key, value}
        end)
    end
  end

  # Field access helpers

  defp parse_fields(tokens), do: parse_fields(tokens, [])

  defp parse_fields([], acc), do: {Enum.reverse(acc), []}
  defp parse_fields([{:rbrace} | rest], acc), do: {Enum.reverse(acc), rest}

  defp parse_fields([{:ident, name}, {:colon} | rest], acc) do
    case rest do
      [{:string, val} | rest2] ->
        # Handle textproto string concatenation: adjacent strings are joined
        {extra_strings, rest3} = collect_adjacent_strings(rest2)
        combined = Enum.join([val | extra_strings])
        parse_fields(rest3, [{name, {:scalar, combined}} | acc])

      [{:number, val} | rest2] ->
        parse_fields(rest2, [{name, {:scalar, val}} | acc])

      [{:ident, "true"} | rest2] ->
        parse_fields(rest2, [{name, {:scalar, true}} | acc])

      [{:ident, "false"} | rest2] ->
        parse_fields(rest2, [{name, {:scalar, false}} | acc])

      [{:ident, "NULL_VALUE"} | rest2] ->
        parse_fields(rest2, [{name, {:scalar, nil}} | acc])

      [{:ident, "inf"} | rest2] ->
        parse_fields(rest2, [{name, {:scalar, :infinity}} | acc])

      [{:ident, "Infinity"} | rest2] ->
        parse_fields(rest2, [{name, {:scalar, :infinity}} | acc])

      # Handle -inf (negative infinity)
      [{:ident, "-inf"} | rest2] ->
        parse_fields(rest2, [{name, {:scalar, :neg_infinity}} | acc])

      [{:lbrace} | rest2] ->
        {block_fields, rest3} = parse_fields(rest2)
        parse_fields(rest3, [{name, {:block, block_fields}} | acc])

      # Bare ident value (e.g., enum constants like BAZ, FOO, or numeric idents like NaN)
      [{:ident, val} | rest2] ->
        parse_fields(rest2, [{name, {:scalar, val}} | acc])

      _ ->
        parse_fields(rest, acc)
    end
  end

  # Block without colon: `section { ... }` or `value { ... }`
  defp parse_fields([{:ident, name}, {:lbrace} | rest], acc) do
    {block_fields, rest2} = parse_fields(rest)
    parse_fields(rest2, [{name, {:block, block_fields}} | acc])
  end

  # Handle negative number values: ident: { double_value: -0.0 }
  defp parse_fields([{:ident, _name} | _rest] = tokens, acc) do
    # Skip malformed tokens
    parse_fields(tl(tokens), acc)
  end

  defp parse_fields([_ | rest], acc), do: parse_fields(rest, acc)

  # Collect adjacent string tokens for textproto string concatenation
  defp collect_adjacent_strings([{:string, s} | rest]) do
    {more, final_rest} = collect_adjacent_strings(rest)
    {[s | more], final_rest}
  end

  defp collect_adjacent_strings(rest), do: {[], rest}

  defp get_string(fields, name) do
    case List.keyfind(fields, name, 0) do
      {_, {:scalar, val}} when is_binary(val) -> val
      _ -> nil
    end
  end

  defp get_number(fields, name) do
    case List.keyfind(fields, name, 0) do
      {_, {:scalar, val}} when is_number(val) -> val
      _ -> nil
    end
  end

  defp get_double(fields, name) do
    case List.keyfind(fields, name, 0) do
      {_, {:scalar, val}} when is_number(val) -> val * 1.0
      {_, {:scalar, :infinity}} -> :infinity
      {_, {:scalar, :neg_infinity}} -> :neg_infinity
      _ -> nil
    end
  end

  defp get_bool(fields, name) do
    case List.keyfind(fields, name, 0) do
      {_, {:scalar, val}} when is_boolean(val) -> val
      _ -> false
    end
  end

  defp get_block(fields, name) do
    case List.keyfind(fields, name, 0) do
      {_, {:block, block_fields}} -> block_fields
      _ -> nil
    end
  end

  defp get_all(fields, name) do
    fields
    |> Enum.filter(fn {n, _} -> n == name end)
    |> Enum.map(fn
      {_, {:block, block_fields}} -> block_fields
      _ -> []
    end)
  end

  defp has_field?(fields, name) do
    Enum.any?(fields, fn {n, _} -> n == name end)
  end

  defp has_scalar?(fields, name) do
    case List.keyfind(fields, name, 0) do
      {_, {:scalar, _}} -> true
      _ -> false
    end
  end

  defp get_scalar(fields, name) do
    case List.keyfind(fields, name, 0) do
      {_, {:scalar, val}} -> val
      _ -> nil
    end
  end
end
