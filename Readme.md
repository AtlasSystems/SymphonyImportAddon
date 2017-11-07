# Symphony Web Service Server Addon

## Versions
**1.0 -** Initial release

**1.1.0 -** *Enhancement:* Added ability to specify multiple fields in the Lookup Source Field. Used in the cases where the symphony call number contains both the callnumber and the location (ex: "82045 Box 1").

This addon imports ILS data from a Symphony Web Service for transactions that are in the specified data import queue. The transaction will be routed to one of 2 queues, depending on the success of the data import.

> *Note:* The Symphony Web Service is a custom CGI Script written by Stanford.

## Settings

### RequestMonitorQueue

The queue that the addon will monitor for transactions that need ILS data automatically imported from Symphony. The value of this setting is required.

*Default*: `Awaiting ILS Data Import`

### SuccessRouteQueue

The queue that the addon will route requests to after successfully importing ILS data from Symphony. The value of this setting is required.

*Default*: `Awaiting Request Processing`

### ErrorRouteQueue

The queue that the addon will route requests to if errors are encountered while importing ILS data from Symphony. The value of this setting is required.

*Default*: `Awaiting Manual Data Import`


### SymphonyWebServiceUrl

Base URL for the Symphony Web Service. The value of this setting is required.

*Example*: `https://{YourDomain}/cgi-bin/aeonItem.pl?`

### LookupSourceField

Specifies the transaction field that contains the Symphony record's Call Number. The value of this setting is required and must match the name of a column from the Transactions table. A second column may be specified in the lookup source in cases where an item's callnumber also contains a location. For these cases add a space between column names `CallNumber Location`

*Default*: `CallNumber`

### LocationDestinationField

Specifies the transaction field where the location information for the transaction should be stored. The value of this setting is optional. If specified, the value of this setting must match the name of a column from the Transactions table.

*Default*: `Location`

### BarcodeDestinationField

Specifies the transaction field where gathered barcode information should be stored. The value of this setting is optional. If specified, the value of this setting must match the name of a column from the Transactions table.

*Default*: `ReferenceNumber`


## Workflow Summary

The addon watches the transaction queue specified by the RequestMonitorQueue addon setting. When the addon detects that there are transactions present in the queue, it will grab the call number from the transaction. Using the call number, the addon will place a request on the Symphony Web Service and take the first result returned from the pipe-delimited record. Then, it will input the barcode and location into the specified fields. If there is an error during the process, the transaction will be routed to the queue specified in the `ErrorRouteQueue` setting.

## Error Handling

All error cases add a note to the transaction and then route the transaction to the specified error queue. From that queue, staff should be able to

1. Process the request as normal,
2. Manually fix the record and then route it back into monitor queue, or
3. Manually adjust the addon's settings and then route affected transactions back into the monitor queue.

## Error Cases

The addon will route transactions into the error queue for any of the following reasons.

- Call Number was not present in the specified fields of the transaction
- The connection to Symphony Web Service failed
- The Symphony Web Service request was invalid
- The Symphony Web Service request returned 0 results