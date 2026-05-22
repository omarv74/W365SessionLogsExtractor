# MSGraph API usage

## getRemoteConnectionHistoricalReports
  
https://learn.microsoft.com/en-us/graph/api/cloudpcreports-getremoteconnectionhistoricalreports?view=graph-rest-beta&tabs=csharp

OData **filter** syntax: https://learn.microsoft.com/en-us/graph/filter-query-parameter?tabs=csharp  
OData **query** syntax: https://learn.microsoft.com/en-us/odata/concepts/queryoptions-overview  
  
## Test Request body examples

### This is a good example for dev/smoke-testing. Returns a small result set of 25 rows where **CloudPcId** contains a hyphen (all Cloud PC IDs contain hyphens, so this effectively returns all rows but is syntactically valid for the required filter field)

```JSON
{
    "filter": "contains(CloudPcId, '-')",
    "top": 25,
    "skip": 0
}
```  

### From MSLearn Docs. **filter** uses **ne 'x'** because it is a required field and we want to include everything (all **CloudPcId**s)

 ```JSON 
{
    "filter": "CloudPcId ne 'x'",
    "top": 25,
    "skip": 0
}
```