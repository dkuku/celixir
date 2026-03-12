defmodule Celixir.Checker do
  @moduledoc """
  Static type checker for CEL expressions.

  Validates that a parsed AST is well-typed given declared variable types.
  This is an optional step — CEL expressions can be evaluated without
  type-checking, but checking catches errors earlier.

  ## Usage

      {:ok, ast} = Celixir.parse("x + 1")
      declarations = %{"x" => :int}
      :ok = Celixir.Checker.check(ast, declarations)

      # Type error:
      declarations = %{"x" => :string}
      {:error, "no matching overload for + on string and int"} =
        Celixir.Checker.check(ast, declarations)
  """

  alias Celixir.AST

  @type cel_type ::
          :int
          | :uint
          | :double
          | :bool
          | :string
          | :bytes
          | :null_type
          | :timestamp
          | :duration
          | :dyn
          | {:list, cel_type()}
          | {:map, cel_type(), cel_type()}
          | :type
          | :optional_type
          | :error

  @spec check(AST.expr(), %{String.t() => cel_type()}) :: :ok | {:error, String.t()}
  def check(ast, declarations \\ %{}) do
    case infer(ast, stringify_keys(declarations)) do
      {:error, _} = err -> err
      _type -> :ok
    end
  end

  @spec infer(AST.expr(), map()) :: cel_type() | {:error, String.t()}
  def infer(ast, declarations \\ %{})

  def infer(%AST.IntLit{}, _), do: :int
  def infer(%AST.UintLit{}, _), do: :uint
  def infer(%AST.FloatLit{}, _), do: :double
  def infer(%AST.StringLit{}, _), do: :string
  def infer(%AST.BytesLit{}, _), do: :bytes
  def infer(%AST.BoolLit{}, _), do: :bool
  def infer(%AST.NullLit{}, _), do: :null_type

  def infer(%AST.Ident{name: name}, decls) do
    case Map.fetch(decls, name) do
      {:ok, type} -> type
      :error -> :dyn
    end
  end

  def infer(%AST.UnaryOp{op: :not, operand: operand}, decls) do
    case infer(operand, decls) do
      :bool -> :bool
      :dyn -> :bool
      t -> {:error, "no matching overload for ! on #{format_type(t)}"}
    end
  end

  def infer(%AST.UnaryOp{op: :negate, operand: operand}, decls) do
    case infer(operand, decls) do
      t when t in [:int, :double, :dyn] -> t
      t -> {:error, "no matching overload for - on #{format_type(t)}"}
    end
  end

  def infer(%AST.BinaryOp{op: op, left: left, right: right}, decls) when op in [:and, :or] do
    with {:ok, lt} <- infer_ok(left, decls),
         {:ok, rt} <- infer_ok(right, decls) do
      if lt in [:bool, :dyn] and rt in [:bool, :dyn] do
        :bool
      else
        {:error, "no matching overload for #{op_name(op)} on #{format_type(lt)} and #{format_type(rt)}"}
      end
    end
  end

  def infer(%AST.BinaryOp{op: op, left: left, right: right}, decls) when op in [:add, :sub, :mul, :div, :mod] do
    with {:ok, lt} <- infer_ok(left, decls),
         {:ok, rt} <- infer_ok(right, decls) do
      cond do
        lt == :dyn or rt == :dyn ->
          :dyn

        op == :add and lt == :string and rt == :string ->
          :string

        op == :add and match?({:list, _}, lt) and match?({:list, _}, rt) ->
          lt

        op == :add and lt == :bytes and rt == :bytes ->
          :bytes

        lt == rt and lt in [:int, :uint, :double] ->
          lt

        true ->
          {:error, "no matching overload for #{op_name(op)} on #{format_type(lt)} and #{format_type(rt)}"}
      end
    end
  end

  def infer(%AST.BinaryOp{op: op}, _decls) when op in [:eq, :neq, :lt, :lte, :gt, :gte, :in], do: :bool

  def infer(%AST.Ternary{condition: cond_expr, true_expr: t, false_expr: f}, decls) do
    with {:ok, ct} <- infer_ok(cond_expr, decls),
         {:ok, tt} <- infer_ok(t, decls),
         {:ok, ft} <- infer_ok(f, decls) do
      cond do
        ct not in [:bool, :dyn] -> {:error, "ternary condition must be bool"}
        tt == ft -> tt
        tt == :dyn -> ft
        ft == :dyn -> tt
        true -> :dyn
      end
    end
  end

  def infer(%AST.CreateList{elements: []}, _), do: {:list, :dyn}

  def infer(%AST.CreateList{elements: [h | _]}, decls) do
    {:list, infer(h, decls)}
  end

  def infer(%AST.CreateMap{entries: []}, _), do: {:map, :dyn, :dyn}

  def infer(%AST.CreateMap{entries: [{k, v} | _]}, decls) do
    {:map, infer(k, decls), infer(v, decls)}
  end

  def infer(%AST.Select{}, _), do: :dyn
  def infer(%AST.Index{}, _), do: :dyn
  def infer(%AST.Call{}, _), do: :dyn
  def infer(%AST.Comprehension{}, _), do: :dyn

  defp infer_ok(ast, decls) do
    case infer(ast, decls) do
      {:error, _} = err -> err
      type -> {:ok, type}
    end
  end

  defp op_name(:add), do: "+"
  defp op_name(:sub), do: "-"
  defp op_name(:mul), do: "*"
  defp op_name(:div), do: "/"
  defp op_name(:mod), do: "%"
  defp op_name(:and), do: "&&"
  defp op_name(:or), do: "||"

  defp format_type({:list, t}), do: "list(#{format_type(t)})"
  defp format_type({:map, k, v}), do: "map(#{format_type(k)}, #{format_type(v)})"
  defp format_type(t) when is_atom(t), do: Atom.to_string(t)
  defp format_type(t), do: inspect(t)

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
