namespace W365LogsXFer.Application;

public interface IGraphReportsService
{
    Task<CloudPcConnectionReport> GetTotalAggregatedRemoteConnectionReportsAsync(CancellationToken cancellationToken = default);
}
