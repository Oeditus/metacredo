defmodule MetaCredo.SourceFileTest do
  use ExUnit.Case, async: true

  alias MetaCredo.SourceFile
  alias MetaCredo.Sources

  describe "SourceFile.parse/3" do
    test "parses valid UTF-8 source code" do
      source = "defmodule Test do\n  def hello, do: :world\nend"
      assert {:ok, %SourceFile{} = sf} = SourceFile.parse(source, "test.ex", :elixir)
      assert sf.filename == "test.ex"
      assert sf.language == :elixir
      assert sf.status == :valid
    end

    test "handles Non-UTF-8 (Latin-1) encoded source code without crashing" do
      # <<241>> is byte 'ñ' in Latin-1 / ISO-8859-1 encoding
      non_utf8_source = "# Comentario con " <> <<241>> <> "\ndefmodule Latin1Test do\n  def test, do: :ok\nend"

      # Converts Latin-1 ñ (241) to UTF-8 ñ and parses successfully without UnicodeConversionError
      assert {:ok, %SourceFile{} = sf} = SourceFile.parse(non_utf8_source, "latin1.ex", :elixir)
      assert String.valid?(sf.source)
    end

    test "handles completely corrupted invalid binary gracefully" do
      binary = <<255, 254, 253, 0, 1, 2, 3>>
      result = SourceFile.parse(binary, "corrupt.ex", :elixir)

      case result do
        {:ok, %SourceFile{} = sf} ->
          assert String.valid?(sf.source)

        {:error, {:parse_failed, "corrupt.ex", _reason}} ->
          assert true
      end
    end
  end

  describe "Sources.find/1" do
    test "safely parses files with non-UTF-8 encoding without crashing task stream" do
      tmp_dir = System.tmp_dir!()
      file_path = Path.join(tmp_dir, "non_utf8_test_file_#{System.unique_integer([:positive])}.ex")
      # Write raw Latin-1 bytes to file
      File.write!(file_path, "# " <> <<241>> <> "\ndefmodule NonUtf8Test do\nend")

      on_exit(fn -> File.rm(file_path) end)

      source_files = Sources.find([file_path])
      assert is_list(source_files)
      assert length(source_files) == 1
    end
  end
end
