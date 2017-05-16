local lfs = require("lfs")
local io = require("io")
local os = require("os")

local new_timer = ngx.timer.at

local purgeRoot = ""
local purgeServer = {}

local failedRetryTimes  = 5
local failedRetryRate   = 30

local purgeThreshold    = 10
local purgeTimes        = 0
local purgeSleep        = 0.01

local retryTimes = {30, 90, 300, 600, 1800}

local function sendPurgeRequest( addr, port, req )

    if purgeTimes >= purgeThreshold then
        ngx.sleep(purgeSleep)
        purgeTimes = 0
    end
    purgeTimes = purgeTimes + 1

    local sock, err = ngx.socket.tcp()
    if not sock then
        ngx.log(ngx.ERR, "Ant Controlor socket error !!")
        return nil
    end

    sock:settimeout(3000)
    ok, err = sock:connect(addr, port)
    if not ok then
        sock:close() 
        ngx.log(ngx.ERR, "Ant Controlor connect error !!")
        return nil
    end

    local bytes, err = sock:send(req)
    if not bytes then
        sock:close() 
        ngx.log(ngx.ERR, "Ant Controlor send error !!")
        return nil
    end

    local status_line, err = sock:receive()
    if not status_line then
        sock:close() 
        ngx.log(ngx.ERR, "Ant Controlor receive error !!")
        return nil
    end

    sock:close() 

    status = string.match(status_line, "^HTTP%S+%s+(%d+)%s+")
    if not status then
         ngx.log(ngx.ERR, "Purge Responst Error!! ", status_line)
        return nil
    end

    if tonumber(status) ~= 200 then 
        ngx.log(ngx.ERR, "Purge Response Status " .. status .. " Error !!" )
        return nil, status
    end

    return true
end

local function walkTree (path, callback)
    local ok, iter, entries = pcall(lfs.dir, path)
    if not ok then return false end

    for file in iter, entries do
        if file ~= "." and file ~= ".." and file ~= "tmp.list" then
            local f = path..'/'..file
            local attr = lfs.attributes (f)
            if attr then
                if attr.mode == "directory" then
                    walkTree (f, callback)
                elseif attr.mode == "file" then
                    callback (f)
                end
            end
        end
    end
    return true
end

local function recordFailedPurge(ptype, line, ts, err)
    local fileName = purgeRoot .. "/" .. ptype .. "/bak/failed.list"

    local file = io.open(fileName, "a")
    if not file then
        ngx.log(ngx.CRIT, "Purge Record failed ! type: ", ptype .. " line: " .. line)
        return
    end

    local timeNow  = os.date("%Y/%m/%d %X")
    local sendTime = os.date("%Y/%m/%d %X", ts)
    local errMsg   = timeNow .. "|" .. sendTime .. "|" .. line .. "|" .. err .. "\n"

    file:write(errMsg)
    file:close()
end

local function retryFailedPurge(ptype, line, name, ts, num)
    local fileName = purgeRoot .. "/" .. ptype .. "/bak/" .. name 

    local file = io.open(fileName, "a")
    if not file then
        ngx.log(ngx.CRIT, "Purge Retry failed !!! type: " .. ptype .. " line: " .. line)
        return
    end

    file:write(line .. "|" .. ts .. "|" .. num .. "\n")
    file:close()
end

local function parsePurgeLine(purgeLine)

    local line, host, url, sendTs, num
    local tempLine

    local pos = string.find(purgeLine, "|")
    if pos == nil then
        line = purgeLine
        num  = 0 
    else
        line = string.sub(purgeLine, 1, pos - 1)
        tempLine = string.sub(purgeLine, pos + 1)

        pos = string.find(tempLine, "|")
        if pos ~= nil then
            sendTs = string.sub(tempLine, 1, pos - 1)
            num    = string.sub(tempLine, pos + 1)
        end
        if num == nil or num == "" then
            num = 0 
        end 
    end 

    local pos = string.find(line, "/")
    if pos ~= nil and pos > 1 then
        url  = string.sub(line, pos)
        host = string.sub(line, 1, pos - 1)
    end 

    num = tonumber(num) + 1
    return line, host, url, sendTs, num 

end

local function purgeRetryHandler(path, callback)
    local ok, iter, entries = pcall(lfs.dir, path)
    if not ok then return false end

    for file in iter, entries do
        if file ~= "." and file ~= ".." and file ~= "failed.list" and file ~= "tmp.list" then
            local f = path .. "/" .. file
            local attr = lfs.attributes(f)
            if attr then
                if attr.mode == "directory" then
                    purgeRetryHandler(f, callback)
                elseif attr.mode == "file" then

                    local fileTime = tonumber(file)
                    local timeNow  = ngx.time()
                    if timeNow >= fileTime then
                        callback(f)
                    end
                end
            end
        end
    end
    return true
end

local function judgePurgeLine(status, retryTimes)

    if status == nil or status == "" then
        return nil
    end

    if retryTimes > failedRetryTimes then
        return "beyond retry times"
    end

    local banStatus = {"403"}
    for i = 1, #banStatus do
        if (status == banStatus[i]) then
            return status
        end
    end

    return nil

end

local function processPurgeList( filename )
    
    local ptype, opt, ts = string.match(filename, "(%a+)/+(%a+)/+(%d+)")
    if not (ptype or opt or ts) then return false end

    local timeNow = ngx.time()
    if tonumber(ts) > timeNow then ts = timeNow end

    local file = io.open(filename, "r")
    if not file then return false end

    for purgeLine in file:lines() do
        local line, host, url, sendTs, num = parsePurgeLine(purgeLine)

        local retryFileName = ts
        if num <= failedRetryTimes then
            retryFileName = retryFileName + retryTimes[num]
        end

        if sendTs == nil or sendTs == "" then
            sendTs = ts
        end

        local param = "ts=" .. sendTs .. "; type=" .. ptype .. "; opt=add"

        if host == nil or host == "" or url == nil or url == "" then 
            ngx.log(ngx.ERR, "file: " .. filename .. " line: " .. line .. " parse error !!")
            recordFailedPurge(ptype, line, sendTs, "parse error")
        else

            local req = "PURGE " .. url .." HTTP/1.1\r\nHost: " .. host .. "\r\nConnection: close\r\nX-Purge-Param: " .. param .. "\r\nUser-Agent: Ant Controlor\r\n\r\n"
            local result, status = sendPurgeRequest(purgeServer.addr, purgeServer.port, req)
            if not result then 
                ngx.log(ngx.ERR, "file: " .. filename .. " line: " .. line .. " purge request send error !!")

                local errMsg = judgePurgeLine(status, num)
                if errMsg ~= nil and errMsg ~= "" then
                    recordFailedPurge(ptype, line, sendTs, errMsg)
                else
                    retryFailedPurge(ptype, line, retryFileName, sendTs, num)
                end
            else
                ngx.log(ngx.WARN, "file: " .. filename .. " line: " .. line .. " purge request send ok, the purge result in uce's error.log !!")
            end
        end
    end
    file:close()
    os.remove(filename)
end

local _M = {}

local function do_purge(ctx)

    walkTree (purgeRoot .. "/file/new/", processPurgeList)
    walkTree (purgeRoot .. "/prefix/new/", processPurgeList)

end

local function purge(ctx)
    local ok, err = pcall(do_purge, {})
    if not ok then 
        ngx.log(ngx.CRIT, err)
    end
    local ok, err = new_timer(1, purge, {})
end

local function do_purgeRetry(ctx)

    purgeRetryHandler(purgeRoot .. "/file/bak/", processPurgeList)
    purgeRetryHandler(purgeRoot .. "/prefix/bak/", processPurgeList)

end

local function purgeRetry(ctx)

    local ok, err = pcall(do_purgeRetry, {})
    if not ok then
        ngx.log(ngx.CRIT, err)
    end

    local ok, err = new_timer(failedRetryRate, purgeRetry, {})

end

function _M.run(ctx)
    local addr, port = string.match(ctx.purgeServer, "(%d+%.%d+%.%d+%.%d+):(%d+)$")
    purgeServer.addr = addr or ctx.purgeServer
    purgeServer.port = tonumber(port or "80")
    purgeRoot = ctx.purgeRoot or ngx.config.prefix() .. "/purge"

    os.execute("mkdir -p " .. purgeRoot .. "/file/new/") 
    os.execute("mkdir -p " .. purgeRoot .. "/prefix/new/") 
    os.execute("mkdir -p " .. purgeRoot .. "/file/bak/") 
    os.execute("mkdir -p " .. purgeRoot .. "/prefix/bak/") 

    local ok, err = new_timer(0, purge, {})
    local ok, err = new_timer(0, purgeRetry, {})
end

return _M
