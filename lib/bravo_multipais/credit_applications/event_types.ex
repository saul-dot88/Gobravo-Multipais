defmodule BravoMultipais.CreditApplications.EventTypes do
  @moduledoc false

  # Core lifecycle
  @created "application.created"
  @risk_enqueued "risk.enqueued"
  @risk_enqueue_failed "risk.enqueue_failed"
  @risk_evaluated "risk.evaluated"

  # Webhook lifecycle
  @webhook_enqueued "webhook.enqueued"
  @webhook_enqueue_failed "webhook.enqueue_failed"
  @webhook_sending "webhook.sending"
  @webhook_sent "webhook.sent"
  @webhook_discarded "webhook.discarded"
  @webhook_failed "webhook.failed"
  @webhook_skipped "webhook.skipped"

  def created, do: @created
  def risk_enqueued, do: @risk_enqueued
  def risk_enqueue_failed, do: @risk_enqueue_failed
  def risk_evaluated, do: @risk_evaluated

  def webhook_enqueued, do: @webhook_enqueued
  def webhook_enqueue_failed, do: @webhook_enqueue_failed
  def webhook_sending, do: @webhook_sending
  def webhook_sent, do: @webhook_sent
  def webhook_discarded, do: @webhook_discarded
  def webhook_failed, do: @webhook_failed
  def webhook_skipped, do: @webhook_skipped
end
