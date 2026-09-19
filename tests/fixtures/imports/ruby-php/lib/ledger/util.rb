# frozen_string_literal: true

# A "." segment and an explicit .rb extension. Both are legal, and both have
# to normalize down to the same file a plain "entry" would reach.
require_relative "./entry.rb"

# Single quotes. The capture has to accept either quote character.
require_relative '../support/money'

module Ledger
  # Label helpers. Note the name: lib/support/util.rb is the other util.rb in
  # this tree, and nothing but the directory tells the two apart.
  module Util
    def self.label(entry)
      "#{entry.memo}: #{Support::Money.humanize(entry.cents)}"
    end
  end
end
