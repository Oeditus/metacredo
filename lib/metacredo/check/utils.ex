defmodule MetaCredo.Check.Utils do
  @moduledoc """
  Shared utilities for check implementations.

  Provides function classification helpers to reduce false positives
  across security, observability, and other checks that match on
  function call names.
  """

  # Modules whose functions are standard library / language infrastructure
  # and should never be treated as user-facing I/O / security-sensitive calls
  @safe_modules ~W[
    Keyword Map MapSet Enum List Tuple String Integer Float Atom
    Access Kernel Module Code Macro IO File Path System
    Agent GenServer Supervisor Task Process Registry
    Application Logger Config Mix ExUnit
    Date Time DateTime NaiveDateTime Calendar URI
    Regex Range Stream Inspect Protocol
    Base Bitwise Math
    ETS DETS
    Elixir.Access Elixir.Kernel
  ]

  @pure_operation_modules ~W(
    Map MapSet Keyword Enum List Tuple String Integer Float Atom Kernel
    Logger Path Base Regex Date Time DateTime NaiveDateTime Calendar URI
    Ecto.Query Dllb.Query
  )

  @blocking_modules %{
    "File" => ~W(read write open close stat lstat ls mkdir mkdir_p rm rm_rf cp cp_r copy rename),
    "IO" => ~W(read binread write binwrite puts gets inspect),
    ":file" => ~W(read_file write_file open close read write list_dir),
    "System" => ~W(cmd shell),
    "Process" => ~W(sleep),
    "GenServer" => ~W(call stop),
    "Task" => ~W(await await_many yield yield_many shutdown),
    "Dllb" => ~W(query batch batch_transaction),
    "Req" => ~W(get post put patch delete head request run),
    "HTTPoison" => ~W(get post put patch delete head request),
    "HTTPotion" => ~W(get post put patch delete head request),
    "Tesla" => ~W(get post put patch delete head request),
    "Finch" => ~W(request stream),
    ":httpc" => ~W(request)
  }

  @repo_operations ~W(
    all one get get_by insert insert_all update update_all delete delete_all
    preload query transaction checkout
  )

  # Bare function names that are stdlib and should never be flagged
  @safe_bare_functions ~W[
    is_nil is_binary is_list is_map is_atom is_integer is_float
    is_boolean is_tuple is_number is_pid is_port is_reference
    is_function is_bitstring is_struct is_exception
    hd tl length elem tuple_size map_size byte_size bit_size
    div rem abs round ceil floor trunc min max
    not and or
    to_string to_charlist to_atom
    inspect raise reraise throw exit
    spawn send self node
    apply
    defmodule def defp defmacro defmacrop defguard defstruct
    defdelegate defexception defprotocol defimpl defoverridable
    use import require alias
    if unless cond case with for receive try catch after rescue
    fn quote unquote unquote_splicing
    sigil_w sigil_W
  ]

  # Statements that terminate control flow for the remainder of a block.
  # Shared by `MetaCredo.Check.Refactor.DeadCode` and
  # `MetaCredo.Analysis.DeadCode` so the two cannot drift apart.
  @terminators ~W(raise reraise throw exit return)

  # Names that appear as :variable nodes but are actually special forms
  @special_names ~W[
    __MODULE__ __ENV__ __DIR__ __CALLER__ __STACKTRACE__
    _ ... __struct__ __exception__
  ]

  # `camelCase`, as used by the JavaScript, TypeScript and Go adapters: a
  # lower-case first letter, then any mix of letters, digits, `_` and `$`.
  # A leading `_`/`$` is legal (JS/TS "private" markers, Go's blank identifier
  # and `$`-prefixed identifiers). A single lower-case word is valid camelCase.
  @camel_case ~r/^[_$]?[a-z][a-zA-Z0-9$]*$/

  # `snake_case`, optionally suffixed with `!`/`?` (the Elixir convention).
  # Leading underscores are permitted and may repeat: `_unused`, `_`, and the
  # compiler-reserved `__using__`/`__struct__` forms are all legal Elixir
  # identifiers, and rejecting them made `FunctionNames` flag every macro
  # definition in the language.
  @snake_case ~r/^_*[a-z][a-z0-9_]*[!?]?$/

  @doc """
  Safely extracts a node name from AST metadata as a string.

  Handles the case where `:name` is a list of AST tuples (e.g., quoted
  expressions in typespec files) instead of a plain string or atom.
  Returns `inspect(value)` for non-stringable values rather than crashing.
  """
  @spec safe_name(keyword(), term()) :: String.t()
  def safe_name(meta, default \\ "") when is_list(meta) do
    case Keyword.get(meta, :name, default) do
      val when is_binary(val) -> val
      val when is_atom(val) -> Atom.to_string(val)
      val when is_number(val) -> to_string(val)
      other -> inspect(other)
    end
  end

  @doc """
  Returns the 1-based source line recorded in a node's metadata, or `nil`.

  Metastatic does not attach `:line` to every node: for Elixir, only nodes
  derived from forms that carry position information (e.g. `cond`, some
  `function_def`s) get one, while plain `if`-derived `:conditional` nodes
  arrive with empty metadata. Checks that read `meta[:line]` directly
  therefore emit a proportion of issues with `line_no: nil`, which breaks
  `mix metacredo explain file:line`, the code-snippet renderer, and GitHub
  inline annotations.

  Use this helper instead of `Keyword.get(meta, :line)`, and pass the
  enclosing `:function_def` metadata as `fallback` so the issue still points
  at the right function when the node itself has no position.

  ## Examples

      iex> CheckUtils.line_of([line: 42])
      42

      iex> CheckUtils.line_of([], [line: 7])
      7

      iex> CheckUtils.line_of([])
      nil
  """
  @spec line_of(keyword(), keyword() | nil) :: pos_integer() | nil
  def line_of(meta, fallback \\ nil)

  def line_of(meta, fallback) when is_list(meta) do
    case Keyword.get(meta, :line) do
      line when is_integer(line) -> line
      _ -> line_of(fallback, nil)
    end
  end

  def line_of(_meta, _fallback), do: nil

  @doc """
  Returns true if the function name belongs to a well-known standard library
  module that should never be flagged as user-facing I/O, HTTP, auth,
  file operations, etc.

  This prevents false positives like `Keyword.get` being flagged as an
  HTTP "get" call, or `Map.fetch!` being flagged as a database "fetch".
  """
  @spec safe_stdlib_call?(String.t()) :: boolean()
  def safe_stdlib_call?(func_name) when is_binary(func_name) do
    case String.split(func_name, ".", parts: 2) do
      [module, _fun] -> module in @safe_modules
      [bare] -> bare in @safe_bare_functions
    end
  end

  def safe_stdlib_call?(_), do: false

  @doc "Splits a qualified call into its module and terminal function name."
  @spec call_parts(String.t()) :: {String.t(), String.t()}
  def call_parts(name) do
    parts = name |> String.replace_prefix("Elixir.", "") |> String.split(".")
    {parts |> Enum.drop(-1) |> Enum.join("."), List.last(parts)}
  end

  @doc "Recognizes pure operations, including known query builders, rather than query execution."
  @spec pure_operation?(String.t()) :: boolean()
  def pure_operation?(name) do
    {module, _function} = call_parts(name)
    module in @pure_operation_modules
  end

  @doc """
  Identifies synchronous I/O from semantic metadata or known module operations.

  Unknown helper names are not evidence of blocking. Pure standard operations
  and query builders remain pure even when an adapter attaches broad metadata.
  """
  @spec blocking_call?(keyword()) :: boolean()
  def blocking_call?(meta) do
    name = safe_name(meta)

    if pure_operation?(name) do
      false
    else
      case Keyword.get(meta, :op_kind) do
        kind when is_list(kind) ->
          Keyword.get(kind, :domain) in [:db, :http, :file, :external_api] and
            Keyword.get(kind, :async, false) != true

        _ ->
          known_blocking_call?(name)
      end
    end
  end

  @doc """
  Returns true if the node terminates control flow for the remainder of a block.

  `raise`/`reraise`/`throw`/`exit`/`return` are the statements after which any
  following sibling can never execute. Metastatic emits them as plain
  `:function_call` nodes rather than `:early_return`, so both shapes must be
  recognised -- this is the single source of truth shared by
  `MetaCredo.Check.Refactor.DeadCode` and `MetaCredo.Analysis.DeadCode`.

  ## Examples

      iex> CheckUtils.terminator?({:early_return, [], [{:literal, [subtype: :integer], 1}]})
      true

      iex> CheckUtils.terminator?({:function_call, [name: "raise"], []})
      true

      iex> CheckUtils.terminator?({:function_call, [name: "Logger.info"], []})
      false
  """
  @spec terminator?(Metastatic.AST.meta_ast()) :: boolean()
  def terminator?({:early_return, _meta, _children}), do: true

  def terminator?({:function_call, meta, _args}) when is_list(meta) do
    safe_name(meta) in @terminators
  end

  def terminator?(_), do: false

  @doc """
  Returns true if a variable name represents a module attribute

  @doc \"""
  Returns true if a variable name represents a module attribute
  (starts with `@`), which should be excluded from snake_case checks
  since module attribute names follow their own conventions.
  """
  @spec module_attribute?(String.t()) :: boolean()
  def module_attribute?("@" <> _), do: true
  def module_attribute?(_), do: false

  @doc """
  Returns true if a variable name is a well-known Elixir special form
  or compiler artifact that should be excluded from naming checks.
  """
  @spec special_variable?(String.t()) :: boolean()
  def special_variable?(name) when is_binary(name) do
    module_attribute?(name) or name in @special_names or module_name?(name)
  end

  def special_variable?(_), do: false

  @doc """
  Returns true if the string looks like a module name (PascalCase or
  contains dots like `Enum.map`), not a regular variable.
  """
  @spec module_name?(String.t()) :: boolean()
  def module_name?(name) when is_binary(name) do
    String.contains?(name, ".") or
      (byte_size(name) > 0 and String.first(name) == String.upcase(String.first(name)) and
         String.first(name) != "_")
  end

  def module_name?(_), do: false

  @doc """
  Returns true when a `:container` node is a Rust `mod` item.

  Rust declares modules in two forms, and the MetaAST only distinguishes them
  by their body:

      mod config;              # declaration -- body is `[]`
      mod inline { ... }       # definition -- body holds the items

  A *declaration* is not a module definition: it names another file (or an
  inline block) and has no body, no documentation, and a name that Rust
  conventionally writes in `snake_case`. Applying Elixir's module rules to it
  produces pure noise -- `ModuleDoc` reports "no documentation" for something
  that cannot carry documentation, and `ModuleNames` reports "not in
  PascalCase" for a name that is correctly cased for Rust.

  The `rust_kind: "Module"` key is set by `Metastatic.Adapters.Rust.ToMeta`
  and by no other adapter, so it identifies Rust `mod` items precisely. It is
  deliberately *not* inferred from an empty body: empty-bodied containers also
  occur in Elixir (`defmodule Foo do end`) and Haskell, where the module rules
  do apply.

  ## Examples

      iex> CheckUtils.rust_mod?(container_type: :module, rust_kind: "Module")
      true

      iex> CheckUtils.rust_mod?(container_type: :module, rust_kind: "Struct")
      false

      iex> CheckUtils.rust_mod?(container_type: :module)
      false
  """
  @spec rust_mod?(keyword()) :: boolean()
  def rust_mod?(meta) when is_list(meta) do
    Keyword.get(meta, :rust_kind) == "Module" and Keyword.get(meta, :language) == :rust
  end

  def rust_mod?(_), do: false

  @doc """
  Returns true when a `:container` node is a Go `package` clause.

  A Go file opens with `package main`, which every adapter reports as a
  `:container` of type `:module` -- the same shape Elixir uses for
  `defmodule`. Applying Elixir's module rules to it is meaningless: a Go
  package name is conventionally lower-case (`package main`, `package http`),
  so `ModuleNames` reported "not in PascalCase" for *every* Go file, and
  `ModuleDoc` demanded a doc comment that Go convention puts on the package
  clause only for non-main packages.

  The `go_kind: "File"` key is set by `Metastatic.Adapters.Go.ToMeta` and by
  no other adapter, so it identifies a Go file container precisely.

  ## Examples

      iex> CheckUtils.go_package?(go_kind: "File", language: :go)
      true

      iex> CheckUtils.go_package?(go_kind: "FuncDecl", language: :go)
      false

      iex> CheckUtils.go_package?(container_type: :module)
      false
  """
  @spec go_package?(keyword()) :: boolean()
  def go_package?(meta) when is_list(meta) do
    Keyword.get(meta, :go_kind) == "File" and Keyword.get(meta, :language) == :go
  end

  def go_package?(_), do: false

  @doc """
  Returns true when a `:container` node carries no name to check.

  Covers both `rust_mod?/1` (a Rust `mod x;` declaration) and
  `go_package?/1` (a Go file's `package` clause): in both cases the adapter's
  `:module` container is a structural artifact rather than a module definition
  that naming or documentation rules can sensibly apply to.

  ## Examples

      iex> CheckUtils.nameless_container?(go_kind: "File", language: :go)
      true

      iex> CheckUtils.nameless_container?(rust_kind: "Module", language: :rust)
      true

      iex> CheckUtils.nameless_container?(container_type: :module, name: "MyApp.User")
      false
  """
  @spec nameless_container?(keyword()) :: boolean()
  def nameless_container?(meta) when is_list(meta), do: rust_mod?(meta) or go_package?(meta)
  def nameless_container?(_), do: false

  @doc """
  Returns the naming convention used for identifiers in `language`.

  MetaCredo's naming checks (`Readability.FunctionNames`,
  `Readability.VariableNames`) originally hardcoded Elixir's `snake_case` and
  ran it on every language. That is wrong for the C-family adapters: `camelCase`
  is the convention in JavaScript, TypeScript and Go, so `processUserData` was
  reported as "not in snake_case" in every JS/TS/Go file -- a false positive on
  *correctly written* code.

  Languages not listed here keep `:snake_case`, which is the convention for
  Elixir, Erlang, Python, Ruby and Rust.

  ## Examples

      iex> CheckUtils.naming_convention(:javascript)
      :camel_case

      iex> CheckUtils.naming_convention(:go)
      :camel_case

      iex> CheckUtils.naming_convention(:elixir)
      :snake_case

      iex> CheckUtils.naming_convention(:haskell)
      :snake_case
  """
  @spec naming_convention(atom()) :: :camel_case | :snake_case
  def naming_convention(language) when language in [:javascript, :typescript, :go],
    do: :camel_case

  def naming_convention(_language), do: :snake_case

  @doc """
  Returns true when `name` follows `camelCase`.

  Accepts a leading underscore (the conventional "private" marker in JS/TS and
  the blank identifier in Go), a leading `$` (legal in JS/TS identifiers), and
  the `$`/`_` characters inside the name. A single lower-case word is valid
  camelCase.

  ## Examples

      iex> CheckUtils.camel_case?("processUserData")
      true

      iex> CheckUtils.camel_case?("process")
      true

      iex> CheckUtils.camel_case?("_unused")
      true

      iex> CheckUtils.camel_case?("process_user_data")
      false

      iex> CheckUtils.camel_case?("ProcessUserData")
      false
  """
  @spec camel_case?(String.t()) :: boolean()
  def camel_case?(name) when is_binary(name) do
    Regex.match?(@camel_case, name)
  end

  def camel_case?(_), do: false

  @doc """
  Returns true when `name` follows `snake_case`, optionally suffixed with `!`
  or `?` (the Elixir predicate/bang convention).

  ## Examples

      iex> CheckUtils.snake_case?("process_user_data")
      true

      iex> CheckUtils.snake_case?("valid?")
      true

      iex> CheckUtils.snake_case?("processUserData")
      false
  """
  @spec snake_case?(String.t()) :: boolean()
  def snake_case?(name) when is_binary(name) do
    Regex.match?(@snake_case, name)
  end

  def snake_case?(_), do: false

  @doc """
  Returns true when `name` follows the naming convention of `language`.

  This is the single entry point the naming checks use, so a new language only
  has to be classified in `naming_convention/1` rather than in every check.

  ## Examples

      iex> CheckUtils.conventional_name?("processUserData", :go)
      true

      iex> CheckUtils.conventional_name?("process_user_data", :go)
      false

      iex> CheckUtils.conventional_name?("process_user_data", :elixir)
      true
  """
  @spec conventional_name?(String.t(), atom()) :: boolean()
  def conventional_name?(name, language) when is_binary(name) do
    case naming_convention(language) do
      :camel_case -> camel_case?(name)
      :snake_case -> snake_case?(name)
    end
  end

  def conventional_name?(_name, _language), do: false

  @doc """
  Returns the human-readable name of the convention used by `language`.

  Used in issue messages so a finding says "not in camelCase" for Go and
  "not in snake_case" for Elixir, instead of always claiming snake_case.

  ## Examples

      iex> CheckUtils.convention_label(:go)
      "camelCase"

      iex> CheckUtils.convention_label(:elixir)
      "snake_case"
  """
  @spec convention_label(atom()) :: String.t()
  def convention_label(language) do
    case naming_convention(language) do
      :camel_case -> "camelCase"
      :snake_case -> "snake_case"
    end
  end

  @doc """
  Returns the argument nodes of a `:function_call`, with the callee removed.

  Adapters disagree about where a call's callee lives. Elixir, Erlang, Python,
  Ruby, Rust and Go record it only in the `:name` metadata, so the children are
  exactly the arguments. The JavaScript and TypeScript adapters additionally
  emit the callee as the *first child*:

      axios.get(targetUrl)   ->  [callee, targetUrl]
      foo()                  ->  [callee]

  A check that inspects "the first argument" therefore examined the callee on
  JS/TS and never the argument, which silently disabled every argument-based
  heuristic there (`SSRFVulnerability`, `SensitiveDataExposure`,
  `UnsafeExec`). Route every argument lookup through this helper so the same
  check works on both shapes.

  ## Examples

      iex> CheckUtils.call_arguments([name: "foo"], [{:variable, [], "x"}])
      [{:variable, [], "x"}]

      iex> callee = {:function_call, [name: "member_access"], []}
      iex> CheckUtils.call_arguments([name: "axios.get"], [callee, {:variable, [], "url"}])
      [{:variable, [], "url"}]

      iex> CheckUtils.call_arguments([name: "foo"], [])
      []
  """
  @spec call_arguments(keyword(), [Metastatic.AST.meta_ast()]) :: [Metastatic.AST.meta_ast()]
  def call_arguments(meta, [callee | rest]) when is_list(meta) do
    if callee_node?(meta, callee), do: rest, else: [callee | rest]
  end

  def call_arguments(_meta, args), do: args

  @doc """
  Returns true when `node` is the callee child of the call described by `meta`.

  A leading child is the callee when it names the same function as the node's
  `:name` metadata: either a plain variable (`fetch(...)`) or the
  `member_access` pseudo-call the JavaScript/TypeScript adapters wrap the
  callee in (`axios.get(...)`).

  ## Examples

      iex> CheckUtils.callee_node?([name: "fetch"], {:variable, [], "fetch"})
      true

      iex> CheckUtils.callee_node?([name: "fetch"], {:variable, [], "url"})
      false

      iex> CheckUtils.callee_node?([name: "axios.get"], {:function_call, [name: "member_access"], []})
      true

      iex> CheckUtils.callee_node?([name: "member_access"], {:function_call, [name: "member_access"], []})
      false
  """
  @spec callee_node?(keyword(), Metastatic.AST.meta_ast()) :: boolean()
  def callee_node?(meta, {:variable, _var_meta, name}) when is_list(meta) and is_binary(name),
    do: Keyword.get(meta, :name) == name

  def callee_node?(meta, {:function_call, call_meta, _children}) when is_list(meta) do
    Keyword.get(call_meta, :name) == "member_access" and
      Keyword.get(meta, :name) not in [nil, "", "member_access"]
  end

  def callee_node?(_meta, _callee), do: false

  @doc """
  Collects string content from documentation attributes (`@moduledoc`, `@doc`,
  `@typedoc`).

  Returns a `MapSet` of strings that appear as values of documentation module
  attributes. Checks can use this to skip doc strings during literal analysis,
  preventing false positives when documentation merely *mentions* patterns like
  `Phoenix.HTML.raw/1` or URL examples.
  """
  @type doc_strings :: %{String.t() => true}

  @spec doc_string_contents(Metastatic.AST.meta_ast()) :: doc_strings()
  def doc_string_contents(ast) do
    {_, doc_strings} =
      Metastatic.AST.prewalk(ast, %{}, fn
        # Plain literal doc attribute: @moduledoc "..."
        {:assignment, meta, [{:variable, _, var_name}, {:literal, lit_meta, content}]} = node, acc
        when var_name in ["@moduledoc", "@doc", "@typedoc"] and is_binary(content) ->
          if Keyword.get(meta, :attribute_type) == :module_attribute and
               Keyword.get(lit_meta, :subtype) == :string do
            {node, Map.put(acc, content, true)}
          else
            {node, acc}
          end

        # Interpolated doc attribute: @moduledoc "...#{expr}..."
        # Collect all literal fragments inside the :string_interpolation
        {:assignment, meta, [{:variable, _, var_name}, {:string_interpolation, _, parts}]} = node,
        acc
        when var_name in ["@moduledoc", "@doc", "@typedoc"] and is_list(parts) ->
          if Keyword.get(meta, :attribute_type) == :module_attribute do
            new_acc =
              Enum.reduce(parts, acc, fn
                {:literal, lit_meta, content}, inner_acc
                when is_binary(content) ->
                  if Keyword.get(lit_meta, :subtype) == :string,
                    do: Map.put(inner_acc, content, true),
                    else: inner_acc

                _, inner_acc ->
                  inner_acc
              end)

            {node, new_acc}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    doc_strings
  end

  @doc """
  Returns `true` when `value` appears in the doc-strings set returned by
  `doc_string_contents/1`.
  """
  @spec doc_string?(doc_strings(), String.t()) :: boolean()
  def doc_string?(doc_strings, value), do: is_map_key(doc_strings, value)

  defp known_blocking_call?(name) do
    {module, function} = call_parts(name)
    operation = String.trim_trailing(function, "!")
    operations = Map.get(@blocking_modules, module, [])
    repo? = module == "Repo" or String.ends_with?(module, ".Repo")

    function in operations or operation in operations or
      (repo? and operation in @repo_operations)
  end
end
