namespace W365LogsXFer.Application;

public sealed record CloudPcConnectionReport
{
    public int TotalRowCount { get; init; }
    public IReadOnlyList<string> Columns { get; init; } = [];
    public IReadOnlyList<IReadOnlyList<string?>> Rows { get; init; } = [];
}
