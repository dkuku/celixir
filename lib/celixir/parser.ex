defmodule Celixir.Parser do
  @moduledoc """
  Recursive descent parser for CEL.
  Transforms a token list into an AST.

  Precedence (low to high):
    Conditional (?:)
    Or (||)
    And (&&)
    Relation (==, !=, <, <=, >, >=, in)
    Addition (+, -)
    Multiplication (*, /, %)
    Unary (!, -)
    Member (., [], ())
    Primary (literals, idents, parens, list, map)
  """

  alias Celixir.AST

  @type tokens :: [Celixir.Lexer.token()]

  @spec parse(tokens()) :: {:ok, AST.expr()} | {:error, String.t()}
  def parse(tokens) do
    case parse_expr(tokens) do
      {:ok, expr, [{:eof, _, _}]} -> {:ok, expr}
      {:ok, _expr, [{type, _, line} | _]} -> {:error, "line #{line}: unexpected token #{type}"}
      {:error, _} = err -> err
    end
  end

  # Expr = ConditionalOr ["?" ConditionalOr ":" Expr]
  defp parse_expr(tokens) do
    with {:ok, left, rest} <- parse_or(tokens) do
      case rest do
        [{:question, _, _} | rest2] ->
          with {:ok, true_expr, rest3} <- parse_or(rest2),
               {:ok, rest4} <- expect(:colon, rest3),
               {:ok, false_expr, rest5} <- parse_expr(rest4) do
            {:ok, %AST.Ternary{condition: left, true_expr: true_expr, false_expr: false_expr}, rest5}
          end

        _ ->
          {:ok, left, rest}
      end
    end
  end

  # ConditionalOr = ConditionalAnd {"||" ConditionalAnd}
  defp parse_or(tokens) do
    with {:ok, left, rest} <- parse_and(tokens) do
      parse_or_loop(left, rest)
    end
  end

  defp parse_or_loop(left, [{:or, _, _} | rest]) do
    with {:ok, right, rest2} <- parse_and(rest) do
      parse_or_loop(%AST.BinaryOp{op: :or, left: left, right: right}, rest2)
    end
  end

  defp parse_or_loop(left, rest), do: {:ok, left, rest}

  # ConditionalAnd = Relation {"&&" Relation}
  defp parse_and(tokens) do
    with {:ok, left, rest} <- parse_relation(tokens) do
      parse_and_loop(left, rest)
    end
  end

  defp parse_and_loop(left, [{:and, _, _} | rest]) do
    with {:ok, right, rest2} <- parse_relation(rest) do
      parse_and_loop(%AST.BinaryOp{op: :and, left: left, right: right}, rest2)
    end
  end

  defp parse_and_loop(left, rest), do: {:ok, left, rest}

  # Relation = Addition {Relop Addition}
  @rel_ops %{eq: :eq, neq: :neq, lt: :lt, lte: :lte, gt: :gt, gte: :gte, in: :in}

  defp parse_relation(tokens) do
    with {:ok, left, rest} <- parse_addition(tokens) do
      parse_relation_loop(left, rest)
    end
  end

  defp parse_relation_loop(left, [{op_token, _, _} | rest]) when is_map_key(@rel_ops, op_token) do
    op = Map.fetch!(@rel_ops, op_token)

    with {:ok, right, rest2} <- parse_addition(rest) do
      parse_relation_loop(%AST.BinaryOp{op: op, left: left, right: right}, rest2)
    end
  end

  defp parse_relation_loop(left, rest), do: {:ok, left, rest}

  # Addition = Multiplication {("+" | "-") Multiplication}
  defp parse_addition(tokens) do
    with {:ok, left, rest} <- parse_multiplication(tokens) do
      parse_addition_loop(left, rest)
    end
  end

  defp parse_addition_loop(left, [{:plus, _, _} | rest]) do
    with {:ok, right, rest2} <- parse_multiplication(rest) do
      parse_addition_loop(%AST.BinaryOp{op: :add, left: left, right: right}, rest2)
    end
  end

  defp parse_addition_loop(left, [{:minus, _, _} | rest]) do
    with {:ok, right, rest2} <- parse_multiplication(rest) do
      parse_addition_loop(%AST.BinaryOp{op: :sub, left: left, right: right}, rest2)
    end
  end

  defp parse_addition_loop(left, rest), do: {:ok, left, rest}

  # Multiplication = Unary {("*" | "/" | "%") Unary}
  defp parse_multiplication(tokens) do
    with {:ok, left, rest} <- parse_unary(tokens) do
      parse_multiplication_loop(left, rest)
    end
  end

  defp parse_multiplication_loop(left, [{:star, _, _} | rest]) do
    with {:ok, right, rest2} <- parse_unary(rest) do
      parse_multiplication_loop(%AST.BinaryOp{op: :mul, left: left, right: right}, rest2)
    end
  end

  defp parse_multiplication_loop(left, [{:slash, _, _} | rest]) do
    with {:ok, right, rest2} <- parse_unary(rest) do
      parse_multiplication_loop(%AST.BinaryOp{op: :div, left: left, right: right}, rest2)
    end
  end

  defp parse_multiplication_loop(left, [{:percent, _, _} | rest]) do
    with {:ok, right, rest2} <- parse_unary(rest) do
      parse_multiplication_loop(%AST.BinaryOp{op: :mod, left: left, right: right}, rest2)
    end
  end

  defp parse_multiplication_loop(left, rest), do: {:ok, left, rest}

  # Unary = Member | "!" Member | "-" Member
  defp parse_unary([{:not, _, _} | rest]) do
    with {:ok, operand, rest2} <- parse_unary(rest) do
      {:ok, %AST.UnaryOp{op: :not, operand: operand}, rest2}
    end
  end

  defp parse_unary([{:minus, _, _} | rest]) do
    with {:ok, operand, rest2} <- parse_unary(rest) do
      {:ok, %AST.UnaryOp{op: :negate, operand: operand}, rest2}
    end
  end

  defp parse_unary(tokens), do: parse_member(tokens)

  # Member = Primary { "." IDENT ["(" [ExprList] ")"] | "[" Expr "]" | "(" [ExprList] ")" }
  defp parse_member(tokens) do
    with {:ok, expr, rest} <- parse_primary(tokens) do
      parse_member_loop(expr, rest)
    end
  end

  defp parse_member_loop(expr, [{:dot, _, _}, {:ident, name, _} | rest]) do
    case rest do
      # Method call: expr.name(args)
      [{:lparen, _, _} | rest2] ->
        with {:ok, args, rest3} <- parse_expr_list(rest2),
             {:ok, rest4} <- expect(:rparen, rest3) do
          case maybe_expand_method_macro(name, expr, args) do
            {:macro, node} ->
              parse_member_loop(node, rest4)

            :not_macro ->
              parse_member_loop(%AST.Call{function: name, target: expr, args: args}, rest4)
          end
        end

      # Field access: expr.name
      _ ->
        parse_member_loop(%AST.Select{operand: expr, field: name}, rest)
    end
  end

  # Optional field select: expr.?field
  defp parse_member_loop(expr, [{:dot, _, _}, {:question, _, _}, {:ident, name, _} | rest]) do
    parse_member_loop(%AST.OptSelect{operand: expr, field: name}, rest)
  end

  # Optional index: expr[?index]
  defp parse_member_loop(expr, [{:lbracket, _, _}, {:question, _, _} | rest]) do
    with {:ok, index, rest2} <- parse_expr(rest),
         {:ok, rest3} <- expect(:rbracket, rest2) do
      parse_member_loop(%AST.OptIndex{operand: expr, index: index}, rest3)
    end
  end

  # Index: expr[index]
  defp parse_member_loop(expr, [{:lbracket, _, _} | rest]) do
    with {:ok, index, rest2} <- parse_expr(rest),
         {:ok, rest3} <- expect(:rbracket, rest2) do
      parse_member_loop(%AST.Index{operand: expr, index: index}, rest3)
    end
  end

  # Struct creation: TypeName{field: value, ...} or a.b.TypeName{field: value, ...}
  defp parse_member_loop(expr, [{:lbrace, _, _} | rest]) when is_struct(expr, AST.Ident) or is_struct(expr, AST.Select) do
    type_name = extract_qualified_name(expr)

    case type_name do
      {:ok, name} ->
        case rest do
          [{:rbrace, _, _} | rest2] ->
            parse_member_loop(%AST.CreateStruct{type_name: name, entries: []}, rest2)

          _ ->
            with {:ok, entries, rest2} <- parse_struct_fields(rest),
                 {:ok, rest3} <- maybe_comma(rest2),
                 {:ok, rest4} <- expect(:rbrace, rest3) do
              parse_member_loop(%AST.CreateStruct{type_name: name, entries: entries}, rest4)
            end
        end

      :error ->
        # Not a valid qualified name, don't treat as struct creation
        {:ok, expr, [{:lbrace, nil, 0} | rest]}
    end
  end

  defp parse_member_loop(expr, rest), do: {:ok, expr, rest}

  # Extract a qualified name from an Ident or chain of Select nodes
  # e.g., Select(Select(Ident("a"), "b"), "c") -> "a.b.c"
  defp extract_qualified_name(%AST.Ident{name: name}), do: {:ok, name}

  defp extract_qualified_name(%AST.Select{operand: operand, field: field, test_only: false}) do
    case extract_qualified_name(operand) do
      {:ok, prefix} -> {:ok, prefix <> "." <> field}
      :error -> :error
    end
  end

  defp extract_qualified_name(_), do: :error

  # Parse struct field initializers: [?]field1: expr1, [?]field2: expr2
  defp parse_struct_fields(tokens) do
    {optional?, tokens} = parse_optional_prefix(tokens)

    with {:ok, field_name, rest} <- expect_ident(tokens),
         {:ok, rest2} <- expect(:colon, rest),
         {:ok, value, rest3} <- parse_expr(rest2) do
      entry = if optional?, do: {:optional, field_name, value}, else: {field_name, value}
      parse_struct_fields_tail([entry], rest3)
    end
  end

  defp parse_struct_fields_tail(acc, [{:comma, _, _} | rest]) do
    case rest do
      [{:rbrace, _, _} | _] ->
        {:ok, Enum.reverse(acc), rest}

      _ ->
        {optional?, rest} = parse_optional_prefix(rest)

        with {:ok, field_name, rest2} <- expect_ident(rest),
             {:ok, rest3} <- expect(:colon, rest2),
             {:ok, value, rest4} <- parse_expr(rest3) do
          entry = if optional?, do: {:optional, field_name, value}, else: {field_name, value}
          parse_struct_fields_tail([entry | acc], rest4)
        end
    end
  end

  defp parse_struct_fields_tail(acc, rest), do: {:ok, Enum.reverse(acc), rest}

  defp expect_ident([{:ident, name, _} | rest]), do: {:ok, name, rest}

  defp expect_ident([{type, _, line} | _]), do: {:error, "line #{line}: expected identifier, got #{type}"}

  defp expect_ident([]), do: {:error, "unexpected end of input, expected identifier"}

  # Primary
  defp parse_primary([{:int, value, _} | rest]), do: {:ok, %AST.IntLit{value: value}, rest}
  defp parse_primary([{:uint, value, _} | rest]), do: {:ok, %AST.UintLit{value: value}, rest}
  defp parse_primary([{:float, value, _} | rest]), do: {:ok, %AST.FloatLit{value: value}, rest}
  defp parse_primary([{:string, value, _} | rest]), do: {:ok, %AST.StringLit{value: value}, rest}
  defp parse_primary([{:bytes, value, _} | rest]), do: {:ok, %AST.BytesLit{value: value}, rest}
  defp parse_primary([{true, _, _} | rest]), do: {:ok, %AST.BoolLit{value: true}, rest}
  defp parse_primary([{false, _, _} | rest]), do: {:ok, %AST.BoolLit{value: false}, rest}
  defp parse_primary([{:null, _, _} | rest]), do: {:ok, %AST.NullLit{}, rest}

  # Parenthesized expression
  defp parse_primary([{:lparen, _, _} | rest]) do
    with {:ok, expr, rest2} <- parse_expr(rest),
         {:ok, rest3} <- expect(:rparen, rest2) do
      {:ok, expr, rest3}
    end
  end

  # List construction: [expr, ...] with optional ? prefix for elements
  defp parse_primary([{:lbracket, _, _} | rest]) do
    case rest do
      [{:rbracket, _, _} | rest2] ->
        {:ok, %AST.CreateList{elements: []}, rest2}

      _ ->
        with {:ok, elements, rest2} <- parse_list_elements(rest),
             {:ok, rest3} <- maybe_comma(rest2),
             {:ok, rest4} <- expect(:rbracket, rest3) do
          {:ok, %AST.CreateList{elements: elements}, rest4}
        end
    end
  end

  # Map construction: {expr: expr, ...}
  defp parse_primary([{:lbrace, _, _} | rest]) do
    case rest do
      [{:rbrace, _, _} | rest2] ->
        {:ok, %AST.CreateMap{entries: []}, rest2}

      _ ->
        with {:ok, entries, rest2} <- parse_map_inits(rest),
             {:ok, rest3} <- maybe_comma(rest2),
             {:ok, rest4} <- expect(:rbrace, rest3) do
          {:ok, %AST.CreateMap{entries: entries}, rest4}
        end
    end
  end

  # Leading-dot qualified identifier: .ident.ident...
  defp parse_primary([{:dot, _, _}, {:ident, name, _} | rest]) do
    {qualified, rest2} = read_qualified_tail("." <> name, rest)

    case rest2 do
      [{:lparen, _, _} | rest3] ->
        with {:ok, args, rest4} <- parse_expr_list(rest3),
             {:ok, rest5} <- expect(:rparen, rest4) do
          maybe_expand_function_macro(qualified, args, rest5)
        end

      _ ->
        {:ok, %AST.Ident{name: qualified}, rest2}
    end
  end

  # Identifier or function call
  defp parse_primary([{:ident, name, _} | rest]) do
    case rest do
      [{:lparen, _, _} | rest2] ->
        with {:ok, args, rest3} <- parse_expr_list(rest2),
             {:ok, rest4} <- expect(:rparen, rest3) do
          maybe_expand_function_macro(name, args, rest4)
        end

      _ ->
        {:ok, %AST.Ident{name: name}, rest}
    end
  end

  defp parse_primary([{type, _, line} | _]) do
    {:error, "line #{line}: unexpected token #{type}"}
  end

  defp parse_primary([]) do
    {:error, "unexpected end of input"}
  end

  # ExprList = Expr {"," Expr}
  defp parse_expr_list([{:rparen, _, _} | _] = tokens), do: {:ok, [], tokens}
  defp parse_expr_list([{:rbracket, _, _} | _] = tokens), do: {:ok, [], tokens}

  defp parse_expr_list(tokens) do
    with {:ok, first, rest} <- parse_expr(tokens) do
      parse_expr_list_tail([first], rest)
    end
  end

  defp parse_expr_list_tail(acc, [{:comma, _, _} | rest]) do
    # Allow trailing comma before closing delimiters
    case rest do
      [{:rparen, _, _} | _] ->
        {:ok, Enum.reverse(acc), rest}

      [{:rbracket, _, _} | _] ->
        {:ok, Enum.reverse(acc), rest}

      _ ->
        with {:ok, expr, rest2} <- parse_expr(rest) do
          parse_expr_list_tail([expr | acc], rest2)
        end
    end
  end

  defp parse_expr_list_tail(acc, rest), do: {:ok, Enum.reverse(acc), rest}

  # List elements: supports ? prefix for optional inclusion
  defp parse_list_elements([{:rbracket, _, _} | _] = tokens), do: {:ok, [], tokens}

  defp parse_list_elements(tokens) do
    {optional?, tokens} = parse_optional_prefix(tokens)

    with {:ok, first, rest} <- parse_expr(tokens) do
      elem = if optional?, do: {:optional_list_elem, first}, else: first
      parse_list_elements_tail([elem], rest)
    end
  end

  defp parse_list_elements_tail(acc, [{:comma, _, _} | rest]) do
    case rest do
      [{:rbracket, _, _} | _] ->
        {:ok, Enum.reverse(acc), rest}

      _ ->
        {optional?, rest} = parse_optional_prefix(rest)

        with {:ok, expr, rest2} <- parse_expr(rest) do
          elem = if optional?, do: {:optional_list_elem, expr}, else: expr
          parse_list_elements_tail([elem | acc], rest2)
        end
    end
  end

  defp parse_list_elements_tail(acc, rest), do: {:ok, Enum.reverse(acc), rest}

  # MapInits = [?] Expr ":" Expr {"," [?] Expr ":" Expr}
  defp parse_map_inits(tokens) do
    {optional?, tokens} = parse_optional_prefix(tokens)

    with {:ok, key, rest} <- parse_expr(tokens),
         {:ok, rest2} <- expect(:colon, rest),
         {:ok, value, rest3} <- parse_expr(rest2) do
      entry = if optional?, do: {:optional, key, value}, else: {key, value}
      parse_map_inits_tail([entry], rest3)
    end
  end

  defp parse_map_inits_tail(acc, [{:comma, _, _} | rest]) do
    case rest do
      [{:rbrace, _, _} | _] ->
        {:ok, Enum.reverse(acc), rest}

      _ ->
        {optional?, rest} = parse_optional_prefix(rest)

        with {:ok, key, rest2} <- parse_expr(rest),
             {:ok, rest3} <- expect(:colon, rest2),
             {:ok, value, rest4} <- parse_expr(rest3) do
          entry = if optional?, do: {:optional, key, value}, else: {key, value}
          parse_map_inits_tail([entry | acc], rest4)
        end
    end
  end

  defp parse_map_inits_tail(acc, rest), do: {:ok, Enum.reverse(acc), rest}

  defp parse_optional_prefix([{:question, _, _} | rest]), do: {true, rest}
  defp parse_optional_prefix(tokens), do: {false, tokens}

  # --- Macro expansion ---

  # has(expr.field) -> Select with test_only: true
  defp maybe_expand_function_macro("has", [%AST.Select{} = select], rest) do
    {:ok, %{select | test_only: true}, rest}
  end

  # has(expr.?field) -> check if OptSelect yields a present optional (has value)
  defp maybe_expand_function_macro("has", [%AST.OptSelect{} = opt_select], rest) do
    {:ok, %AST.Call{function: "hasValue", target: opt_select, args: []}, rest}
  end

  defp maybe_expand_function_macro(name, args, rest) do
    {:ok, %AST.Call{function: name, target: nil, args: args}, rest}
  end

  @comprehension_macros ~w(all exists exists_one existsOne filter map transformList transformMap)

  # One-variable forms:
  #   list.all(x, pred) -> comprehension that checks all elements satisfy pred
  #   list.exists(x, pred) -> comprehension that checks any element satisfies pred
  #   list.exists_one(x, pred) / list.existsOne(x, pred) -> exactly one satisfies pred
  #   list.filter(x, pred) -> comprehension that collects elements satisfying pred
  #   list.map(x, expr) -> comprehension that transforms each element
  #   list.map(x, pred, expr) -> comprehension that transforms filtered elements
  # Two-variable forms (index/key + value):
  #   collection.all(k, v, pred)
  #   collection.exists(k, v, pred)
  #   collection.existsOne(k, v, pred) / collection.exists_one(k, v, pred)
  #   collection.filter(k, v, pred)
  #   collection.map(k, v, expr) / collection.map(k, v, pred, expr)
  #   collection.transformList(k, v, expr) / collection.transformList(k, v, pred, expr)
  #   collection.transformMap(k, v, expr) / collection.transformMap(k, v, pred, expr)
  # Convert CelIterVar to Ident with synthetic name for use in comprehension patterns
  defp normalize_iter_var(%AST.CelIterVar{depth: d, index: i}),
    do: %AST.Ident{name: "__cel_iter_#{d}_#{i}__"}

  defp normalize_iter_var(other), do: other

  defp maybe_expand_method_macro(name, target, args) when name in @comprehension_macros do
    # Normalize CelIterVar nodes to Ident nodes with synthetic names for comprehension expansion
    args = Enum.map(args, &normalize_iter_var/1)

    case expand_comprehension(name, target, args) do
      {:ok, node} -> {:macro, node}
      :error -> :not_macro
    end
  end

  # optFlatMap(var, expr) -> OptLambda(:flat_map, ...)
  defp maybe_expand_method_macro("optFlatMap", target, [%AST.Ident{name: var}, expr]) do
    {:macro, %AST.OptLambda{kind: :flat_map, target: target, var: var, expr: expr}}
  end

  # optMap(var, expr) -> OptLambda(:map, ...)
  defp maybe_expand_method_macro("optMap", target, [%AST.Ident{name: var}, expr]) do
    {:macro, %AST.OptLambda{kind: :map, target: target, var: var, expr: expr}}
  end

  # cel.bind(var, init, expr) → Comprehension that just binds var = init, then evaluates expr
  defp maybe_expand_method_macro("bind", %AST.Ident{name: "cel"}, [%AST.Ident{name: var}, init, expr]) do
    {:macro,
     %AST.Comprehension{
       iter_var: "#unused",
       iter_var2: nil,
       iter_range: %AST.CreateList{elements: []},
       acc_var: var,
       acc_init: init,
       loop_condition: %AST.BoolLit{value: false},
       loop_step: %AST.Ident{name: var},
       result: expr
     }}
  end

  # cel.block([bindings...], result) → CelBlock node
  defp maybe_expand_method_macro("block", %AST.Ident{name: "cel"}, [%AST.CreateList{elements: bindings}, result]) do
    {:macro, %AST.CelBlock{bindings: bindings, result: result}}
  end

  # cel.index(N) → CelIndex node
  defp maybe_expand_method_macro("index", %AST.Ident{name: "cel"}, [%AST.IntLit{value: n}]) do
    {:macro, %AST.CelIndex{index: n}}
  end

  # cel.iterVar(depth, index) → CelIterVar node
  defp maybe_expand_method_macro("iterVar", %AST.Ident{name: "cel"}, [%AST.IntLit{value: depth}, %AST.IntLit{value: idx}]) do
    {:macro, %AST.CelIterVar{depth: depth, index: idx}}
  end

  defp maybe_expand_method_macro(_name, _target, _args), do: :not_macro

  # ---- Two-variable forms (index/key + value) ----
  # NOTE: Two-variable forms with 3 args (Ident, Ident, expr) MUST come before
  # one-variable forms with 3 args (Ident, expr, expr) to avoid ambiguity when
  # the second arg is also an Ident.

  # all(var1, var2, predicate)
  defp expand_comprehension("all", iter_range, [%AST.Ident{name: var1}, %AST.Ident{name: var2}, predicate]) do
    {:ok,
     %AST.Comprehension{
       iter_var: var1,
       iter_var2: var2,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.BoolLit{value: true},
       loop_condition: %AST.Ident{name: "__result__"},
       loop_step: %AST.BinaryOp{
         op: :and,
         left: %AST.Ident{name: "__result__"},
         right: predicate
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  # exists(var1, var2, predicate)
  defp expand_comprehension("exists", iter_range, [%AST.Ident{name: var1}, %AST.Ident{name: var2}, predicate]) do
    {:ok,
     %AST.Comprehension{
       iter_var: var1,
       iter_var2: var2,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.BoolLit{value: false},
       loop_condition: %AST.UnaryOp{op: :not, operand: %AST.Ident{name: "__result__"}},
       loop_step: %AST.BinaryOp{
         op: :or,
         left: %AST.Ident{name: "__result__"},
         right: predicate
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  # existsOne / exists_one (var1, var2, predicate)
  defp expand_comprehension(name, iter_range, [%AST.Ident{name: var1}, %AST.Ident{name: var2}, predicate])
       when name in ["exists_one", "existsOne"] do
    {:ok,
     %AST.Comprehension{
       iter_var: var1,
       iter_var2: var2,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.IntLit{value: 0},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: %AST.Ternary{
         condition: predicate,
         true_expr: %AST.BinaryOp{
           op: :add,
           left: %AST.Ident{name: "__result__"},
           right: %AST.IntLit{value: 1}
         },
         false_expr: %AST.Ident{name: "__result__"}
       },
       result: %AST.BinaryOp{
         op: :eq,
         left: %AST.Ident{name: "__result__"},
         right: %AST.IntLit{value: 1}
       }
     }}
  end

  # filter(var1, var2, predicate)
  defp expand_comprehension("filter", iter_range, [%AST.Ident{name: var1}, %AST.Ident{name: var2}, predicate]) do
    {:ok,
     %AST.Comprehension{
       iter_var: var1,
       iter_var2: var2,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.CreateList{elements: []},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: %AST.Ternary{
         condition: predicate,
         true_expr: %AST.BinaryOp{
           op: :add,
           left: %AST.Ident{name: "__result__"},
           right: %AST.CreateList{elements: [%AST.Ident{name: var2}]}
         },
         false_expr: %AST.Ident{name: "__result__"}
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  # map(var1, var2, predicate, transform) — two-variable transform filtered elements (4 args, unambiguous)
  defp expand_comprehension("map", iter_range, [%AST.Ident{name: var1}, %AST.Ident{name: var2}, predicate, transform]) do
    {:ok,
     %AST.Comprehension{
       iter_var: var1,
       iter_var2: var2,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.CreateList{elements: []},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: %AST.Ternary{
         condition: predicate,
         true_expr: %AST.BinaryOp{
           op: :add,
           left: %AST.Ident{name: "__result__"},
           right: %AST.CreateList{elements: [transform]}
         },
         false_expr: %AST.Ident{name: "__result__"}
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  # map(var1, var2, transform) — two-variable transform each element
  # Must come before one-variable map(var, pred, transform) to match when second arg is Ident
  defp expand_comprehension("map", iter_range, [%AST.Ident{name: var1}, %AST.Ident{name: var2}, transform]) do
    {:ok,
     %AST.Comprehension{
       iter_var: var1,
       iter_var2: var2,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.CreateList{elements: []},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: %AST.BinaryOp{
         op: :add,
         left: %AST.Ident{name: "__result__"},
         right: %AST.CreateList{elements: [transform]}
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  # transformList(var1, var2, predicate, transform) — with filter (4 args, unambiguous)
  defp expand_comprehension("transformList", iter_range, [
         %AST.Ident{name: var1},
         %AST.Ident{name: var2},
         predicate,
         transform
       ]) do
    {:ok,
     %AST.Comprehension{
       iter_var: var1,
       iter_var2: var2,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.CreateList{elements: []},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: %AST.Ternary{
         condition: predicate,
         true_expr: %AST.BinaryOp{
           op: :add,
           left: %AST.Ident{name: "__result__"},
           right: %AST.CreateList{elements: [transform]}
         },
         false_expr: %AST.Ident{name: "__result__"}
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  # transformList(var1, var2, transform)
  defp expand_comprehension("transformList", iter_range, [%AST.Ident{name: var1}, %AST.Ident{name: var2}, transform]) do
    {:ok,
     %AST.Comprehension{
       iter_var: var1,
       iter_var2: var2,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.CreateList{elements: []},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: %AST.BinaryOp{
         op: :add,
         left: %AST.Ident{name: "__result__"},
         right: %AST.CreateList{elements: [transform]}
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  # transformMap(var1, var2, filter, transform) — with filter (4 args, unambiguous)
  defp expand_comprehension("transformMap", iter_range, [
         %AST.Ident{name: var1},
         %AST.Ident{name: var2},
         filter_expr,
         transform
       ]) do
    {:ok,
     %AST.Comprehension{
       iter_var: var1,
       iter_var2: var2,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.CreateMap{entries: []},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: transform,
       result: %AST.Ident{name: "__result__"},
       kind: {:transform_map, transform, filter_expr}
     }}
  end

  # transformMap(var1, var2, transform) — returns map with same keys, transformed values
  defp expand_comprehension("transformMap", iter_range, [%AST.Ident{name: var1}, %AST.Ident{name: var2}, transform]) do
    {:ok,
     %AST.Comprehension{
       iter_var: var1,
       iter_var2: var2,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.CreateMap{entries: []},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: transform,
       result: %AST.Ident{name: "__result__"},
       kind: {:transform_map, transform, nil}
     }}
  end

  # ---- One-variable forms ----

  defp expand_comprehension("all", iter_range, [%AST.Ident{name: var}, predicate]) do
    # __result__ starts true; loop_step = __result__ && predicate (error absorption via &&)
    {:ok,
     %AST.Comprehension{
       iter_var: var,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.BoolLit{value: true},
       loop_condition: %AST.Ident{name: "__result__"},
       loop_step: %AST.BinaryOp{
         op: :and,
         left: %AST.Ident{name: "__result__"},
         right: predicate
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  defp expand_comprehension("exists", iter_range, [%AST.Ident{name: var}, predicate]) do
    # __result__ starts false; loop_step = __result__ || predicate (error absorption via ||)
    {:ok,
     %AST.Comprehension{
       iter_var: var,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.BoolLit{value: false},
       loop_condition: %AST.UnaryOp{op: :not, operand: %AST.Ident{name: "__result__"}},
       loop_step: %AST.BinaryOp{
         op: :or,
         left: %AST.Ident{name: "__result__"},
         right: predicate
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  defp expand_comprehension(name, iter_range, [%AST.Ident{} = var, predicate]) when name in ["exists_one", "existsOne"] do
    # __result__ counts matches; loop always continues; result checks count == 1
    {:ok,
     %AST.Comprehension{
       iter_var: var.name,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.IntLit{value: 0},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: %AST.Ternary{
         condition: predicate,
         true_expr: %AST.BinaryOp{
           op: :add,
           left: %AST.Ident{name: "__result__"},
           right: %AST.IntLit{value: 1}
         },
         false_expr: %AST.Ident{name: "__result__"}
       },
       result: %AST.BinaryOp{
         op: :eq,
         left: %AST.Ident{name: "__result__"},
         right: %AST.IntLit{value: 1}
       }
     }}
  end

  defp expand_comprehension("filter", iter_range, [%AST.Ident{name: var}, predicate]) do
    # __result__ starts [], appends item when predicate is true
    {:ok,
     %AST.Comprehension{
       iter_var: var,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.CreateList{elements: []},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: %AST.Ternary{
         condition: predicate,
         true_expr: %AST.BinaryOp{
           op: :add,
           left: %AST.Ident{name: "__result__"},
           right: %AST.CreateList{elements: [%AST.Ident{name: var}]}
         },
         false_expr: %AST.Ident{name: "__result__"}
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  # list.map(x, expr) — transform each element
  defp expand_comprehension("map", iter_range, [%AST.Ident{name: var}, transform]) do
    {:ok,
     %AST.Comprehension{
       iter_var: var,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.CreateList{elements: []},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: %AST.BinaryOp{
         op: :add,
         left: %AST.Ident{name: "__result__"},
         right: %AST.CreateList{elements: [transform]}
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  # list.map(x, pred, expr) — transform filtered elements
  defp expand_comprehension("map", iter_range, [%AST.Ident{name: var}, predicate, transform]) do
    {:ok,
     %AST.Comprehension{
       iter_var: var,
       iter_range: iter_range,
       acc_var: "__result__",
       acc_init: %AST.CreateList{elements: []},
       loop_condition: %AST.BoolLit{value: true},
       loop_step: %AST.Ternary{
         condition: predicate,
         true_expr: %AST.BinaryOp{
           op: :add,
           left: %AST.Ident{name: "__result__"},
           right: %AST.CreateList{elements: [transform]}
         },
         false_expr: %AST.Ident{name: "__result__"}
       },
       result: %AST.Ident{name: "__result__"}
     }}
  end

  defp expand_comprehension(_, _, _), do: :error

  # Helpers
  defp expect(type, [{type, _, _} | rest]), do: {:ok, rest}

  defp expect(expected, [{actual, _, line} | _]), do: {:error, "line #{line}: expected #{expected}, got #{actual}"}

  defp expect(expected, []), do: {:error, "unexpected end of input, expected #{expected}"}

  defp maybe_comma([{:comma, _, _} | rest]), do: {:ok, rest}
  defp maybe_comma(rest), do: {:ok, rest}

  # Read remaining .ident segments for a qualified name (used for leading-dot names)
  defp read_qualified_tail(acc, [{:dot, _, _}, {:ident, name, _} | rest]) do
    read_qualified_tail(acc <> "." <> name, rest)
  end

  defp read_qualified_tail(acc, rest), do: {acc, rest}
end
