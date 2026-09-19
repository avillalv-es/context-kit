# frozen_string_literal: true

require "bigdecimal"

=begin
Ruby has a block comment form, and it is nothing like #. Everything between
=begin and =end is comment, including the line below, which is flush left,
carries no # of its own, and names a file that really exists:

require_relative "../ledger/entry"

Pulling entry.rb back in here made a cycle, so it lives in history. A reader
that only knows about # sees a live require on that line and hands back an
edge that inverts the dependency direction of the whole fixture.
=end

# Minor-unit money helpers. A leaf: nothing in this fixture sits below it,
# and this file must end the scan with zero outgoing edges.
module Support
  module Money
    def self.cents(amount)
      (BigDecimal(amount.to_s) * 100).to_i
    end

    def self.humanize(cents)
      "$%.2f" % (cents / 100.0)
    end
  end
end
