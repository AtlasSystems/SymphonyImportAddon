
-- =========================================================
-- Load settings and .NET Assemblies
-- =========================================================


local Settings = {}
Settings.RequestMonitorQueue = GetSetting("RequestMonitorQueue")
Settings.SuccessRouteQueue = GetSetting("SuccessRouteQueue")
Settings.ErrorRouteQueue = GetSetting("ErrorRouteQueue")

-- Declaring WebServiceUrl here, so it will be globally accessible
Settings.SymphonyWebServiceUrl = nil

Settings.LookupSourceField = GetSetting("LookupSourceField")

Settings.LocationDestinationField = GetSetting("LocationDestinationField")
Settings.BarcodeDestinationField = GetSetting("BarcodeDestinationField")
Settings.ShelfLocationDestinationField = GetSetting("ShelfLocationDestinationField")

luanet.load_assembly("System")
luanet.load_assembly("log4net")
luanet.load_assembly("Mscorlib")


local types = {}
types["System.Type"] = luanet.import_type("System.Type")
types["log4net.LogManager"] = luanet.import_type("log4net.LogManager")


-- =========================================================
-- Main
-- =========================================================


local isCurrentlyProcessing = false

local rootLogger = "AtlasSystems.Addons.Aeon.SymphonyImportAddon";
local log = types["log4net.LogManager"].GetLogger(rootLogger)


function Init ()
    RegisterSystemEventHandler("SystemTimerElapsed", "TimerElapsed")log:Debug("Addon Settings: ")

    -- Setting the WebServiceUrl in Init, so PrepServiceUrl can be called
    Settings.SymphonyWebServiceUrl = PrepServiceUrl(GetSetting("SymphonyWebServiceUrl"))
    LogSettings()

end


function TimerElapsed (eventArgs)
    --[[
        Function that is called whenever the
        system manager triggers server addon
        execution.
    ]]

    if (not isCurrentlyProcessing) then
        isCurrentlyProcessing = true

        local successfulAddonExecution, error = pcall(function()
            ProcessDataContexts("TransactionStatus", Settings.RequestMonitorQueue, "HandleRequests")
        end)

        if not successfulAddonExecution then
            log:Error("Unsuccessful addon execution.")
            log:Error(error.Message or error)
            LogSettings()
        end

        isCurrentlyProcessing = false
    else
        log:Debug("Addon is still executing.")
    end
end

function LogSettings()
    for settingKey, settingValue in pairs(Settings) do
        log:DebugFormat("{0}: {1}", settingKey, settingValue)
    end
end

function PrepServiceUrl(url)
    -- Make sure that a question mark is on the end of the web service url
    if not string.find(url, "?", -1) then
        log:Debug("Appending question mark to web service url")
        url = url .. "?"
    end

    return url
end

-- =========================================================
-- ProcessDataContext functionality
-- =========================================================


function HandleRequests ()
    --[[
        Must be called from a ProcessDataContexts function.
        Runs for every transaction that meets the criteria specified
        by the ProcessDataContexts function.
    ]]

    local transactionNumber = GetFieldValue("Transaction", "TransactionNumber")
    log:DebugFormat("Found transaction number {0} in \"{1}\"", transactionNumber, Settings.RequestMonitorQueue)

    local success, result = pcall(
        function()
            local fieldFetchSuccess, transactionCallNumber = pcall(
                function()
                    local lookupValue = Utility.StringSplit(" ", Settings.LookupSourceField);
                    local transactionCallNumber = nil;

                    if not lookupValue or lookupValue == "" then
                        log:ErrorFormat("Lookup Value from Transaction {0} is empty.", transactionNumber);
                        error({Message = "Lookup Value is empty."});
                    end

                    log:DebugFormat("Lookup Value Count = {0}", #lookupValue);

                    if #lookupValue == 2 then
                        local callNumber = GetFieldValue("Transaction", lookupValue[1]);
                        local location = GetFieldValue("Transaction", lookupValue[2]);

                        if callNumber and location then
                            transactionCallNumber = callNumber .. " " .. location;
                        elseif callNumber then
                            transactionCallNumber = callNumber;
                        end

                    elseif #lookupValue == 1 then
                        transactionCallNumber = GetFieldValue("Transaction", lookupValue[1]);
                    else
                        log:ErrorFormat("Incorrect number of Lookup Values on Transaction {0}.", transactionNumber);
                    end

                    log:DebugFormat("Returning Transaction Call Number: {0}", transactionCallNumber);
                    return transactionCallNumber;
                end
            )

            if not(fieldFetchSuccess) then
                log:ErrorFormat("Error fetching Call Number from Transaction {0}.", transactionNumber)
                error({ Message = "Error fetching Call Number from the Transactions table." })
            end

            log:DebugFormat("Call Number : {0}", transactionCallNumber)
            log:Info("Searching for Symphony records.")

            local success, symphonyRecord = pcall(GetSymphonyRecordByCallNumber,transactionCallNumber);

            if not success then
                error({ Message = symphonyRecord.Message });
            end

			if (symphonyRecord.CallNumber ~= transactionCallNumber) and 
			   (symphonyRecord.CallNumber == nil or transactionCallNumber == nil or string.upper(symphonyRecord.CallNumber) ~= string.upper(transactionCallNumber)) then
                log:ErrorFormat("Call Number from web service ({0}) does not match provided call number ({1})", symphonyRecord.CallNumber, transactionCallNumber)
                error({Message = "Call Number from web service does not match provided call number"});
            end

            if Settings.LocationDestinationField and Settings.LocationDestinationField ~= "" then
                log:Debug("Populating location destination field")

                if (not type(symphonyRecord.Location) == "string") or symphonyRecord.Location == "" then
                    error({ Message = "Cannot populate location from Symphony. Location is either missing or blank." })
                end

                SetFieldValue("Transaction", Settings.LocationDestinationField, symphonyRecord.Location)
                SaveDataSource("Transaction")
            end

            if Settings.BarcodeDestinationField and Settings.BarcodeDestinationField ~= "" then
                log:Debug("Populating barcode destination field")

                if (not type(symphonyRecord.Barcode) == "string") or symphonyRecord.Barcode == "" then
                    error({ Message = "Cannot populate barcode from Symphony. Barcode is either missing or blank." })
                end

                SetFieldValue("Transaction", Settings.BarcodeDestinationField, symphonyRecord.Barcode)
                SaveDataSource("Transaction")
            end

            if Settings.ShelfLocationDestinationField and Settings.ShelfLocationDestinationField ~= "" then
                if ((symphonyRecord.ShelfLocation) and (type(symphonyRecord.ShelfLocation) == "string") and (symphonyRecord.ShelfLocation ~= "")) then
                    log:Debug("Populating shelf location destination field")
                    SetFieldValue("Transaction", Settings.ShelfLocationDestinationField, symphonyRecord.ShelfLocation)
                    SaveDataSource("Transaction");    
                else
                    log:Warn("Cannot populate shelf location from Symphony. Shelf location is either missing or blank.");
                end
            end

            return nil
        end
    )

    if success then
        log:InfoFormat("Addon successfully populated Transaction {0} with data from Symphony", transactionNumber)
        ExecuteCommand("Route", { transactionNumber, Settings.SuccessRouteQueue })

    else
        log:ErrorFormat("Failed to populate transaction {0} with data from Symphony. Routing transaction to \"{1}\".", transactionNumber, Settings.ErrorRouteQueue)
        log:Error(result.Message or result)
        ExecuteCommand("AddNote", { transactionNumber, result.Message or result })
        ExecuteCommand("Route", { transactionNumber, Settings.ErrorRouteQueue })

    end
end

function GetSymphonyRecordByCallNumber(callNumber)

    if ((callNumber == nil) or (callNumber == "")) then
        log:Error("Invalid callnumber");
        error({ Message = "Error getting Symphony Record: Invalid call number" });
    end

    local url = Settings.SymphonyWebServiceUrl .. "callnum=" .. FormatSymphonyQueryString(callNumber);
    log:DebugFormat("Requesting {0} from {1}", callNumber, url);
    local result = WebClient.GetRequest(url, {});
    log:DebugFormat("Web Request Result = {0}", result);

    if not result then
        log:Error("Web request resulted in an error");
        error({ Message = "Web request resulted in an error" });
    end

    local success, record = pcall(ParseWebServiceResult, result);
    if not success then
        log:ErrorFormat("Error getting Symphony Record: {0}", record.Message or record);
        error({ Message = record.Message });
    end

    return record;
end

function FormatSymphonyQueryString(queryString)
    -- Replaces encoded `nbsp;` with `+`
    return string.gsub(Utility.URLEncode(queryString), "%%C2%%A0", "+")
end

function ParseWebServiceResult(result)
    local errorMessage = "invalid call number as input";
    local record = nil;
    local data = Utility.StringSplit('|', result);

    log:DebugFormat("Data's Length = {0}", #data);
    if #data >= 3 then
        log:Debug("Creating record...");
        -- Only taking the first record's data
        record = {
            Barcode = Utility.Trim(data[1]),
            Location = Trim(data[2]),
            CallNumber = Trim(data[3]),
            ShelfLocation = nil;
        };

        log:DebugFormat("Barcode: {0}", record.Barcode);
        log:DebugFormat("Location: {0}", record.Location);
        log:DebugFormat("CallNumber: {0}", record.CallNumber);

        if #data >= 4 then 
            record.ShelfLocation = Trim(data[4]);
            log:DebugFormat("Shelf Location: {0}", record.ShelfLocation);
        else
            log:Warn("Record did not contain Shelf Location");
        end
    elseif data == errorMessage then
        log:Error(errorMessage);
        error({ Message = errorMessage });
    else
        log:ErrorFormat("Web Service result is invalid: {0}", result);
        error({ Message = "Web Service result is invalid: " .. result });
    end

    return record;
end