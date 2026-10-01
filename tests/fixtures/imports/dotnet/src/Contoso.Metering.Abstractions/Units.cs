namespace Contoso.Metering.Abstractions
{
    // The BLOCK-scoped form of the namespace IMeterReader.cs declares
    // file-scoped. Two files, one namespace, so a using of it reaches both.
    public static class Units
    {
        public const double WhPerKwh = 1000.0;
    }
}
