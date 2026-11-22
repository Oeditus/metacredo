defmodule MetaCredo.Check.Readability.LongFunction do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    confidence: :high,
    param_defaults: [max_statements: 50],
    explanations: [
      check: """
      Detects functions with too many statements. Long functions are harder
      to read, test, and maintain. Break them into smaller, focused functions.
      """,
      params: [
        max_statements: "Maximum allowed statements per function (default: 50)"
      ],
      examples: [
        elixir: [
          wrong: """
          # 55 statements crammed into one function -- impossible to review or test
          def process_order(order, user, opts) do
            validate_user(user)
            check_inventory(order)
            apply_discounts(order)
            calculate_tax(order)
            reserve_stock(order)
            authorize_payment(order, user)
            capture_payment(order)
            create_shipment(order)
            notify_warehouse(order)
            send_confirmation_email(user)
            record_audit_event(order, user)
            update_analytics(order)
            invalidate_cache(order)
            publish_event(:order_placed, order)
            schedule_followup(order)
            validate_user(user)
            check_inventory(order)
            apply_discounts(order)
            calculate_tax(order)
            reserve_stock(order)
            authorize_payment(order, user)
            capture_payment(order)
            create_shipment(order)
            notify_warehouse(order)
            send_confirmation_email(user)
            record_audit_event(order, user)
            update_analytics(order)
            invalidate_cache(order)
            publish_event(:order_placed, order)
            schedule_followup(order)
            validate_user(user)
            check_inventory(order)
            apply_discounts(order)
            calculate_tax(order)
            reserve_stock(order)
            authorize_payment(order, user)
            capture_payment(order)
            create_shipment(order)
            notify_warehouse(order)
            send_confirmation_email(user)
            record_audit_event(order, user)
            update_analytics(order)
            invalidate_cache(order)
            publish_event(:order_placed, order)
            schedule_followup(order)
            validate_user(user)
            check_inventory(order)
            apply_discounts(order)
            calculate_tax(order)
            reserve_stock(order)
            authorize_payment(order, user)
            capture_payment(order)
            create_shipment(order)
            notify_warehouse(order)
            send_confirmation_email(user)
          end
          """,
          correct: """
          # Compose focused private helpers that each do one thing
          def process_order(order, user, opts) do
            with :ok <- validate(order, user),
                 order <- apply_pricing(order, opts),
                 {:ok, order} <- persist(order) do
              {:ok, order}
            end
          end

          defp validate(order, user), do: ...
          defp apply_pricing(order, opts), do: ...
          defp persist(order), do: ...
          """
        ],
        javascript: [
          wrong: """
          // 55 statements crammed into one function -- impossible to review or test
          function processOrder(orderId, userId) {
            validateUser(userId);
            checkInventory(orderId);
            applyDiscounts(orderId);
            calculateTax(orderId);
            reserveStock(orderId);
            authorizePayment(orderId, userId);
            capturePayment(orderId);
            createShipment(orderId);
            notifyWarehouse(orderId);
            sendConfirmationEmail(userId);
            recordAuditEvent(orderId, userId);
            updateAnalytics(orderId);
            invalidateCache(orderId);
            publishEvent(orderId);
            scheduleFollowup(orderId);
            validateUser(userId);
            checkInventory(orderId);
            applyDiscounts(orderId);
            calculateTax(orderId);
            reserveStock(orderId);
            authorizePayment(orderId, userId);
            capturePayment(orderId);
            createShipment(orderId);
            notifyWarehouse(orderId);
            sendConfirmationEmail(userId);
            recordAuditEvent(orderId, userId);
            updateAnalytics(orderId);
            invalidateCache(orderId);
            publishEvent(orderId);
            scheduleFollowup(orderId);
            validateUser(userId);
            checkInventory(orderId);
            applyDiscounts(orderId);
            calculateTax(orderId);
            reserveStock(orderId);
            authorizePayment(orderId, userId);
            capturePayment(orderId);
            createShipment(orderId);
            notifyWarehouse(orderId);
            sendConfirmationEmail(userId);
            recordAuditEvent(orderId, userId);
            updateAnalytics(orderId);
            invalidateCache(orderId);
            publishEvent(orderId);
            scheduleFollowup(orderId);
            validateUser(userId);
            checkInventory(orderId);
            applyDiscounts(orderId);
            calculateTax(orderId);
            reserveStock(orderId);
            authorizePayment(orderId, userId);
            capturePayment(orderId);
            createShipment(orderId);
            notifyWarehouse(orderId);
            sendConfirmationEmail(userId);
          }
          """,
          correct: """
          // Compose focused helpers that each do one thing
          function processOrder(orderId, userId) {
            validateUser(userId);
            checkInventory(orderId);
            applyDiscounts(orderId);
            const total = calculateTax(orderId);
            return { orderId, userId, total };
          }
          """
        ],
        go: [
          wrong: """
          // 55 statements crammed into one function -- impossible to review or test
          func processOrder(orderID, userID string) {
          \tvalidateUser(userID)
          \tcheckInventory(orderID)
          \tapplyDiscounts(orderID)
          \tcalculateTax(orderID)
          \treserveStock(orderID)
          \tauthorizePayment(orderID, userID)
          \tcapturePayment(orderID)
          \tcreateShipment(orderID)
          \tnotifyWarehouse(orderID)
          \tsendConfirmationEmail(userID)
          \trecordAuditEvent(orderID, userID)
          \tupdateAnalytics(orderID)
          \tinvalidateCache(orderID)
          \tpublishEvent(orderID)
          \tscheduleFollowup(orderID)
          \tvalidateUser(userID)
          \tcheckInventory(orderID)
          \tapplyDiscounts(orderID)
          \tcalculateTax(orderID)
          \treserveStock(orderID)
          \tauthorizePayment(orderID, userID)
          \tcapturePayment(orderID)
          \tcreateShipment(orderID)
          \tnotifyWarehouse(orderID)
          \tsendConfirmationEmail(userID)
          \trecordAuditEvent(orderID, userID)
          \tupdateAnalytics(orderID)
          \tinvalidateCache(orderID)
          \tpublishEvent(orderID)
          \tscheduleFollowup(orderID)
          \tvalidateUser(userID)
          \tcheckInventory(orderID)
          \tapplyDiscounts(orderID)
          \tcalculateTax(orderID)
          \treserveStock(orderID)
          \tauthorizePayment(orderID, userID)
          \tcapturePayment(orderID)
          \tcreateShipment(orderID)
          \tnotifyWarehouse(orderID)
          \tsendConfirmationEmail(userID)
          \trecordAuditEvent(orderID, userID)
          \tupdateAnalytics(orderID)
          \tinvalidateCache(orderID)
          \tpublishEvent(orderID)
          \tscheduleFollowup(orderID)
          \tvalidateUser(userID)
          \tcheckInventory(orderID)
          \tapplyDiscounts(orderID)
          \tcalculateTax(orderID)
          \treserveStock(orderID)
          \tauthorizePayment(orderID, userID)
          \tcapturePayment(orderID)
          \tcreateShipment(orderID)
          \tnotifyWarehouse(orderID)
          \tsendConfirmationEmail(userID)
          }
          """,
          correct: """
          // Compose focused helpers that each do one thing
          func processOrder(orderID, userID string) error {
          \tif err := validate(userID); err != nil {
          \t\treturn err
          \t}
          \tif err := applyPricing(orderID); err != nil {
          \t\treturn err
          \t}
          \treturn persist(orderID)
          }
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    max_statements = params_get(params, :max_statements)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, max_statements)
      end)

    issues
  end

  defp traverse({:function_def, meta, children} = node, issues, source_file, max_statements)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "anonymous")
    count = count_statements(children)

    if count > max_statements do
      line = CheckUtils.line_of(meta)

      issue =
        format_issue(source_file,
          message: "Function '#{name}' has #{count} statements (max allowed: #{max_statements})",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _max), do: {node, issues}

  # Count top-level statements in a function body
  defp count_statements({:block, _meta, stmts}) when is_list(stmts) do
    Enum.reduce(stmts, 0, fn stmt, acc -> acc + count_statements(stmt) end)
  end

  defp count_statements(children) when is_list(children) do
    Enum.reduce(children, 0, fn child, acc -> acc + count_statements(child) end)
  end

  # Each significant node counts as one statement
  defp count_statements({type, _meta, _children})
       when type in [
              :assignment,
              :function_call,
              :conditional,
              :loop,
              :pattern_match,
              :exception_handling,
              :early_return,
              :augmented_assignment,
              :inline_match
            ] do
    1
  end

  defp count_statements(_), do: 0
end
