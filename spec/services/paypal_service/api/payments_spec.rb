require 'spec_helper'

require_relative '../test_events'
require_relative '../test_logger'
require_relative '../test_merchant'

describe PaypalService::API::Payments do

  TokenStore = PaypalService::Store::Token
  PaymentStore = PaypalService::Store::PaypalPayment

  before(:each) do
    @events = PaypalService::TestEvents.new
    @api_builder = PaypalService::TestApiBuilder.new
    @payments = PaypalService::API::Payments.new(
      @events,
      PaypalService::TestMerchant.build(@api_builder),
      PaypalService::TestLogger.new)

    @cid = 10
    @mid = "merchant_id_1"
    @paypal_email = "merchant_1@test.com"
    @payer_id = "payer_id_1"

    PaypalService::PaypalAccount::Command.create_personal_account(
      @mid,
      @cid,
      { email: @paypal_email, payer_id: @payer_id })

    @tx_id = 1234

    @req_info = {
      transaction_id: @tx_id,
      item_name: "Item name",
      item_quantity: 1,
      item_price: Money.new(1200, "EUR"),
      merchant_id: @mid,
      order_total: Money.new(1200, "EUR"),
      success: "https://www.test.com/success",
      cancel: "https://www.test.com/cancel"
    }
  end

  context "#request and #request_cancel" do
    it "saves token info" do
      response = @payments.request(@cid, @req_info)
      token = PaypalService::Store::Token.get_for_transaction(@cid, @tx_id)

      expect(token[:community_id]).to eq @cid
      expect(token[:token]).to eq response[:data][:token]
      expect(token[:transaction_id]).to eq @req_info[:transaction_id]
      expect(token[:merchant_id]).to eq @req_info[:merchant_id]
      expect(token[:item_name]).to eq @req_info[:item_name]
      expect(token[:item_quantity]).to eq @req_info[:item_quantity]
      expect(token[:item_price]).to eq @req_info[:item_price]
    end

    it "tries the paypal api call at least 3 times in case of 10001" do
      @api_builder.will_fail(2, "10001")
      response = @payments.request(@cid, @req_info)

      expect(response.success).to eq(true)
    end

    it "cancel deletes token and fires request_cancelled event" do
      @payments.request(@cid, @req_info)
      token = PaypalService::Store::Token.get_for_transaction(@cid, @tx_id)

      @payments.request_cancel(@cid, token[:token])

      expect(PaypalToken.count).to eq 0
      expect(@events.received_events[:request_cancelled].length).to eq 1
      expect(@events.received_events[:request_cancelled].first).to eq([:api, token])
    end

    it "cancel fires no events for non-existent token" do
      result = @payments.request_cancel(@cid, "foo_bar_token")

      expect(result[:success]).to eq false
      expect(PaypalToken.count).to eq 0
      expect(@events.received_events[:request_cancelled].length).to eq 0
    end
  end

  context "#create" do
    it "creates, authorizes and saves the new payment" do
      token = @payments.request(@cid, @req_info)[:data]

      payment_res = @payments.create(@cid, token[:token])

      payment = PaymentStore.get(@cid, @tx_id)
      expect(payment_res.success).to eq(true)
      expect(payment).not_to be_nil
      expect(payment_res[:data][:payment_status]).to eq(:pending)
      expect(payment_res[:data][:pending_reason]).to eq(:authorization)
      expect(payment_res[:data][:order_id]).not_to be_nil
      expect(payment_res[:data][:order_total]).to eq(@req_info[:order_total])
      expect(payment_res[:data][:authorization_id]).not_to be_nil
      expect(payment_res[:data][:authorization_total]).to eq(@req_info[:order_total])
    end

    it "triggers payment_created event followed by payment_updated" do
      token = @payments.request(@cid, @req_info)[:data]
      payment_res = @payments.create(@cid, token[:token])

      payment = PaymentStore.get(@cid, @tx_id)
      expect(@events.received_events[:payment_created].length).to eq(1)
      expect(@events.received_events[:payment_updated].length).to eq(1)
      expect(@events.received_events[:payment_updated].first).to eq([:api, payment_res[:data]])
    end

    it "will retry at least 3 times" do
      token = @payments.request(@cid, @req_info)[:data]
      @api_builder.will_fail(2, "10001")
      payment_res = @payments.create(@cid, token[:token])

      expect(payment_res.success).to eq(true)
    end

    it "deletes request token when payment created" do
      token = @payments.request(@cid, @req_info)[:data]
      @payments.create(@cid, token[:token])

      expect(PaypalToken.count).to eq 0
    end

    it "returns failure and fires no events when called with non-existent token" do
      res = @payments.create(@cid, "not_a_real_token")

      expect(res.success).to eq(false)
      expect(@events.received_events[:payment_created].length).to eq(0)
      expect(@events.received_events[:payment_updated].length).to eq(0)
    end

    it "deletes token and fires request_cancelled after 3 paypal api failures" do
      token = @payments.request(@cid, @req_info)[:data]
      @api_builder.will_fail(3, "10001")
      payment_res = @payments.create(@cid, token[:token])

      expect(payment_res.success).to eq(false)
      expect(@events.received_events[:request_cancelled].length).to eq(1)
      expect(@events.received_events[:request_cancelled].first.second[:transaction_id]).to eq(@tx_id)
      expect(PaypalToken.count).to eq(0)
    end

    it "keeps token and returns redirect_url in error data upon 10486 error" do
      token = @payments.request(@cid, @req_info)[:data]
      @api_builder.will_fail(1, "10486")
      payment_res = @payments.create(@cid, token[:token])

      expect(payment_res.success).to eq(false)
      expect(payment_res[:data][:redirect_url]).not_to be_nil
      expect(PaypalToken.count).to eq(1)
    end

  end

  context "#full_capture" do
    before(:each) do
      @payment_total = Money.new(1200, "EUR")
      token = @payments.request(@cid, @req_info)[:data]
      @payments.create(@cid, token[:token])[:data]
      @events.clear
    end

    it "completes the payment with given payment_total" do
      payment_res = @payments.full_capture(@cid, @tx_id, { payment_total: @payment_total })

      expect(payment_res.success).to eq(true)
      expect(payment_res[:data][:payment_status]).to eq(:completed)
      expect(payment_res[:data][:pending_reason]).to eq(:none)
      expect(payment_res[:data][:payment_id]).not_to be_nil
      expect(payment_res[:data][:payment_total]).to eq(@payment_total)
    end

    it "fires payment_updated event" do
      payment_res = @payments.full_capture(@cid, @tx_id, { payment_total: @payment_total })

      expect(@events.received_events[:payment_updated].length).to eq(1)
      expect(@events.received_events[:payment_updated].last).to eq([:api, payment_res[:data]])
    end

    it "will retry at least 5 times in case of 10001" do
      @api_builder.will_fail(4, "10001")
      payment_res = @payments.full_capture(@cid, @tx_id, { payment_total: @payment_total })

      expect(payment_res.success).to eq(true)
    end

    it "returns failure and fires no events if called for non-existent payment" do
      payment_res = @payments.full_capture(@cid, 987654321, { payment_total: @payment_total })

      expect(payment_res.success).to eq(false)
      expect(@events.received_events[:payment_updated].length).to eq(0)
    end

    it "only captures a payment once, second time returns failure" do
      @payments.full_capture(@cid, @tx_id, { payment_total: @payment_total })
      @events.clear

      payment_res = @payments.full_capture(@cid, @tx_id, { payment_total: @payment_total })

      expect(payment_res.success).to eq(false)
      expect(@events.received_events[:payment_updated].length).to eq(0)
    end

    it "voids payment and fires payment_updated after 5 paypal api fails" do
      @api_builder.will_fail(5, "x-timeout")
      payment_res = @payments.full_capture(@cid, @tx_id, { payment_total: @payment_total })

      expect(payment_res.success).to eq(false)
      expect(@events.received_events[:payment_updated].length).to eq(1)
      expect(@events.received_events[:payment_updated].first.second[:payment_status]).to eq(:voided)
    end
  end

  context "#void" do
    before(:each) do
      @payment_total = Money.new(1200, "EUR")
      token = @payments.request(@cid, @req_info)[:data]
      @payments.create(@cid, token[:token])[:data]
      @events.clear
    end

    it "voids an authorized payment" do
      payment_res = @payments.void(@cid, @tx_id, { note: "Voided for testing purposes." })

      expect(payment_res.success).to eq(true)
      expect(payment_res[:data][:payment_status]).to eq(:voided)
      expect(payment_res[:data][:pending_reason]).to eq(:none)
    end

    it "triggers a payment updated event" do
      payment_res = @payments.void(@cid, @tx_id, { note: "Voided for testing purposes." })

      expect(@events.received_events[:payment_updated].length).to eq(1)
      expect(@events.received_events[:payment_updated].first).to eq([:api, payment_res[:data]])
    end

    it "will retry at least 5 times" do
      @api_builder.will_fail(4, "x-servererror")
      payment_res = @payments.void(@cid, @tx_id, { note: "Voided for testing purposes." })

      expect(payment_res.success).to eq(true)
    end

    it "cannot void the same payment twice" do
      @payments.void(@cid, @tx_id, { note: "Voided for testing purposes." })
      @events.clear
      payment_res = @payments.void(@cid, @tx_id, { note: "Voided for testing purposes." })

      expect(payment_res.success).to eq(false)
      expect(@events.received_events[:payment_updated].length).to eq(0)
    end

    it "cannot void a captured payment" do
      @payments.full_capture(@cid, @tx_id, { payment_total: @payment_total })
      @events.clear
      payment_res = @payments.void(@cid, @tx_id, { note: "Voided for testing purposes." })

      expect(payment_res.success).to eq(false)
      expect(@events.received_events[:payment_updated].length).to eq(0)
      expect(PaymentStore.get(@cid, @tx_id)[:payment_status]).to eq(:completed)
    end

    it "does nothing if called for non-existent payment" do
      payment_res = @payments.void(@cid, 987654321, { note: "Voided for testing purposes." })

      expect(payment_res.success).to eq(false)
      expect(@events.received_events[:payment_updated].length).to eq(0)
    end
  end

  context "#get_payment" do
    it "returns payment for given commmunity_id and transaction_id" do
      token = @payments.request(@cid, @req_info)[:data]
      expect(@payments.get_payment(@cid, @tx_id).success).to eq(false)

      payment_res = @payments.create(@cid, token[:token])
      expect(@payments.get_payment(@cid, @tx_id)[:data]).to eq(payment_res[:data])

      payment_res = @payments.full_capture(@cid, @tx_id, { payment_total: Money.new(1200, "EUR") })
      expect(@payments.get_payment(@cid, @tx_id)[:data]).to eq(payment_res[:data])
    end
  end

end
