# frozen_string_literal: true

require "json"

require_relative "ledger/account"
require_relative "ledger/entry"

# Two statements on one line. Both are real requires to real files, and they
# name the two util.rb files that a load-path require cannot tell apart. A
# reader that stops at the first match on a line silently loses the second.
require_relative "ledger/util"; require_relative "support/util"

# Money arrives transitively through account.rb. Requiring it here as well
# only hid load-order bugs, so the line stays commented out - and it names a
# file that really exists, which is what makes it a trap.
# require_relative "support/money"

# Optional exporters are named at run time. The path is interpolated, so no
# static reader can say which file this reaches; it must drop, not guess.
%w[csv_export pdf_export].each do |ext|
  begin
    require_relative "ledger/#{ext}"
  rescue LoadError
    nil
  end
end

# autoload defers the load until the constant is first touched. It is a
# fourth way to name a file, it is not in the capture set, and the file it
# names is not in the tree either.
autoload :CsvExport, "ledger/csv_export"

module Ledger
  VERSION = "0.3.1"

  def self.open(name)
    Account.new(name)
  end
end
