defmodule Cel.Expr.Conformance.Proto2.GlobalEnum do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "cel.expr.conformance.proto2.GlobalEnum",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:GOO, 0)
  field(:GAR, 1)
  field(:GAZ, 2)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.NestedEnum do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.NestedEnum",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:FOO, 0)
  field(:BAR, 1)
  field(:BAZ, 2)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.NestedMessage do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.NestedMessage",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:bb, 1, optional: true, type: :int32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64NestedTypeEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64NestedTypeEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Cel.Expr.Conformance.Proto2.NestedTestAllTypes)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolBoolEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolBoolEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: :bool)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolStringEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolStringEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: :string)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolBytesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolBytesEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: :bytes)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolInt32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolInt32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: :int32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolInt64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolInt64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: :int64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolUint32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolUint32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: :uint32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolUint64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolUint64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: :uint64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolFloatEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolFloatEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: :float)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolDoubleEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolDoubleEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: :double)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolEnumEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolEnumEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)

  field(:value, 2,
    optional: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedEnum,
    enum: true
  )
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolMessageEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolMessageEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedMessage)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolDurationEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolDurationEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.Duration)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolTimestampEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolTimestampEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.Timestamp)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolNullValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolNullValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.NullValue, enum: true)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolAnyEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolAnyEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.Any)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolStructEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolStructEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.Struct)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolListValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolListValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.ListValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolInt64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolInt64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.Int64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolInt32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolInt32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.Int32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolDoubleWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolDoubleWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.DoubleValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolFloatWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolFloatWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.FloatValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolUint64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolUint64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolUint32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolUint32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolStringWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolStringWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.StringValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolBoolWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolBoolWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.BoolValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolBytesWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapBoolBytesWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :bool)
  field(:value, 2, optional: true, type: Google.Protobuf.BytesValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32BoolEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32BoolEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: :bool)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32StringEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32StringEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: :string)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32BytesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32BytesEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: :bytes)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Int32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32Int32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: :int32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Int64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32Int64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: :int64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Uint32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32Uint32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: :uint32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Uint64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32Uint64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: :uint64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32FloatEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32FloatEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: :float)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32DoubleEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32DoubleEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: :double)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32EnumEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32EnumEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)

  field(:value, 2,
    optional: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedEnum,
    enum: true
  )
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32MessageEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32MessageEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedMessage)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32DurationEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32DurationEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.Duration)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32TimestampEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32TimestampEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.Timestamp)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32NullValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32NullValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.NullValue, enum: true)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32AnyEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32AnyEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.Any)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32StructEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32StructEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.Struct)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32ValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32ValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32ListValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32ListValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.ListValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Int64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32Int64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.Int64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Int32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32Int32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.Int32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32DoubleWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32DoubleWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.DoubleValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32FloatWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32FloatWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.FloatValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Uint64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32Uint64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Uint32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32Uint32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32StringWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32StringWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.StringValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32BoolWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32BoolWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.BoolValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32BytesWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt32BytesWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int32)
  field(:value, 2, optional: true, type: Google.Protobuf.BytesValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64BoolEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64BoolEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: :bool)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64StringEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64StringEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: :string)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64BytesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64BytesEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: :bytes)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Int32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64Int32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: :int32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Int64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64Int64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: :int64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Uint32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64Uint32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: :uint32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Uint64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64Uint64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: :uint64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64FloatEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64FloatEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: :float)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64DoubleEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64DoubleEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: :double)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64EnumEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64EnumEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)

  field(:value, 2,
    optional: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedEnum,
    enum: true
  )
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64MessageEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64MessageEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedMessage)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64DurationEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64DurationEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.Duration)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64TimestampEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64TimestampEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.Timestamp)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64NullValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64NullValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.NullValue, enum: true)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64AnyEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64AnyEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.Any)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64StructEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64StructEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.Struct)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64ValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64ValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64ListValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64ListValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.ListValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Int64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64Int64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.Int64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Int32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64Int32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.Int32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64DoubleWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64DoubleWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.DoubleValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64FloatWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64FloatWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.FloatValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Uint64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64Uint64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Uint32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64Uint32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64StringWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64StringWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.StringValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64BoolWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64BoolWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.BoolValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64BytesWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapInt64BytesWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :int64)
  field(:value, 2, optional: true, type: Google.Protobuf.BytesValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32BoolEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32BoolEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: :bool)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32StringEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32StringEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: :string)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32BytesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32BytesEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: :bytes)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Int32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32Int32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: :int32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Int64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32Int64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: :int64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Uint32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32Uint32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: :uint32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Uint64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32Uint64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: :uint64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32FloatEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32FloatEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: :float)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32DoubleEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32DoubleEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: :double)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32EnumEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32EnumEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)

  field(:value, 2,
    optional: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedEnum,
    enum: true
  )
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32MessageEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32MessageEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedMessage)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32DurationEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32DurationEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.Duration)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32TimestampEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32TimestampEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.Timestamp)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32NullValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32NullValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.NullValue, enum: true)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32AnyEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32AnyEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.Any)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32StructEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32StructEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.Struct)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32ValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32ValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32ListValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32ListValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.ListValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Int64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32Int64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.Int64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Int32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32Int32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.Int32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32DoubleWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32DoubleWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.DoubleValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32FloatWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32FloatWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.FloatValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Uint64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32Uint64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Uint32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32Uint32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32StringWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32StringWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.StringValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32BoolWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32BoolWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.BoolValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32BytesWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint32BytesWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint32)
  field(:value, 2, optional: true, type: Google.Protobuf.BytesValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64BoolEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64BoolEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: :bool)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64StringEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64StringEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: :string)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64BytesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64BytesEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: :bytes)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Int32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64Int32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: :int32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Int64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64Int64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: :int64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Uint32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64Uint32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: :uint32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Uint64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64Uint64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: :uint64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64FloatEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64FloatEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: :float)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64DoubleEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64DoubleEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: :double)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64EnumEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64EnumEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)

  field(:value, 2,
    optional: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedEnum,
    enum: true
  )
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64MessageEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64MessageEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedMessage)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64DurationEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64DurationEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.Duration)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64TimestampEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64TimestampEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.Timestamp)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64NullValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64NullValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.NullValue, enum: true)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64AnyEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64AnyEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.Any)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64StructEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64StructEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.Struct)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64ValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64ValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64ListValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64ListValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.ListValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Int64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64Int64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.Int64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Int32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64Int32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.Int32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64DoubleWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64DoubleWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.DoubleValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64FloatWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64FloatWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.FloatValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Uint64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64Uint64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Uint32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64Uint32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64StringWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64StringWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.StringValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64BoolWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64BoolWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.BoolValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64BytesWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapUint64BytesWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :uint64)
  field(:value, 2, optional: true, type: Google.Protobuf.BytesValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringBoolEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringBoolEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: :bool)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringStringEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringStringEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: :string)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringBytesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringBytesEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: :bytes)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringInt32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringInt32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: :int32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringInt64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringInt64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: :int64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringUint32Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringUint32Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: :uint32)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringUint64Entry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringUint64Entry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: :uint64)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringFloatEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringFloatEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: :float)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringDoubleEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringDoubleEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: :double)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringEnumEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringEnumEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)

  field(:value, 2,
    optional: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedEnum,
    enum: true
  )
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringMessageEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringMessageEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Cel.Expr.Conformance.Proto2.TestAllTypes.NestedMessage)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringDurationEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringDurationEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.Duration)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringTimestampEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringTimestampEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.Timestamp)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringNullValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringNullValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.NullValue, enum: true)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringAnyEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringAnyEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.Any)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringStructEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringStructEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.Struct)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringListValueEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringListValueEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.ListValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringInt64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringInt64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.Int64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringInt32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringInt32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.Int32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringDoubleWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringDoubleWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.DoubleValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringFloatWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringFloatWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.FloatValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringUint64WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringUint64WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt64Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringUint32WrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringUint32WrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.UInt32Value)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringStringWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringStringWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.StringValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringBoolWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringBoolWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.BoolValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringBytesWrapperEntry do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.MapStringBytesWrapperEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:key, 1, optional: true, type: :string)
  field(:value, 2, optional: true, type: Google.Protobuf.BytesValue)
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes.NestedGroup do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes.NestedGroup",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:single_id, 404, optional: true, type: :int32, json_name: "singleId")
  field(:single_name, 405, optional: true, type: :string, json_name: "singleName")
end

defmodule Cel.Expr.Conformance.Proto2.TestAllTypes do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestAllTypes",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  alias Cel.Expr.Conformance.Proto2.TestAllTypes.NestedEnum
  alias Cel.Expr.Conformance.Proto2.TestAllTypes.NestedMessage
  alias Google.Protobuf.Any
  alias Google.Protobuf.BoolValue
  alias Google.Protobuf.BytesValue
  alias Google.Protobuf.DoubleValue
  alias Google.Protobuf.Duration
  alias Google.Protobuf.FloatValue
  alias Google.Protobuf.Int32Value
  alias Google.Protobuf.Int64Value
  alias Google.Protobuf.ListValue
  alias Google.Protobuf.NullValue
  alias Google.Protobuf.StringValue
  alias Google.Protobuf.Struct
  alias Google.Protobuf.Timestamp
  alias Google.Protobuf.UInt32Value
  alias Google.Protobuf.UInt64Value
  alias Google.Protobuf.Value

  oneof(:nested_type, 0)

  oneof(:kind, 1)

  field(:single_int32, 1, optional: true, type: :int32, json_name: "singleInt32", default: -32)
  field(:single_int64, 2, optional: true, type: :int64, json_name: "singleInt64", default: -64)
  field(:single_uint32, 3, optional: true, type: :uint32, json_name: "singleUint32", default: 32)
  field(:single_uint64, 4, optional: true, type: :uint64, json_name: "singleUint64", default: 64)
  field(:single_sint32, 5, optional: true, type: :sint32, json_name: "singleSint32")
  field(:single_sint64, 6, optional: true, type: :sint64, json_name: "singleSint64")
  field(:single_fixed32, 7, optional: true, type: :fixed32, json_name: "singleFixed32")
  field(:single_fixed64, 8, optional: true, type: :fixed64, json_name: "singleFixed64")
  field(:single_sfixed32, 9, optional: true, type: :sfixed32, json_name: "singleSfixed32")
  field(:single_sfixed64, 10, optional: true, type: :sfixed64, json_name: "singleSfixed64")
  field(:single_float, 11, optional: true, type: :float, json_name: "singleFloat", default: 3.0)
  field(:single_double, 12, optional: true, type: :double, json_name: "singleDouble", default: 6.4)
  field(:single_bool, 13, optional: true, type: :bool, json_name: "singleBool", default: true)

  field(:single_string, 14,
    optional: true,
    type: :string,
    json_name: "singleString",
    default: "empty"
  )

  field(:single_bytes, 15, optional: true, type: :bytes, json_name: "singleBytes", default: "none")
  field(:in, 18, optional: true, type: :bool)
  field(:single_any, 100, optional: true, type: Any, json_name: "singleAny")

  field(:single_duration, 101,
    optional: true,
    type: Duration,
    json_name: "singleDuration"
  )

  field(:single_timestamp, 102,
    optional: true,
    type: Timestamp,
    json_name: "singleTimestamp"
  )

  field(:single_struct, 103,
    optional: true,
    type: Struct,
    json_name: "singleStruct"
  )

  field(:single_value, 104, optional: true, type: Value, json_name: "singleValue")

  field(:single_int64_wrapper, 105,
    optional: true,
    type: Int64Value,
    json_name: "singleInt64Wrapper"
  )

  field(:single_int32_wrapper, 106,
    optional: true,
    type: Int32Value,
    json_name: "singleInt32Wrapper"
  )

  field(:single_double_wrapper, 107,
    optional: true,
    type: DoubleValue,
    json_name: "singleDoubleWrapper"
  )

  field(:single_float_wrapper, 108,
    optional: true,
    type: FloatValue,
    json_name: "singleFloatWrapper"
  )

  field(:single_uint64_wrapper, 109,
    optional: true,
    type: UInt64Value,
    json_name: "singleUint64Wrapper"
  )

  field(:single_uint32_wrapper, 110,
    optional: true,
    type: UInt32Value,
    json_name: "singleUint32Wrapper"
  )

  field(:single_string_wrapper, 111,
    optional: true,
    type: StringValue,
    json_name: "singleStringWrapper"
  )

  field(:single_bool_wrapper, 112,
    optional: true,
    type: BoolValue,
    json_name: "singleBoolWrapper"
  )

  field(:single_bytes_wrapper, 113,
    optional: true,
    type: BytesValue,
    json_name: "singleBytesWrapper"
  )

  field(:list_value, 114, optional: true, type: ListValue, json_name: "listValue")

  field(:null_value, 115,
    optional: true,
    type: NullValue,
    json_name: "nullValue",
    enum: true
  )

  field(:optional_null_value, 116,
    optional: true,
    type: NullValue,
    json_name: "optionalNullValue",
    enum: true
  )

  field(:field_mask, 117, optional: true, type: Google.Protobuf.FieldMask, json_name: "fieldMask")
  field(:empty, 118, optional: true, type: Google.Protobuf.Empty)

  field(:single_nested_message, 21,
    optional: true,
    type: NestedMessage,
    json_name: "singleNestedMessage",
    oneof: 0
  )

  field(:single_nested_enum, 22,
    optional: true,
    type: NestedEnum,
    json_name: "singleNestedEnum",
    default: :BAR,
    enum: true,
    oneof: 0
  )

  field(:standalone_message, 23,
    optional: true,
    type: NestedMessage,
    json_name: "standaloneMessage"
  )

  field(:standalone_enum, 24,
    optional: true,
    type: NestedEnum,
    json_name: "standaloneEnum",
    enum: true
  )

  field(:repeated_int32, 31, repeated: true, type: :int32, json_name: "repeatedInt32")
  field(:repeated_int64, 32, repeated: true, type: :int64, json_name: "repeatedInt64")
  field(:repeated_uint32, 33, repeated: true, type: :uint32, json_name: "repeatedUint32")
  field(:repeated_uint64, 34, repeated: true, type: :uint64, json_name: "repeatedUint64")
  field(:repeated_sint32, 35, repeated: true, type: :sint32, json_name: "repeatedSint32")
  field(:repeated_sint64, 36, repeated: true, type: :sint64, json_name: "repeatedSint64")
  field(:repeated_fixed32, 37, repeated: true, type: :fixed32, json_name: "repeatedFixed32")
  field(:repeated_fixed64, 38, repeated: true, type: :fixed64, json_name: "repeatedFixed64")
  field(:repeated_sfixed32, 39, repeated: true, type: :sfixed32, json_name: "repeatedSfixed32")
  field(:repeated_sfixed64, 40, repeated: true, type: :sfixed64, json_name: "repeatedSfixed64")
  field(:repeated_float, 41, repeated: true, type: :float, json_name: "repeatedFloat")
  field(:repeated_double, 42, repeated: true, type: :double, json_name: "repeatedDouble")
  field(:repeated_bool, 43, repeated: true, type: :bool, json_name: "repeatedBool")
  field(:repeated_string, 44, repeated: true, type: :string, json_name: "repeatedString")
  field(:repeated_bytes, 45, repeated: true, type: :bytes, json_name: "repeatedBytes")

  field(:repeated_nested_message, 51,
    repeated: true,
    type: NestedMessage,
    json_name: "repeatedNestedMessage"
  )

  field(:repeated_nested_enum, 52,
    repeated: true,
    type: NestedEnum,
    json_name: "repeatedNestedEnum",
    enum: true
  )

  field(:repeated_string_piece, 53,
    repeated: true,
    type: :string,
    json_name: "repeatedStringPiece"
  )

  field(:repeated_cord, 54, repeated: true, type: :string, json_name: "repeatedCord")

  field(:repeated_lazy_message, 55,
    repeated: true,
    type: NestedMessage,
    json_name: "repeatedLazyMessage"
  )

  field(:repeated_any, 120, repeated: true, type: Any, json_name: "repeatedAny")

  field(:repeated_duration, 121,
    repeated: true,
    type: Duration,
    json_name: "repeatedDuration"
  )

  field(:repeated_timestamp, 122,
    repeated: true,
    type: Timestamp,
    json_name: "repeatedTimestamp"
  )

  field(:repeated_struct, 123,
    repeated: true,
    type: Struct,
    json_name: "repeatedStruct"
  )

  field(:repeated_value, 124,
    repeated: true,
    type: Value,
    json_name: "repeatedValue"
  )

  field(:repeated_int64_wrapper, 125,
    repeated: true,
    type: Int64Value,
    json_name: "repeatedInt64Wrapper"
  )

  field(:repeated_int32_wrapper, 126,
    repeated: true,
    type: Int32Value,
    json_name: "repeatedInt32Wrapper"
  )

  field(:repeated_double_wrapper, 127,
    repeated: true,
    type: DoubleValue,
    json_name: "repeatedDoubleWrapper"
  )

  field(:repeated_float_wrapper, 128,
    repeated: true,
    type: FloatValue,
    json_name: "repeatedFloatWrapper"
  )

  field(:repeated_uint64_wrapper, 129,
    repeated: true,
    type: UInt64Value,
    json_name: "repeatedUint64Wrapper"
  )

  field(:repeated_uint32_wrapper, 130,
    repeated: true,
    type: UInt32Value,
    json_name: "repeatedUint32Wrapper"
  )

  field(:repeated_string_wrapper, 131,
    repeated: true,
    type: StringValue,
    json_name: "repeatedStringWrapper"
  )

  field(:repeated_bool_wrapper, 132,
    repeated: true,
    type: BoolValue,
    json_name: "repeatedBoolWrapper"
  )

  field(:repeated_bytes_wrapper, 133,
    repeated: true,
    type: BytesValue,
    json_name: "repeatedBytesWrapper"
  )

  field(:repeated_list_value, 134,
    repeated: true,
    type: ListValue,
    json_name: "repeatedListValue"
  )

  field(:repeated_null_value, 135,
    repeated: true,
    type: NullValue,
    json_name: "repeatedNullValue",
    enum: true
  )

  field(:map_int64_nested_type, 62,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64NestedTypeEntry,
    json_name: "mapInt64NestedType",
    map: true
  )

  field(:map_bool_bool, 63,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolBoolEntry,
    json_name: "mapBoolBool",
    map: true
  )

  field(:map_bool_string, 64,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolStringEntry,
    json_name: "mapBoolString",
    map: true
  )

  field(:map_bool_bytes, 65,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolBytesEntry,
    json_name: "mapBoolBytes",
    map: true
  )

  field(:map_bool_int32, 66,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolInt32Entry,
    json_name: "mapBoolInt32",
    map: true
  )

  field(:map_bool_int64, 67,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolInt64Entry,
    json_name: "mapBoolInt64",
    map: true
  )

  field(:map_bool_uint32, 68,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolUint32Entry,
    json_name: "mapBoolUint32",
    map: true
  )

  field(:map_bool_uint64, 69,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolUint64Entry,
    json_name: "mapBoolUint64",
    map: true
  )

  field(:map_bool_float, 70,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolFloatEntry,
    json_name: "mapBoolFloat",
    map: true
  )

  field(:map_bool_double, 71,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolDoubleEntry,
    json_name: "mapBoolDouble",
    map: true
  )

  field(:map_bool_enum, 72,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolEnumEntry,
    json_name: "mapBoolEnum",
    map: true
  )

  field(:map_bool_message, 73,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolMessageEntry,
    json_name: "mapBoolMessage",
    map: true
  )

  field(:map_bool_duration, 228,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolDurationEntry,
    json_name: "mapBoolDuration",
    map: true
  )

  field(:map_bool_timestamp, 229,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolTimestampEntry,
    json_name: "mapBoolTimestamp",
    map: true
  )

  field(:map_bool_null_value, 230,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolNullValueEntry,
    json_name: "mapBoolNullValue",
    map: true
  )

  field(:map_bool_any, 246,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolAnyEntry,
    json_name: "mapBoolAny",
    map: true
  )

  field(:map_bool_struct, 247,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolStructEntry,
    json_name: "mapBoolStruct",
    map: true
  )

  field(:map_bool_value, 248,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolValueEntry,
    json_name: "mapBoolValue",
    map: true
  )

  field(:map_bool_list_value, 249,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolListValueEntry,
    json_name: "mapBoolListValue",
    map: true
  )

  field(:map_bool_int64_wrapper, 250,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolInt64WrapperEntry,
    json_name: "mapBoolInt64Wrapper",
    map: true
  )

  field(:map_bool_int32_wrapper, 251,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolInt32WrapperEntry,
    json_name: "mapBoolInt32Wrapper",
    map: true
  )

  field(:map_bool_double_wrapper, 252,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolDoubleWrapperEntry,
    json_name: "mapBoolDoubleWrapper",
    map: true
  )

  field(:map_bool_float_wrapper, 253,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolFloatWrapperEntry,
    json_name: "mapBoolFloatWrapper",
    map: true
  )

  field(:map_bool_uint64_wrapper, 254,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolUint64WrapperEntry,
    json_name: "mapBoolUint64Wrapper",
    map: true
  )

  field(:map_bool_uint32_wrapper, 255,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolUint32WrapperEntry,
    json_name: "mapBoolUint32Wrapper",
    map: true
  )

  field(:map_bool_string_wrapper, 256,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolStringWrapperEntry,
    json_name: "mapBoolStringWrapper",
    map: true
  )

  field(:map_bool_bool_wrapper, 257,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolBoolWrapperEntry,
    json_name: "mapBoolBoolWrapper",
    map: true
  )

  field(:map_bool_bytes_wrapper, 258,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapBoolBytesWrapperEntry,
    json_name: "mapBoolBytesWrapper",
    map: true
  )

  field(:map_int32_bool, 74,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32BoolEntry,
    json_name: "mapInt32Bool",
    map: true
  )

  field(:map_int32_string, 75,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32StringEntry,
    json_name: "mapInt32String",
    map: true
  )

  field(:map_int32_bytes, 76,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32BytesEntry,
    json_name: "mapInt32Bytes",
    map: true
  )

  field(:map_int32_int32, 77,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Int32Entry,
    json_name: "mapInt32Int32",
    map: true
  )

  field(:map_int32_int64, 78,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Int64Entry,
    json_name: "mapInt32Int64",
    map: true
  )

  field(:map_int32_uint32, 79,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Uint32Entry,
    json_name: "mapInt32Uint32",
    map: true
  )

  field(:map_int32_uint64, 80,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Uint64Entry,
    json_name: "mapInt32Uint64",
    map: true
  )

  field(:map_int32_float, 81,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32FloatEntry,
    json_name: "mapInt32Float",
    map: true
  )

  field(:map_int32_double, 82,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32DoubleEntry,
    json_name: "mapInt32Double",
    map: true
  )

  field(:map_int32_enum, 83,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32EnumEntry,
    json_name: "mapInt32Enum",
    map: true
  )

  field(:map_int32_message, 84,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32MessageEntry,
    json_name: "mapInt32Message",
    map: true
  )

  field(:map_int32_duration, 231,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32DurationEntry,
    json_name: "mapInt32Duration",
    map: true
  )

  field(:map_int32_timestamp, 232,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32TimestampEntry,
    json_name: "mapInt32Timestamp",
    map: true
  )

  field(:map_int32_null_value, 233,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32NullValueEntry,
    json_name: "mapInt32NullValue",
    map: true
  )

  field(:map_int32_any, 259,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32AnyEntry,
    json_name: "mapInt32Any",
    map: true
  )

  field(:map_int32_struct, 260,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32StructEntry,
    json_name: "mapInt32Struct",
    map: true
  )

  field(:map_int32_value, 261,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32ValueEntry,
    json_name: "mapInt32Value",
    map: true
  )

  field(:map_int32_list_value, 262,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32ListValueEntry,
    json_name: "mapInt32ListValue",
    map: true
  )

  field(:map_int32_int64_wrapper, 263,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Int64WrapperEntry,
    json_name: "mapInt32Int64Wrapper",
    map: true
  )

  field(:map_int32_int32_wrapper, 264,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Int32WrapperEntry,
    json_name: "mapInt32Int32Wrapper",
    map: true
  )

  field(:map_int32_double_wrapper, 265,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32DoubleWrapperEntry,
    json_name: "mapInt32DoubleWrapper",
    map: true
  )

  field(:map_int32_float_wrapper, 266,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32FloatWrapperEntry,
    json_name: "mapInt32FloatWrapper",
    map: true
  )

  field(:map_int32_uint64_wrapper, 267,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Uint64WrapperEntry,
    json_name: "mapInt32Uint64Wrapper",
    map: true
  )

  field(:map_int32_uint32_wrapper, 268,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32Uint32WrapperEntry,
    json_name: "mapInt32Uint32Wrapper",
    map: true
  )

  field(:map_int32_string_wrapper, 269,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32StringWrapperEntry,
    json_name: "mapInt32StringWrapper",
    map: true
  )

  field(:map_int32_bool_wrapper, 270,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32BoolWrapperEntry,
    json_name: "mapInt32BoolWrapper",
    map: true
  )

  field(:map_int32_bytes_wrapper, 271,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt32BytesWrapperEntry,
    json_name: "mapInt32BytesWrapper",
    map: true
  )

  field(:map_int64_bool, 85,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64BoolEntry,
    json_name: "mapInt64Bool",
    map: true
  )

  field(:map_int64_string, 86,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64StringEntry,
    json_name: "mapInt64String",
    map: true
  )

  field(:map_int64_bytes, 87,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64BytesEntry,
    json_name: "mapInt64Bytes",
    map: true
  )

  field(:map_int64_int32, 88,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Int32Entry,
    json_name: "mapInt64Int32",
    map: true
  )

  field(:map_int64_int64, 89,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Int64Entry,
    json_name: "mapInt64Int64",
    map: true
  )

  field(:map_int64_uint32, 90,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Uint32Entry,
    json_name: "mapInt64Uint32",
    map: true
  )

  field(:map_int64_uint64, 91,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Uint64Entry,
    json_name: "mapInt64Uint64",
    map: true
  )

  field(:map_int64_float, 92,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64FloatEntry,
    json_name: "mapInt64Float",
    map: true
  )

  field(:map_int64_double, 93,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64DoubleEntry,
    json_name: "mapInt64Double",
    map: true
  )

  field(:map_int64_enum, 94,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64EnumEntry,
    json_name: "mapInt64Enum",
    map: true
  )

  field(:map_int64_message, 95,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64MessageEntry,
    json_name: "mapInt64Message",
    map: true
  )

  field(:map_int64_duration, 234,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64DurationEntry,
    json_name: "mapInt64Duration",
    map: true
  )

  field(:map_int64_timestamp, 235,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64TimestampEntry,
    json_name: "mapInt64Timestamp",
    map: true
  )

  field(:map_int64_null_value, 236,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64NullValueEntry,
    json_name: "mapInt64NullValue",
    map: true
  )

  field(:map_int64_any, 272,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64AnyEntry,
    json_name: "mapInt64Any",
    map: true
  )

  field(:map_int64_struct, 273,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64StructEntry,
    json_name: "mapInt64Struct",
    map: true
  )

  field(:map_int64_value, 274,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64ValueEntry,
    json_name: "mapInt64Value",
    map: true
  )

  field(:map_int64_list_value, 275,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64ListValueEntry,
    json_name: "mapInt64ListValue",
    map: true
  )

  field(:map_int64_int64_wrapper, 276,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Int64WrapperEntry,
    json_name: "mapInt64Int64Wrapper",
    map: true
  )

  field(:map_int64_int32_wrapper, 277,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Int32WrapperEntry,
    json_name: "mapInt64Int32Wrapper",
    map: true
  )

  field(:map_int64_double_wrapper, 278,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64DoubleWrapperEntry,
    json_name: "mapInt64DoubleWrapper",
    map: true
  )

  field(:map_int64_float_wrapper, 279,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64FloatWrapperEntry,
    json_name: "mapInt64FloatWrapper",
    map: true
  )

  field(:map_int64_uint64_wrapper, 280,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Uint64WrapperEntry,
    json_name: "mapInt64Uint64Wrapper",
    map: true
  )

  field(:map_int64_uint32_wrapper, 281,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64Uint32WrapperEntry,
    json_name: "mapInt64Uint32Wrapper",
    map: true
  )

  field(:map_int64_string_wrapper, 282,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64StringWrapperEntry,
    json_name: "mapInt64StringWrapper",
    map: true
  )

  field(:map_int64_bool_wrapper, 283,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64BoolWrapperEntry,
    json_name: "mapInt64BoolWrapper",
    map: true
  )

  field(:map_int64_bytes_wrapper, 284,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapInt64BytesWrapperEntry,
    json_name: "mapInt64BytesWrapper",
    map: true
  )

  field(:map_uint32_bool, 96,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32BoolEntry,
    json_name: "mapUint32Bool",
    map: true
  )

  field(:map_uint32_string, 97,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32StringEntry,
    json_name: "mapUint32String",
    map: true
  )

  field(:map_uint32_bytes, 98,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32BytesEntry,
    json_name: "mapUint32Bytes",
    map: true
  )

  field(:map_uint32_int32, 99,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Int32Entry,
    json_name: "mapUint32Int32",
    map: true
  )

  field(:map_uint32_int64, 200,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Int64Entry,
    json_name: "mapUint32Int64",
    map: true
  )

  field(:map_uint32_uint32, 201,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Uint32Entry,
    json_name: "mapUint32Uint32",
    map: true
  )

  field(:map_uint32_uint64, 202,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Uint64Entry,
    json_name: "mapUint32Uint64",
    map: true
  )

  field(:map_uint32_float, 203,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32FloatEntry,
    json_name: "mapUint32Float",
    map: true
  )

  field(:map_uint32_double, 204,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32DoubleEntry,
    json_name: "mapUint32Double",
    map: true
  )

  field(:map_uint32_enum, 205,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32EnumEntry,
    json_name: "mapUint32Enum",
    map: true
  )

  field(:map_uint32_message, 206,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32MessageEntry,
    json_name: "mapUint32Message",
    map: true
  )

  field(:map_uint32_duration, 237,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32DurationEntry,
    json_name: "mapUint32Duration",
    map: true
  )

  field(:map_uint32_timestamp, 238,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32TimestampEntry,
    json_name: "mapUint32Timestamp",
    map: true
  )

  field(:map_uint32_null_value, 239,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32NullValueEntry,
    json_name: "mapUint32NullValue",
    map: true
  )

  field(:map_uint32_any, 285,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32AnyEntry,
    json_name: "mapUint32Any",
    map: true
  )

  field(:map_uint32_struct, 286,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32StructEntry,
    json_name: "mapUint32Struct",
    map: true
  )

  field(:map_uint32_value, 287,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32ValueEntry,
    json_name: "mapUint32Value",
    map: true
  )

  field(:map_uint32_list_value, 288,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32ListValueEntry,
    json_name: "mapUint32ListValue",
    map: true
  )

  field(:map_uint32_int64_wrapper, 289,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Int64WrapperEntry,
    json_name: "mapUint32Int64Wrapper",
    map: true
  )

  field(:map_uint32_int32_wrapper, 290,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Int32WrapperEntry,
    json_name: "mapUint32Int32Wrapper",
    map: true
  )

  field(:map_uint32_double_wrapper, 291,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32DoubleWrapperEntry,
    json_name: "mapUint32DoubleWrapper",
    map: true
  )

  field(:map_uint32_float_wrapper, 292,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32FloatWrapperEntry,
    json_name: "mapUint32FloatWrapper",
    map: true
  )

  field(:map_uint32_uint64_wrapper, 293,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Uint64WrapperEntry,
    json_name: "mapUint32Uint64Wrapper",
    map: true
  )

  field(:map_uint32_uint32_wrapper, 294,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32Uint32WrapperEntry,
    json_name: "mapUint32Uint32Wrapper",
    map: true
  )

  field(:map_uint32_string_wrapper, 295,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32StringWrapperEntry,
    json_name: "mapUint32StringWrapper",
    map: true
  )

  field(:map_uint32_bool_wrapper, 296,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32BoolWrapperEntry,
    json_name: "mapUint32BoolWrapper",
    map: true
  )

  field(:map_uint32_bytes_wrapper, 297,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint32BytesWrapperEntry,
    json_name: "mapUint32BytesWrapper",
    map: true
  )

  field(:map_uint64_bool, 207,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64BoolEntry,
    json_name: "mapUint64Bool",
    map: true
  )

  field(:map_uint64_string, 208,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64StringEntry,
    json_name: "mapUint64String",
    map: true
  )

  field(:map_uint64_bytes, 209,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64BytesEntry,
    json_name: "mapUint64Bytes",
    map: true
  )

  field(:map_uint64_int32, 210,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Int32Entry,
    json_name: "mapUint64Int32",
    map: true
  )

  field(:map_uint64_int64, 211,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Int64Entry,
    json_name: "mapUint64Int64",
    map: true
  )

  field(:map_uint64_uint32, 212,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Uint32Entry,
    json_name: "mapUint64Uint32",
    map: true
  )

  field(:map_uint64_uint64, 213,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Uint64Entry,
    json_name: "mapUint64Uint64",
    map: true
  )

  field(:map_uint64_float, 214,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64FloatEntry,
    json_name: "mapUint64Float",
    map: true
  )

  field(:map_uint64_double, 215,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64DoubleEntry,
    json_name: "mapUint64Double",
    map: true
  )

  field(:map_uint64_enum, 216,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64EnumEntry,
    json_name: "mapUint64Enum",
    map: true
  )

  field(:map_uint64_message, 217,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64MessageEntry,
    json_name: "mapUint64Message",
    map: true
  )

  field(:map_uint64_duration, 240,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64DurationEntry,
    json_name: "mapUint64Duration",
    map: true
  )

  field(:map_uint64_timestamp, 241,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64TimestampEntry,
    json_name: "mapUint64Timestamp",
    map: true
  )

  field(:map_uint64_null_value, 242,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64NullValueEntry,
    json_name: "mapUint64NullValue",
    map: true
  )

  field(:map_uint64_any, 298,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64AnyEntry,
    json_name: "mapUint64Any",
    map: true
  )

  field(:map_uint64_struct, 299,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64StructEntry,
    json_name: "mapUint64Struct",
    map: true
  )

  field(:map_uint64_value, 300,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64ValueEntry,
    json_name: "mapUint64Value",
    map: true
  )

  field(:map_uint64_list_value, 301,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64ListValueEntry,
    json_name: "mapUint64ListValue",
    map: true
  )

  field(:map_uint64_int64_wrapper, 302,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Int64WrapperEntry,
    json_name: "mapUint64Int64Wrapper",
    map: true
  )

  field(:map_uint64_int32_wrapper, 303,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Int32WrapperEntry,
    json_name: "mapUint64Int32Wrapper",
    map: true
  )

  field(:map_uint64_double_wrapper, 304,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64DoubleWrapperEntry,
    json_name: "mapUint64DoubleWrapper",
    map: true
  )

  field(:map_uint64_float_wrapper, 305,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64FloatWrapperEntry,
    json_name: "mapUint64FloatWrapper",
    map: true
  )

  field(:map_uint64_uint64_wrapper, 306,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Uint64WrapperEntry,
    json_name: "mapUint64Uint64Wrapper",
    map: true
  )

  field(:map_uint64_uint32_wrapper, 307,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64Uint32WrapperEntry,
    json_name: "mapUint64Uint32Wrapper",
    map: true
  )

  field(:map_uint64_string_wrapper, 308,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64StringWrapperEntry,
    json_name: "mapUint64StringWrapper",
    map: true
  )

  field(:map_uint64_bool_wrapper, 309,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64BoolWrapperEntry,
    json_name: "mapUint64BoolWrapper",
    map: true
  )

  field(:map_uint64_bytes_wrapper, 310,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapUint64BytesWrapperEntry,
    json_name: "mapUint64BytesWrapper",
    map: true
  )

  field(:map_string_bool, 218,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringBoolEntry,
    json_name: "mapStringBool",
    map: true
  )

  field(:map_string_string, 61,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringStringEntry,
    json_name: "mapStringString",
    map: true
  )

  field(:map_string_bytes, 219,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringBytesEntry,
    json_name: "mapStringBytes",
    map: true
  )

  field(:map_string_int32, 220,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringInt32Entry,
    json_name: "mapStringInt32",
    map: true
  )

  field(:map_string_int64, 221,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringInt64Entry,
    json_name: "mapStringInt64",
    map: true
  )

  field(:map_string_uint32, 222,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringUint32Entry,
    json_name: "mapStringUint32",
    map: true
  )

  field(:map_string_uint64, 223,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringUint64Entry,
    json_name: "mapStringUint64",
    map: true
  )

  field(:map_string_float, 224,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringFloatEntry,
    json_name: "mapStringFloat",
    map: true
  )

  field(:map_string_double, 225,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringDoubleEntry,
    json_name: "mapStringDouble",
    map: true
  )

  field(:map_string_enum, 226,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringEnumEntry,
    json_name: "mapStringEnum",
    map: true
  )

  field(:map_string_message, 227,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringMessageEntry,
    json_name: "mapStringMessage",
    map: true
  )

  field(:map_string_duration, 243,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringDurationEntry,
    json_name: "mapStringDuration",
    map: true
  )

  field(:map_string_timestamp, 244,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringTimestampEntry,
    json_name: "mapStringTimestamp",
    map: true
  )

  field(:map_string_null_value, 245,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringNullValueEntry,
    json_name: "mapStringNullValue",
    map: true
  )

  field(:map_string_any, 311,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringAnyEntry,
    json_name: "mapStringAny",
    map: true
  )

  field(:map_string_struct, 312,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringStructEntry,
    json_name: "mapStringStruct",
    map: true
  )

  field(:map_string_value, 313,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringValueEntry,
    json_name: "mapStringValue",
    map: true
  )

  field(:map_string_list_value, 314,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringListValueEntry,
    json_name: "mapStringListValue",
    map: true
  )

  field(:map_string_int64_wrapper, 315,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringInt64WrapperEntry,
    json_name: "mapStringInt64Wrapper",
    map: true
  )

  field(:map_string_int32_wrapper, 316,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringInt32WrapperEntry,
    json_name: "mapStringInt32Wrapper",
    map: true
  )

  field(:map_string_double_wrapper, 317,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringDoubleWrapperEntry,
    json_name: "mapStringDoubleWrapper",
    map: true
  )

  field(:map_string_float_wrapper, 318,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringFloatWrapperEntry,
    json_name: "mapStringFloatWrapper",
    map: true
  )

  field(:map_string_uint64_wrapper, 319,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringUint64WrapperEntry,
    json_name: "mapStringUint64Wrapper",
    map: true
  )

  field(:map_string_uint32_wrapper, 320,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringUint32WrapperEntry,
    json_name: "mapStringUint32Wrapper",
    map: true
  )

  field(:map_string_string_wrapper, 321,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringStringWrapperEntry,
    json_name: "mapStringStringWrapper",
    map: true
  )

  field(:map_string_bool_wrapper, 322,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringBoolWrapperEntry,
    json_name: "mapStringBoolWrapper",
    map: true
  )

  field(:map_string_bytes_wrapper, 323,
    repeated: true,
    type: Cel.Expr.Conformance.Proto2.TestAllTypes.MapStringBytesWrapperEntry,
    json_name: "mapStringBytesWrapper",
    map: true
  )

  field(:oneof_type, 400,
    optional: true,
    type: Cel.Expr.Conformance.Proto2.NestedTestAllTypes,
    json_name: "oneofType",
    oneof: 1
  )

  field(:oneof_msg, 401,
    optional: true,
    type: NestedMessage,
    json_name: "oneofMsg",
    oneof: 1
  )

  field(:oneof_bool, 402, optional: true, type: :bool, json_name: "oneofBool", oneof: 1)
  field(:nestedgroup, 403, optional: true, type: :group)
  field(:as, 500, optional: true, type: :bool)
  field(:break, 501, optional: true, type: :bool)
  field(:const, 502, optional: true, type: :bool)
  field(:continue, 503, optional: true, type: :bool)
  field(:else, 504, optional: true, type: :bool)
  field(:for, 505, optional: true, type: :bool)
  field(:function, 506, optional: true, type: :bool)
  field(:if, 507, optional: true, type: :bool)
  field(:import, 508, optional: true, type: :bool)
  field(:let, 509, optional: true, type: :bool)
  field(:loop, 510, optional: true, type: :bool)
  field(:package, 511, optional: true, type: :bool)
  field(:namespace, 512, optional: true, type: :bool)
  field(:return, 513, optional: true, type: :bool)
  field(:var, 514, optional: true, type: :bool)
  field(:void, 515, optional: true, type: :bool)
  field(:while, 516, optional: true, type: :bool)

  extensions([{1000, Protobuf.Extension.max()}])
end

defmodule Cel.Expr.Conformance.Proto2.NestedTestAllTypes do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.NestedTestAllTypes",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:child, 1, optional: true, type: Cel.Expr.Conformance.Proto2.NestedTestAllTypes)
  field(:payload, 2, optional: true, type: Cel.Expr.Conformance.Proto2.TestAllTypes)
end

defmodule Cel.Expr.Conformance.Proto2.TestRequired do
  @moduledoc false

  use Protobuf,
    full_name: "cel.expr.conformance.proto2.TestRequired",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto2

  field(:required_int32, 1, required: true, type: :int32, json_name: "requiredInt32")
end
