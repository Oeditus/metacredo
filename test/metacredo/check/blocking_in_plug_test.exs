defmodule MetaCredo.Check.Warning.BlockingInPlugTest do
  use MetaCredo.CheckCase

  alias MetaCredo.Check.Warning.BlockingInPlug

  test "documented examples work with the real adapter" do
    examples = BlockingInPlug.explanations()[:examples][:elixir]

    assert {:ok, []} = run_example(BlockingInPlug, examples[:correct], :elixir)
    assert {:ok, [issue]} = run_example(BlockingInPlug, examples[:wrong], :elixir)
    assert issue.trigger == "HTTPoison.get!"
  end

  for expression <- [
        "FeatureFlags.get_all()",
        "Settings.fetch()",
        "Payload.load()",
        "Widget.find()",
        "get_flags()",
        "read_cached_value()",
        "Map.get(conn, :flags)",
        ":ets.lookup(:flags, :all)",
        ":persistent_term.get(:flags)",
        "Cachex.get(:flags, :all)",
        "Task.async(fn -> :ok end)",
        "Finch.build(:get, \"https://example.com\")",
        "File.stream!(\"flags.txt\")",
        "MyRepo.get()",
        "MyApp.RepoCache.get()",
        "MyApp.HTTPoison.get()",
        "HTTPoison.get_cached()"
      ] do
    test "does not assume #{expression} is blocking" do
      source = """
      def call(conn, _opts) do
        #{unquote(expression)}
        conn
      end
      """

      assert {:ok, []} = run_example(BlockingInPlug, source, :elixir)
    end
  end

  for expression <- [
        "HTTPoison.get!(\"https://example.com\")",
        "Req.get!(\"https://example.com\")",
        "Tesla.post(client, \"/flags\", %{})",
        "Finch.request(request, MyFinch)",
        ":httpc.request(~c\"https://example.com\")",
        "Repo.all(query)",
        "MyApp.Repo.get!(User, 1)",
        "MyApp.Repo.query!(\"SELECT 1\")",
        "Ecto.Adapters.SQL.query!(Repo, \"SELECT 1\")",
        "File.read!(\"flags.txt\")",
        "File.write!(\"flags.txt\", \"flags\")",
        ":file.read_file(~c\"flags.txt\")",
        "IO.read(:stdio, :line)",
        "Process.sleep(100)",
        ":timer.sleep(100)",
        "Task.await(task)",
        "GenServer.call(server, :flags)"
      ] do
    test "detects known blocking API #{expression}" do
      source = """
      def call(conn, _opts) do
        #{unquote(expression)}
        conn
      end
      """

      assert {:ok, [issue]} = run_example(BlockingInPlug, source, :elixir)
      assert issue.line_no == 2
    end
  end

  for domain <- [:db, :http, :file, :external_api] do
    test "detects #{domain} operation metadata on an unknown API" do
      ast =
        function_def("call", ["conn", "opts"], [
          call("Custom.execute", [], line: 3, op_kind: [domain: unquote(domain)])
        ])

      assert [issue] = run_check(BlockingInPlug, ast: ast)
      assert issue.trigger == "Custom.execute"
      assert issue.line_no == 3
    end
  end

  test "cache metadata takes precedence over the known API fallback" do
    ast =
      function_def("call", ["conn", "opts"], [
        call("FeatureFlags.get_all", [], op_kind: [domain: :cache]),
        call("Repo.get", [], op_kind: [domain: :cache])
      ])

    assert [] = run_check(BlockingInPlug, ast: ast)
  end

  test "non-I/O metadata is not treated as blocking" do
    ast =
      function_def("call", ["conn", "opts"], [
        call("Custom.read", [], op_kind: [domain: :collection]),
        call("Custom.fetch", [], op_kind: [])
      ])

    assert [] = run_check(BlockingInPlug, ast: ast)
  end

  test "field access sentinels stay exempt even with blocking metadata" do
    ast =
      function_def("call", ["conn", "opts"], [
        call("Map.fetch!", [], op_kind: [domain: :db]),
        call("Map.get", [], op_kind: [domain: :http])
      ])

    assert [] = run_check(BlockingInPlug, ast: ast)
  end

  test "known blocking APIs outside middleware are ignored" do
    source = """
    def refresh_flags do
      HTTPoison.get!("https://example.com")
    end
    """

    assert {:ok, []} = run_example(BlockingInPlug, source, :elixir)
  end

  for function <- ["init(opts)", "plug(conn, opts)"] do
    test "detects blocking calls in #{function}" do
      source = """
      def #{unquote(function)} do
        File.read!("flags.txt")
      end
      """

      assert {:ok, [_issue]} = run_example(BlockingInPlug, source, :elixir)
    end
  end
end
