# frozen_string_literal: true

require_relative "../support/money"

module Ledger
  # One posted line in an account.
  class Entry
    attr_reader :memo, :cents

    def initialize(memo, amount)
      @memo = memo
      @cents = Support::Money.cents(amount)
    end

    def to_s
      "#{@memo}\t#{Support::Money.humanize(@cents)}"
    end
  end
end
