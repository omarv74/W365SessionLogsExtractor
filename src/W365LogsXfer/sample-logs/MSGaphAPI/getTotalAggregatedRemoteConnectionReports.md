# getTotalAggregatedRemoteConnectionReports

https://learn.microsoft.com/en-us/graph/api/cloudpcreports-gettotalaggregatedremoteconnectionreports?view=graph-rest-beta&tabs=http

https://developer.microsoft.com/en-us/graph/graph-explorer

https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/reports/microsoft.graph.getTotalAggregatedRemoteConnectionReports

# Test Request body  
  
## From Joe Indelli
```JSON
{
    "top": 25,
    "skip": 0,
}
```
## Based on MSLearn Docs
 ```JSON 
{
    "top": 25,
    "skip": 0,
    "filter": "(TotalUsageInHour le 80)",
    "select": [
        "CloudPcId",
        "ManagedDeviceName",
        "UserPrincipalName",
        "TotalUsageInHour",
        "LastActiveTime",
        "PcType",
        "CreatedDate"
    ]
}
```