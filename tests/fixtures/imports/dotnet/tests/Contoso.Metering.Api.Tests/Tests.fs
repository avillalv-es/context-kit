module Contoso.Metering.Api.Tests

// F# SOURCE is never scanned: .fs is not in the source-extension list, even
// though .fsproj is. 'open' is F#'s import keyword and no matcher exists for
// it, so every F# file in a repo is a graph hole.
open Xunit
open Contoso.Metering.Api

[<Fact>]
let ``api hosts controllers`` () = Assert.True(true)
