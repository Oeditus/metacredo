defmodule MetaCredo.BaselineTest do
  use ExUnit.Case, async: true

  alias MetaCredo.{Baseline, Issue}

  defp issue(attrs) do
    struct(
      %Issue{
        check: MetaCredo.Check.Warning.UnmanagedTask,
        category: :warning,
        message: "m"
      },
      attrs
    )
  end

  describe "encode/1" do
    test "produces versioned JSON with the issue identity" do
      encoded = Baseline.encode([issue(filename: "lib/a.ex", line_no: 3, message: "boom")])
      decoded = :json.decode(encoded)

      assert decoded["version"] == 1

      assert [%{"filename" => "lib/a.ex", "line_no" => 3, "message" => "boom"}] =
               decoded["issues"]
    end

    test "is deterministic regardless of input order" do
      a = issue(filename: "lib/a.ex", line_no: 1, message: "a")
      b = issue(filename: "lib/b.ex", line_no: 2, message: "b")

      assert Baseline.encode([a, b]) == Baseline.encode([b, a])
    end

    test "deduplicates identical issues" do
      i = issue(filename: "lib/a.ex", line_no: 1, message: "a")
      assert [_single] = :json.decode(Baseline.encode([i, i]))["issues"]
    end
  end

  describe "write/2 and read/1" do
    @tag :tmp_dir
    test "round-trips through a file", %{tmp_dir: dir} do
      path = Path.join(dir, "base.json")
      original = issue(filename: "lib/a.ex", line_no: 7, message: "boom")

      assert :ok = Baseline.write(path, [original])
      assert {:ok, keys} = Baseline.read(path)
      assert MapSet.member?(keys, Baseline.key(original))
    end

    @tag :tmp_dir
    test "creates parent directories", %{tmp_dir: dir} do
      path = Path.join([dir, "nested", "deep", "base.json"])
      assert :ok = Baseline.write(path, [])
      assert File.exists?(path)
    end

    test "reports an error for a missing file" do
      assert {:error, _} = Baseline.read("/nonexistent/base.json")
    end

    @tag :tmp_dir
    test "reports an error for malformed JSON", %{tmp_dir: dir} do
      path = Path.join(dir, "bad.json")
      File.write!(path, "not json")
      assert {:error, :invalid_baseline} = Baseline.read(path)
    end
  end

  describe "filter/2" do
    @tag :tmp_dir
    test "removes issues present in the baseline", %{tmp_dir: dir} do
      path = Path.join(dir, "base.json")
      known = issue(filename: "lib/a.ex", line_no: 1, message: "old")
      fresh = issue(filename: "lib/a.ex", line_no: 2, message: "new")

      assert :ok = Baseline.write(path, [known])
      assert Baseline.filter([known, fresh], path) == [fresh]
    end

    @tag :tmp_dir
    test "treats a missing baseline as empty rather than hiding findings", %{tmp_dir: dir} do
      issues = [issue(filename: "lib/a.ex", line_no: 1, message: "x")]
      assert Baseline.filter(issues, Path.join(dir, "absent.json")) == issues
    end

    @tag :tmp_dir
    test "does not match on line number alone", %{tmp_dir: dir} do
      path = Path.join(dir, "base.json")
      moved = issue(filename: "lib/a.ex", line_no: 99, message: "same")

      assert :ok =
               Baseline.write(path, [issue(filename: "lib/a.ex", line_no: 1, message: "same")])

      assert Baseline.filter([moved], path) == [moved]
    end
  end
end
