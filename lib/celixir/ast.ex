defmodule Celixir.AST do
  @moduledoc """
  AST node definitions for the Common Expression Language.
  """

  # Literals
  defmodule IntLit do
    @moduledoc false
    defstruct [:value]
    @type t :: %__MODULE__{value: integer()}
  end

  defmodule UintLit do
    @moduledoc false
    defstruct [:value]
    @type t :: %__MODULE__{value: non_neg_integer()}
  end

  defmodule FloatLit do
    @moduledoc false
    defstruct [:value]
    @type t :: %__MODULE__{value: float()}
  end

  defmodule StringLit do
    @moduledoc false
    defstruct [:value]
    @type t :: %__MODULE__{value: String.t()}
  end

  defmodule BytesLit do
    @moduledoc false
    defstruct [:value]
    @type t :: %__MODULE__{value: binary()}
  end

  defmodule BoolLit do
    @moduledoc false
    defstruct [:value]
    @type t :: %__MODULE__{value: boolean()}
  end

  defmodule NullLit do
    @moduledoc false
    defstruct []
    @type t :: %__MODULE__{}
  end

  # Identifier reference
  defmodule Ident do
    @moduledoc false
    defstruct [:name]
    @type t :: %__MODULE__{name: String.t()}
  end

  # Field selection: expr.field
  defmodule Select do
    @moduledoc false
    defstruct [:operand, :field, test_only: false]
    @type t :: %__MODULE__{operand: Celixir.AST.expr(), field: String.t(), test_only: boolean()}
  end

  # Optional field selection: expr.?field
  defmodule OptSelect do
    @moduledoc false
    defstruct [:operand, :field]
    @type t :: %__MODULE__{operand: Celixir.AST.expr(), field: String.t()}
  end

  # Index: expr[index]
  defmodule Index do
    @moduledoc false
    defstruct [:operand, :index]
    @type t :: %__MODULE__{operand: Celixir.AST.expr(), index: Celixir.AST.expr()}
  end

  # Optional index: expr[?index]
  defmodule OptIndex do
    @moduledoc false
    defstruct [:operand, :index]
    @type t :: %__MODULE__{operand: Celixir.AST.expr(), index: Celixir.AST.expr()}
  end

  # Function/method call
  defmodule Call do
    @moduledoc false
    defstruct [:function, :target, args: []]

    @type t :: %__MODULE__{
            function: String.t(),
            target: Celixir.AST.expr() | nil,
            args: [Celixir.AST.expr()]
          }
  end

  # Unary operator: !, -
  defmodule UnaryOp do
    @moduledoc false
    defstruct [:op, :operand]
    @type t :: %__MODULE__{op: :negate | :not, operand: Celixir.AST.expr()}
  end

  # Binary operator
  defmodule BinaryOp do
    @moduledoc false
    defstruct [:op, :left, :right]

    @type t :: %__MODULE__{
            op:
              :add
              | :sub
              | :mul
              | :div
              | :mod
              | :eq
              | :neq
              | :lt
              | :lte
              | :gt
              | :gte
              | :and
              | :or
              | :in,
            left: Celixir.AST.expr(),
            right: Celixir.AST.expr()
          }
  end

  # Ternary: condition ? true_expr : false_expr
  defmodule Ternary do
    @moduledoc false
    defstruct [:condition, :true_expr, :false_expr]

    @type t :: %__MODULE__{
            condition: Celixir.AST.expr(),
            true_expr: Celixir.AST.expr(),
            false_expr: Celixir.AST.expr()
          }
  end

  # List construction: [a, b, c]
  defmodule CreateList do
    @moduledoc false
    defstruct elements: []
    @type t :: %__MODULE__{elements: [Celixir.AST.expr()]}
  end

  # Map construction: {k1: v1, k2: v2}
  defmodule CreateMap do
    @moduledoc false
    defstruct entries: []
    @type t :: %__MODULE__{entries: [{Celixir.AST.expr(), Celixir.AST.expr()}]}
  end

  # Struct/message construction: TypeName{field1: expr1, field2: expr2}
  defmodule CreateStruct do
    @moduledoc false
    defstruct [:type_name, entries: []]

    @type t :: %__MODULE__{
            type_name: String.t(),
            entries: [{String.t(), Celixir.AST.expr()}]
          }
  end

  # Comprehension (used by macros: all, exists, exists_one, filter, map, transformList, transformMap)
  defmodule Comprehension do
    @moduledoc false
    defstruct [
      :iter_var,
      :iter_var2,
      :iter_range,
      :acc_var,
      :acc_init,
      :loop_condition,
      :loop_step,
      :result,
      kind: :standard
    ]

    @type t :: %__MODULE__{
            iter_var: String.t(),
            iter_var2: String.t() | nil,
            iter_range: Celixir.AST.expr(),
            acc_var: String.t(),
            acc_init: Celixir.AST.expr(),
            loop_condition: Celixir.AST.expr(),
            loop_step: Celixir.AST.expr(),
            result: Celixir.AST.expr(),
            kind: :standard | {:transform_map, Celixir.AST.expr(), Celixir.AST.expr() | nil}
          }
  end

  # Optional lambda: optFlatMap(var, expr) / optMap(var, expr)
  defmodule OptLambda do
    @moduledoc false
    defstruct [:kind, :target, :var, :expr]

    @type t :: %__MODULE__{
            kind: :flat_map | :map,
            target: Celixir.AST.expr(),
            var: String.t(),
            expr: Celixir.AST.expr()
          }
  end

  @type expr ::
          IntLit.t()
          | UintLit.t()
          | FloatLit.t()
          | StringLit.t()
          | BytesLit.t()
          | BoolLit.t()
          | NullLit.t()
          | Ident.t()
          | Select.t()
          | OptSelect.t()
          | Index.t()
          | OptIndex.t()
          | Call.t()
          | UnaryOp.t()
          | BinaryOp.t()
          | Ternary.t()
          | CreateList.t()
          | CreateMap.t()
          | CreateStruct.t()
          | Comprehension.t()
          | OptLambda.t()
end
