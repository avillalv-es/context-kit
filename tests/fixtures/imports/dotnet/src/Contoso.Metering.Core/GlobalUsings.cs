// Central global usings for this project (C# 10+). Each names a NAMESPACE, not
// a file. The two that name System.* are external: no file in the repo
// declares them, so they draw no edge. 'Contoso.Metering.Abstractions' IS
// declared here, by IMeterReader.cs and Units.cs, so this file gets an edge to
// each.
//
// The edge runs from THIS file only. A global using really applies to every
// file in the project, so the files that use IMeterReader without a using of
// their own are a blind spot of the file-level graph, not edges it invents.

global using System.Threading.Tasks;
global using Contoso.Metering.Abstractions;
global using static System.Math;
