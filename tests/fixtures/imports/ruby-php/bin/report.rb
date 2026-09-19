#!/usr/bin/env ruby
# frozen_string_literal: true

# Run as `ruby -Ilib bin/report.rb`. lib/ is on the load path, which is why
# the third require below is load-path rooted rather than relative.
require "thor"

require_relative "../lib/ledger"
require "ledger/account"

# Two files in this tree are called util.rb: lib/ledger/util.rb and
# lib/support/util.rb. A load-path require names neither directory, so the
# suffix key is ambiguous and the only safe answer is to drop it. Picking
# either one would be a coin flip dressed up as a dependency.
require "util"

# The formatter exists in PHP only; the Ruby port has not been written yet.
# src/Support/Format.php is right there in the tree, and an extension-blind
# matcher hands it back for this line - a cross-language edge to a file this
# script could not load if it tried.
begin
  require_relative "../src/Support/Format"
rescue LoadError
  nil
end

# A vendored helper checked out beside the project rather than inside it.
# The path climbs out of the scanned tree, so it must drop rather than be
# clamped back to the root - ../../js-ts/app/main is a real directory one
# level above this fixture.
begin
  require_relative "../../js-ts/app/main"
rescue LoadError
  nil
end

# `load` names a file too. It is a fifth spelling of "depend on this path",
# it is not in the capture set, and this one is concatenated at run time
# besides. Nothing is captured, so nothing is emitted.
load __dir__ + "/../lib/ledger/plugins.rb" if ENV["LEDGER_PLUGINS"]

# Heredoc. Every line of the body is text. The require_relative inside it
# starts a line with its keyword OUTSIDE any quote on that line, so a
# per-line string mask cannot help: only heredoc state keeps it out, and the
# file it names really exists.
USAGE = <<~TEXT
  Boot problems? Put this at the top of your script:
    require_relative "../lib/support/money"
  and run again with -Ilib.
TEXT

class ReportCLI < Thor
  desc "balance NAME", "print the balance for one account"
  def balance(name)
    account = Ledger::Account.new(name)
    account.post("opening", "12.50")
    puts Ledger::Util.label(account)
    puts account.balance
  end

  desc "usage", "print the boot hint"
  def usage
    puts USAGE
  end
end

ReportCLI.start(ARGV) if $PROGRAM_NAME == __FILE__
