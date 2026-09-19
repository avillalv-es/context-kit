# frozen_string_literal: true

require "rspec"
require_relative "../lib/ledger"

# The hint a failed boot prints. The require_relative inside it is text, not
# code - and it names a file that really exists, so a reader that does not
# track string state invents spec -> lib/support/money.rb from this line.
BOOT_HINT = 'require_relative "../lib/support/money"'

# Split across two lines on purpose: the module string sits on a line of its
# own with no keyword on it, so a line-at-a-time reader cannot see it.
require_relative(
  "../lib/ledger/entry"
)

# The path is assembled by a method call rather than written as a literal.
# lib/ledger/util.rb is a real file and this is a real dependency on it, but
# nothing after `require` is a quoted string, so there is nothing to capture
# and the edge is lost rather than guessed.
require File.expand_path("../lib/ledger/util", __dir__)

RSpec.describe Ledger do
  it "opens an account" do
    expect(Ledger.open("ops")).to be_a(Ledger::Account)
  end

  it "documents the boot hint" do
    expect(BOOT_HINT).to include("money")
  end

  it "labels entries" do
    expect(Ledger::Util).to respond_to(:label)
  end
end
