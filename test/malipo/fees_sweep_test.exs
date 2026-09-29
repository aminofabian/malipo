defmodule Malipo.FeesSweepTest do
  use Malipo.DataCase, async: false

  alias Malipo.Fees
  alias Malipo.Fees.Sweep
  alias Malipo.Intents
  alias Malipo.Rails.TokenCache
  alias Malipo.Repo

  defp base_attrs(key, amount) do
    %{
      business_id: "biz_sweep",
      idempotency_key: key,
      amount: amount,
      payer_msisdn: "0712345678",
      context: %{"type" => "POS_PAYMENT", "id" => key}
    }
  end

  defp settle(key, amount) do
    {:ok, intent} = Intents.create(base_attrs(key, amount))
    {:ok, prompted} = Intents.mark_prompted(intent, %{checkout_request_id: "ws_#{key}"})
    {:ok, settled} = Intents.mark_settled(prompted, %{receipt: "RCP_#{key}"})
    settled
  end

  defp config_destination do
    {:ok, _} =
      Fees.update_config(%{
        "fee_destination_kind" => "till",
        "fee_destination_till" => "5738421",
        "fee_destination_name" => "Fees"
      })
  end

  describe "recording" do
    test "settlement records a pending sweep when a destination is set" do
      config_destination()
      settled = settle("sweep-rec-1", "1450.00")

      assert [%Sweep{} = sweep] = Repo.all(Sweep)
      assert sweep.intent_id == settled.id
      assert Decimal.eq?(sweep.amount, Decimal.new(15))
      assert sweep.status == "pending"
      assert sweep.mode == "manual"
      assert sweep.destination_kind == "till"
      assert sweep.destination_till == "5738421"
    end

    test "no sweep is recorded without a destination" do
      _ = settle("sweep-rec-2", "1450.00")
      assert Repo.all(Sweep) == []
    end

    test "no sweep is recorded for a zero-fee band" do
      config_destination()
      _ = settle("sweep-rec-3", "5.00")
      assert Repo.all(Sweep) == []
    end
  end

  describe "manual mode" do
    test "worker parks the sweep at awaiting, operator settles it" do
      config_destination()
      _ = settle("sweep-man-1", "1450.00")

      [sweep] = Repo.all(Sweep)
      assert :ok = Fees.process_sweep(sweep)

      sweep = Repo.get!(Sweep, sweep.id)
      assert sweep.status == "awaiting"

      {:ok, done} = Fees.mark_sweep_settled(sweep, %{receipt: "MANUAL-1"})
      assert done.status == "settled"
      assert done.receipt == "MANUAL-1"
    end

    test "operator can skip a sweep" do
      config_destination()
      _ = settle("sweep-man-2", "600.00")

      [sweep] = Repo.all(Sweep)
      {:ok, skipped} = Fees.mark_sweep_skipped(sweep, "written off")
      assert skipped.status == "skipped"
    end
  end

  describe "auto mode" do
    setup do
      bypass = Bypass.open()
      base = "http://127.0.0.1:#{bypass.port}"
      previous = Application.get_env(:malipo, :daraja, [])

      Application.put_env(:malipo, :daraja,
        consumer_key: "key",
        consumer_secret: "secret",
        shortcode: "4094529",
        passkey: "live-passkey-not-sandbox",
        environment: "sandbox",
        shortcode_type: "paybill",
        base_url: base,
        callback_base: "https://kiosk.ke",
        initiator_name: "kioskpay",
        security_credential: "SECRET-CRED"
      )

      TokenCache.invalidate({"key", base})
      on_exit(fn -> Application.put_env(:malipo, :daraja, previous) end)

      Bypass.stub(bypass, "GET", "/oauth/v1/generate", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"access_token":"tok_test","expires_in":3599}))
      end)

      {:ok, agent: start_supervised!({Agent, fn -> nil end}), bypass: bypass}
    end

    test "auto sweep sends a B2B request and marks sent", %{agent: agent, bypass: bypass} do
      config_destination()
      {:ok, _} = Fees.update_config(%{"sweep_mode" => "auto"})
      _ = settle("sweep-auto-1", "1450.00")

      [sweep] = Repo.all(Sweep)
      assert sweep.mode == "auto"

      Bypass.expect(bypass, "POST", "/mpesa/b2b/v1/paymentrequest", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        Agent.update(agent, fn _ -> Jason.decode!(body) end)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"ConversationID":"conv-1","OriginatorConversationID":"oc-1","ResponseCode":"0"})
        )
      end)

      assert :ok = Fees.process_sweep(sweep)

      body = Agent.get(agent, & &1)
      assert body["CommandID"] == "BusinessBuyGoods"
      assert body["RecieverIdentifierType"] == "2"
      assert body["PartyA"] == "4094529"
      assert body["PartyB"] == "5738421"
      assert body["Amount"] == 15
      assert body["Initiator"] == "kioskpay"
      assert body["SecurityCredential"] == "SECRET-CRED"
      assert body["ResultURL"] == "https://kiosk.ke/webhooks/daraja/b2b/result"

      sent = Repo.get!(Sweep, sweep.id)
      assert sent.status == "sent"
      assert sent.provider_conversation_id == "conv-1"
    end

    test "a permanent provider rejection marks the sweep failed", %{bypass: bypass} do
      config_destination()
      {:ok, _} = Fees.update_config(%{"sweep_mode" => "auto"})
      _ = settle("sweep-auto-2", "1450.00")

      [sweep] = Repo.all(Sweep)

      Bypass.expect(bypass, "POST", "/mpesa/b2b/v1/paymentrequest", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"ResponseCode":"1","ResponseDescription":"Insufficient funds"})
        )
      end)

      assert :ok = Fees.process_sweep(sweep)
      failed = Repo.get!(Sweep, sweep.id)
      assert failed.status == "failed"
      assert failed.failure_kind == "insufficient_funds"
    end

    test "auto sweep without rail operator credentials is parked for an operator" do
      config_destination()
      {:ok, _} = Fees.update_config(%{"sweep_mode" => "auto"})
      _ = settle("sweep-auto-3", "1450.00")

      previous = Application.get_env(:malipo, :daraja, [])
      Application.put_env(:malipo, :daraja, Keyword.delete(previous, :security_credential))
      on_exit(fn -> Application.put_env(:malipo, :daraja, previous) end)

      [sweep] = Repo.all(Sweep)
      assert :ok = Fees.process_sweep(sweep)
      assert Repo.get!(Sweep, sweep.id).status == "awaiting"
    end

    test "retryable provider errors surface for Oban to retry", %{bypass: bypass} do
      config_destination()
      {:ok, _} = Fees.update_config(%{"sweep_mode" => "auto"})
      _ = settle("sweep-auto-4", "1450.00")

      [sweep] = Repo.all(Sweep)

      Bypass.expect(bypass, "POST", "/mpesa/b2b/v1/paymentrequest", fn conn ->
        Plug.Conn.resp(conn, 500, ~s({"errorMessage":"boom"}))
      end)

      assert {:error, _} = Fees.process_sweep(sweep)
      assert Repo.get!(Sweep, sweep.id).status == "pending"
    end
  end

  describe "result callback" do
    test "a successful b2b_result settles the matching sweep" do
      config_destination()
      _ = settle("sweep-cb-1", "1450.00")

      [sweep] = Repo.all(Sweep)

      {:ok, _} =
        sweep
        |> Sweep.mark_sent_changeset(%{provider_conversation_id: "conv-cb"})
        |> Repo.update()

      payload = %{
        "Result" => %{
          "ResultCode" => 0,
          "ResultDesc" => "ok",
          "ConversationID" => "conv-cb",
          "OriginatorConversationID" => "oc-cb",
          "TransactionID" => "QRY123"
        }
      }

      assert {:ok, %Sweep{status: "settled"} = settled} =
               Fees.finalize_sweep_webhook("b2b_result", payload)

      assert settled.receipt == "QRY123"
    end

    test "an unmatched callback is a no-op" do
      assert {:ok, nil} =
               Fees.finalize_sweep_webhook("b2b_result", %{
                 "Result" => %{"ConversationID" => "nope"}
               })
    end

    test "a timeout marks the sweep failed" do
      config_destination()
      _ = settle("sweep-cb-2", "1450.00")

      [sweep] = Repo.all(Sweep)

      {:ok, _} =
        sweep
        |> Sweep.mark_sent_changeset(%{provider_conversation_id: "conv-to"})
        |> Repo.update()

      payload = %{
        "Result" => %{
          "ResultCode" => 1037,
          "ResultDesc" => "timed out",
          "ConversationID" => "conv-to"
        }
      }

      assert {:ok, %Sweep{status: "failed", failure_kind: "timeout"}} =
               Fees.finalize_sweep_webhook("b2b_timeout", payload)
    end

    test "the b2b_result webhook settles the sweep end to end" do
      config_destination()
      _ = settle("sweep-wh-1", "1450.00")

      [sweep] = Repo.all(Sweep)

      {:ok, _} =
        sweep
        |> Sweep.mark_sent_changeset(%{provider_conversation_id: "conv-wh"})
        |> Repo.update()

      payload = %{
        "Result" => %{
          "ResultCode" => 0,
          "ConversationID" => "conv-wh",
          "TransactionID" => "QRY-WH"
        }
      }

      {:ok, event} = Malipo.Webhooks.ingest("b2b_result", Jason.encode!(payload))
      {:ok, processed} = Malipo.Webhooks.process(event.id)
      assert processed.status == "processed"
      assert Repo.get!(Sweep, sweep.id).status == "settled"
    end

    test "an unmatched b2b_result webhook is ignored" do
      {:ok, event} =
        Malipo.Webhooks.ingest(
          "b2b_result",
          Jason.encode!(%{"Result" => %{"ConversationID" => "unknown"}})
        )

      {:ok, processed} = Malipo.Webhooks.process(event.id)
      assert processed.status == "ignored"
    end
  end
end
