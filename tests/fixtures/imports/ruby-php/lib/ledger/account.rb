# frozen_string_literal: true

require_relative "entry"
# Sibling util.rb. The string carries no directory at all, and there is a
# second util.rb under lib/support/, so only the importing file's own
# directory decides which one this is.
require_relative "util"
require_relative "../support/money"

module Ledger
  # A named bucket of entries.
  class Account
    attr_reader :name

    def initialize(name)
      @name = name
      @entries = []
    end

    def post(memo, amount)
      @entries << Entry.new(memo, amount)
      self
    end

    def balance
      Support::Money.humanize(@entries.sum(&:cents))
    end

    def labels
      @entries.map { |e| Util.label(e) }
    end
  end
end
