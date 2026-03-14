defmodule Celixir.LoadFileTest do
  use ExUnit.Case

  @tmp_dir System.tmp_dir!()

  setup do
    path = Path.join(@tmp_dir, "test_#{:erlang.unique_integer([:positive])}.cel")
    on_exit(fn -> File.rm(path) end)
    {:ok, path: path}
  end

  describe "load_file/1" do
    test "loads and compiles a CEL expression from file", %{path: path} do
      File.write!(path, "x * 2 + y")
      {:ok, program} = Celixir.load_file(path)
      assert {:ok, 11} = Celixir.Program.eval(program, %{x: 5, y: 1})
    end

    test "handles trailing whitespace/newlines", %{path: path} do
      File.write!(path, "x + 1\n\n")
      {:ok, program} = Celixir.load_file(path)
      assert {:ok, 6} = Celixir.Program.eval(program, %{x: 5})
    end

    test "returns error for non-existent file" do
      assert {:error, msg} = Celixir.load_file("/tmp/nonexistent_cel_file.cel")
      assert msg =~ "failed to read"
    end

    test "returns error for invalid CEL expression", %{path: path} do
      File.write!(path, "+++invalid")
      assert {:error, _msg} = Celixir.load_file(path)
    end
  end

  describe "load_file!/1" do
    test "returns program on success", %{path: path} do
      File.write!(path, "1 + 2")
      program = Celixir.load_file!(path)
      assert {:ok, 3} = Celixir.Program.eval(program)
    end

    test "raises on file not found" do
      assert_raise Celixir.Error, fn ->
        Celixir.load_file!("/tmp/nonexistent_cel_file.cel")
      end
    end

    test "raises on invalid expression", %{path: path} do
      File.write!(path, "+++invalid")
      assert_raise Celixir.Error, fn ->
        Celixir.load_file!(path)
      end
    end
  end
end
