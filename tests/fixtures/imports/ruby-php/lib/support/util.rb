# frozen_string_literal: true

# The hash below is INSIDE a string. A comment stripper that cuts the line at
# the first `#` it sees throws away the require that follows on the same
# line, and the edge to money.rb disappears with it.
COMMENT_MARK = "#"; require_relative("money")

module Support
  # The second util.rb. lib/ledger/util.rb is the other one.
  module Util
    def self.strip_comments(text)
      text.split(COMMENT_MARK, 2).first.to_s
    end
  end
end
