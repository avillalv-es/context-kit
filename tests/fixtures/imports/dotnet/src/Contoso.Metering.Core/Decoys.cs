// Nothing imports this file. Every namespace it declares is named by a using
// that sits inside a comment or a string literal elsewhere in the fixture
// (ReadingParser.cs, MultiLineUsings.cs), so an edge INTO this file means one
// of those traps was read as code.
//
// The declarations nest on purpose: 'namespace Core.Legacy' inside
// 'namespace Contoso.Metering' declares Contoso.Metering.Core.Legacy.
namespace Contoso.Metering
{
    namespace Core.Legacy
    {
        internal static class OldFormat { }
    }

    namespace Core.Diagnostics
    {
        internal static class Trace { }
    }

    namespace Ghost
    {
        internal static class G { }
    }

    namespace Phantom
    {
        internal static class P { }
    }
}

// The reverse trap. These two namespaces are mentioned HERE and declared
// nowhere, because both mentions are text: Bootstrap.cs imports them, and the
// imports must drop as external rather than land on this file.
//
// namespace Contoso.Metering.Archived;
/*
namespace Contoso.Metering.Archived { }
*/
internal static class Templates
{
    public const string Generated = @"
namespace Contoso.Metering.Generated;
";
}
