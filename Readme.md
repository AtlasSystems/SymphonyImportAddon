# Symphony Web Service Server Addon

This addon imports ILS data from a Symphony Web Service for transactions that are in the specified data import queue. The transaction will be routed to one of 2 queues, depending on the success of the data import.

> *Note:* The Symphony Web Service is a custom CGI Script written by Stanford.

## Versions

**1.0 -** Initial release

**1.1.0 -** *Enhancement:* Added ability to specify multiple fields in the Lookup Source Field. Used in the cases where the symphony call number contains both the callnumber and the location (ex: "82045 Box 1").

**1.2.0 -** *Enhancement:* Added ability to import Shelf Location from the Symphony Web Service.

**1.2.1 -** *Fix:* Removes leading/trailing space from data being imported

## Requirements

### Network Access

The addon requires outbound HTTP(s) access to the URL indicated in the SymphonyWebServiceUrl setting. While the port will typically be 80 (http) or 443 (https), the outbound port may be different if the WebServiceURL is served on a custom port.

### Queues

The queues indicated in the `RequestMonitorQueue`, `SuccessRouteQueue`, and `ErrorRouteQueue` settings must all be created. The default queues use 2 custom queues that must be created before enabling the addon: `Awaiting ILS Data Import` and `Awaiting Manual Data Import`.

The suggested state code for the queue indicated in the `RequestMonitorQueue` setting is _Submitted by User_.

The suggested state code for the queue indicated in the `ErrorRouteQueue` setting is _Awaiting Request Processing_.

> *Note:* After creating new queues a restart of the Aeon System Manager may be required for the addon to see to see the new queues.

## Routing Rules

While not required, a routing rule helps ensure that the addon will import data for all requests submitted by users.

*Sample Routing Rule*: The following sample rule will move requests from _Submitted by User_ to _Awaiting ILS Data Import_ when the ReferenceNumber is not null or blank and the request has not already been routed to the `RequestMonitorQueue`. Checking for the null/blank ReferenceNumber helps to skip processing by the addon for requests that already have barcode information supplied. Make the appropriate match string changes if using different field(s) for `BarcodeDestinationField`.

**Status**: _Submitted by User_

**New Status**: _Awaiting ILS Data Import_

**Match String**: ISNULL(t.ReferenceNumber, '') = '' AND t.TransactionNumber NOT IN (SELECT DISTINCT TransactionNumber FROM Tracking WHERE ChangedTo = _ID Of RequestMonitorQueue_ AND ChangedDate >= t.CreationDate)

**Description**: Route all requests submitted by user with a CallNumber to the _Awaiting ILS Data Import_ queue for data input.

## Settings

### RequestMonitorQueue

The queue that the addon will monitor for transactions that need ILS data automatically imported from Symphony. The value of this setting is required.

*Default*: _Awaiting ILS Data Import_

### SuccessRouteQueue

The queue that the addon will route requests to after successfully importing ILS data from Symphony. The value of this setting is required.

*Default*: _Awaiting Request Processing_

### ErrorRouteQueue

The queue that the addon will route requests to if errors are encountered while importing ILS data from Symphony. The value of this setting is required.

*Default*: _Awaiting Manual Data Import_

### SymphonyWebServiceUrl

Base URL for the Symphony Web Service. The value of this setting is required.

*Example*: _https://{YourDomain}/cgi-bin/aeonItem.pl?_

### LookupSourceField

Specifies the transaction field that contains the Symphony record's Call Number. The value of this setting is required and must match the name of a column from the Transactions table. A second column may be specified in the lookup source in cases where an item's callnumber also contains a location. For these cases add a space between column names `CallNumber Location`

*Default*: _CallNumber_

### LocationDestinationField

Specifies the transaction field where the location information for the transaction should be stored. The value of this setting is optional. If specified, the value of this setting must match the name of a column from the Transactions table.

*Default*: _Location_

### ShelfLocationDestinationField

Specifies the transaction field where the shelf location information for the transaction should be stored. The value of this setting is optional. If specified, the value of this setting must match the name of a column from the Transactions table.

*Default*: _SubLocation_

### BarcodeDestinationField

Specifies the transaction field where gathered barcode information should be stored. The value of this setting is optional. If specified, the value of this setting must match the name of a column from the Transactions table.

*Default*: _ReferenceNumber_

## Workflow Summary

The addon watches the transaction queue specified by the RequestMonitorQueue addon setting. When the addon detects that there are transactions present in the queue, it will grab the call number from the transaction. Using the call number, the addon will place a request on the Symphony Web Service and take the first result returned from the pipe-delimited record. Then, it will input the barcode and location into the specified fields. Note that all imported values will be trimmed of all leading and trailing spaces. If there is an error during the process, the transaction will be routed to the queue specified in the `ErrorRouteQueue` setting.

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
