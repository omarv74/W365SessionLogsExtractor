# getRemoteConnectionHistoricalReports
  
https://learn.microsoft.com/en-us/graph/api/cloudpcreports-getremoteconnectionhistoricalreports?view=graph-rest-beta&tabs=http

OData **filter** syntax: https://learn.microsoft.com/en-us/graph/filter-query-parameter?tabs=http  
OData **query** syntax: https://learn.microsoft.com/en-us/odata/concepts/queryoptions-overview  
  
# Test Request body  
## From Joe Indelli:
```JSON
{
    "filter": "contains(CloudPcId, '-')",
    "top": 25,
    "skip": 0
}
```
## From MSLearn Docs
> [!NOTE]
> **filter** uses **ne 'x'** because it is a required field and we want to include everything (all **CloudPcId**s).
 ```JSON 
{
    "filter": "CloudPcId ne 'x'",
    "top": 25,
    "skip": 0
}
```