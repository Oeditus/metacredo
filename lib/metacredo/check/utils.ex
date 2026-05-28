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

  # Names that appear as :variable nodes but are actually special forms
  @special_names ~W[
    __MODULE__ __ENV__ __DIR__ __CALLER__ __STACKTRACE__
    _ ... __struct__ __exception__
  ]

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

  @doc """
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
end
