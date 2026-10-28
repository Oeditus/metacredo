defmodule MetaCredo.Check.ClassifierBoundariesTest do
  use MetaCredo.CheckCase, async: true

  alias MetaCredo.Check.Warning.{ImperativeStatusHandling, MissingThrottle, SyncOverAsync}

  describe "SyncOverAsync" do
    test "does not mistake logging, pure helpers or builders for I/O" do
      source = """
      defmodule Worker do
        def handle_info(message, state) do
          log_dllb_output(message)
          get_state(state)
          Map.put(state, :name, String.trim(message))
          Dllb.Query.update("ast_node", state)
          Ecto.Query.where(state, message)
        end
      end
      """

      assert [] = parsed_issues(SyncOverAsync, source)
    end

    test "recognizes real synchronous operations without semantic metadata" do
      for name <- ~W(File.read! Req.get! MyApp.Repo.all Process.sleep GenServer.call Task.await) do
        ast = function_def("handle_info", ["message", "state"], [call(name, [], line: 4)])
        assert [issue] = run_check(SyncOverAsync, ast: ast)
        assert issue.trigger == name
        assert issue.line_no == 4
      end
    end

    test "preserves real parsed I/O findings" do
      assert [issue] =
               parsed_issues(SyncOverAsync, """
               defmodule Worker do
                 def handle_info(path, state), do: File.read!(path)
               end
               """)

      assert issue.trigger == "File.read!"
    end

    test "uses semantic evidence for unknown operations and respects async metadata" do
      sync = call("Client.perform", [], op_kind: [domain: :external_api, async: false], line: 3)
      async = call("Client.perform", [], op_kind: [domain: :external_api, async: true], line: 4)
      ast = function_def("handle_info", ["message", "state"], [sync, async])
      assert [issue] = run_check(SyncOverAsync, ast: ast)
      assert issue.line_no == 3
    end

    test "does not report task lambdas but still reports awaiting their result" do
      task =
        call("Task.Supervisor.async_nolink", [
          var("sup"),
          {:lambda, [], [call("Req.get!", [], line: 3)]}
        ])

      ast =
        function_def("handle_call", ["request", "from", "state"], [
          task,
          call("Task.await", [var("task")], line: 5)
        ])

      assert [issue] = run_check(SyncOverAsync, ast: ast)
      assert issue.trigger == "Task.await"
    end

    test "checks eagerly evaluated task arguments outside the offloaded lambda" do
      ast =
        function_def("handle_info", ["message", "state"], [
          call("Task.Supervisor.async_nolink", [
            call("File.read!", [], line: 3),
            {:lambda, [], [call("Req.get!", [], line: 4)]}
          ])
        ])

      assert [issue] = run_check(SyncOverAsync, ast: ast)
      assert issue.trigger == "File.read!"
    end

    test "does not leak callback context into sibling helper functions" do
      ast =
        block([
          function_def("handle_info", ["message", "state"], [var("state")]),
          function_def("fetch", ["url"], [call("Req.get!", [], line: 8)])
        ])

      assert [] = run_check(SyncOverAsync, ast: ast)
    end
  end

  describe "ImperativeStatusHandling" do
    test "does not recommend FSMs based on lifecycle names or predicates" do
      names = ~W(
        do_stop_instance stop_owned_port safe_close_port do_start_instance
        stop_all_instances stop_instance per_project_enabled? start_link
        activate_loaded_project
      )

      ast = block(Enum.map(names, &function_def(&1, ["opts"], [literal_symbol(:ok)])))
      assert [] = run_check(ImperativeStatusHandling, ast: ast)
    end

    test "does not flag an OTP callback merely because it receives state" do
      assert [] =
               parsed_issues(ImperativeStatusHandling, """
               defmodule Worker do
                 def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
                 def handle_info(:stop, state), do: {:stop, :normal, state}
                 def per_project_enabled?, do: Application.get_env(:app, :enabled)
               end
               """)
    end

    test "still detects multi-state branches in real source" do
      assert [issue] =
               parsed_issues(ImperativeStatusHandling, """
               defmodule Orders do
                 def process(order) do
                   case order.status do
                     :pending -> :wait
                     :processing -> :work
                     :shipped -> :done
                   end
                 end
               end
               """)

      assert issue.message =~ "Branching on 3 status values"
    end

    test "respects the configured minimum state count" do
      ast =
        pattern_match(var("status"), [
          match_arm(literal_symbol(:pending), [literal_symbol(:wait)]),
          match_arm(literal_symbol(:done), [literal_symbol(:ok)])
        ])

      assert [] = run_check(ImperativeStatusHandling, ast: ast)
      assert [_] = run_check(ImperativeStatusHandling, ast: ast, params: [min_states: 2])
    end

    test "detects explicit status writes without relying on function names" do
      for update <- ["%{order | status: :active}", "Map.put(order, :status, :active)"] do
        assert [issue] =
                 parsed_issues(
                   ImperativeStatusHandling,
                   "defmodule Orders do\n def change(order), do: #{update}\nend"
                 )

        assert issue.trigger == "status ="
      end
    end

    test "ignores record initialization and updates to non-status fields" do
      assert [] =
               parsed_issues(ImperativeStatusHandling, """
               defmodule Orders do
                 def new, do: %{status: :pending}
                 def change(order), do: %{order | name: :new}
               end
               """)
    end

    test "preserves status assignments with custom field names" do
      ast = assign(var("phase"), literal_symbol(:active))
      assert [] = run_check(ImperativeStatusHandling, ast: ast)

      assert [_] =
               run_check(ImperativeStatusHandling,
                 ast: ast,
                 params: [status_field_names: ["phase"]]
               )
    end
  end

  describe "MissingThrottle" do
    test "does not classify internal storage APIs as request endpoints" do
      assert [] =
               parsed_issues(MissingThrottle, """
               defmodule Store do
                 def query(conn, statement), do: Dllb.query(statement, conn)
                 def batch_transaction(statements), do: Dllb.batch_transaction(statements)
                 def update_node_metadata(id, metadata) do
                   Dllb.Query.update(id, metadata)
                   query(metadata, [])
                 end
               end
               """)
    end

    test "still detects expensive controller actions with request parameters" do
      assert [issue] =
               parsed_issues(MissingThrottle, """
               defmodule SearchController do
                 use Phoenix.Controller
                 def search(conn, params), do: Search.query(params)
               end
               """)

      assert issue.trigger == "Search.query"
    end

    test "does not confuse a query builder with query execution at an endpoint" do
      ast =
        function_def(
          "update",
          ["conn", "params"],
          [
            call("Dllb.Query.update", [], line: 2),
            call("Dllb.query", [], line: 3)
          ],
          callback_for: "Phoenix.Controller"
        )

      assert [issue] = run_check(MissingThrottle, ast: ast)
      assert issue.trigger == "Dllb.query"
    end

    test "still inspects I/O passed as an argument to a pure query builder" do
      ast =
        function_def(
          "update",
          ["conn", "params"],
          [
            call("Dllb.Query.update", [call("Dllb.query", [], line: 3)])
          ],
          callback_for: "Phoenix.Controller"
        )

      assert [issue] = run_check(MissingThrottle, ast: ast)
      assert issue.trigger == "Dllb.query"
    end

    test "recognizes LiveView events and literal HTTP route boundaries" do
      for source <- [
            """
            defmodule SearchLive do
              use Phoenix.LiveView
              def handle_event("search", params, socket), do: Search.query(params)
            end
            """,
            """
            defmodule Router do
              use Plug.Router
              post "/search" do
                Search.query(conn.params)
              end
            end
            """
          ] do
        assert [issue] = parsed_issues(MissingThrottle, source)
        assert issue.trigger == "Search.query"
      end
    end

    test "module-level limiter declarations apply only to that module" do
      assert [issue] =
               parsed_issues(MissingThrottle, """
               defmodule Limited do
                 plug PlugAttack
                 def search(conn, params), do: Search.query(params)
               end
               defmodule UnlimitedController do
                 def search(conn, params), do: Search.query(params)
               end
               """)

      assert issue.line_no == 6
    end

    test "a limiter in an unrelated helper does not suppress endpoint findings" do
      assert [_] =
               parsed_issues(MissingThrottle, """
               defmodule Controller do
                 def helper, do: Hammer.check_rate("key", 1000, 1)
                 def search(conn, params), do: Search.query(params)
               end
               """)
    end

    test "a function-local limiter does not suppress a sibling endpoint" do
      assert [issue] =
               parsed_issues(MissingThrottle, """
               defmodule Controller do
                 def search(conn, params) do
                   Hammer.check_rate("key", 1000, 1)
                   Search.query(params)
                 end
                 def export(conn, params), do: Report.generate(params)
               end
               """)

      assert issue.trigger == "Report.generate"
    end

    test "ordinary request data mentioning a limiter does not suppress findings" do
      ast =
        function_def(
          "search",
          ["conn", "params"],
          [
            call("Search.query", [literal_string("hammer")])
          ],
          callback_for: "Phoenix.Controller"
        )

      assert [_] = run_check(MissingThrottle, ast: ast)
    end

    test "recognizes atom plug declarations and private helpers are not endpoints" do
      ast =
        container(:module, "Controller", [
          call("plug", [literal_symbol(:rate_limit)]),
          function_def("search", ["conn", "params"], [call("Search.query", [])])
        ])

      assert [] = run_check(MissingThrottle, ast: ast)

      helper =
        function_def("search", ["conn", "params"], [call("Search.query", [])],
          visibility: :private,
          callback_for: "Phoenix.Controller"
        )

      assert [] = run_check(MissingThrottle, ast: helper)
    end
  end

  test "request work still needs throttling when the operation is asynchronous" do
    ast =
      function_def(
        "search",
        ["conn", "params"],
        [call("Client.perform_async", [], op_kind: [domain: :external_api, async: true])],
        callback_for: "Phoenix.Controller"
      )

    assert [issue] = run_check(MissingThrottle, ast: ast)
    assert issue.trigger == "Client.perform_async"
  end

  test "controller context also identifies actions without CRUD names" do
    assert [issue] =
             parsed_issues(MissingThrottle, """
             defmodule Pages do
               use Phoenix.Controller
               def index(conn, params), do: Repo.all(params)
             end
             """)

    assert issue.trigger == "Repo.all"
  end

  defp parsed_issues(check, source) do
    assert {:ok, file} = SourceFile.parse(source, "fixture.ex", :elixir)
    check.run(file, [])
  end
end
