local frame = require "ant.frame"
local request = require "ant.request"

local blocklist = "blocklist"
local limitlist = "limitlist"

local function filterByRedis()
    local blocklist = "blocklist_" .. ngx.var.host
    local limitlist = "limitlist_" .. ngx.var.host

    local blockshm = "ipblockshm"
    local limitshm = "urllimitshm"

    local redis = require "ant.redis"
    local red = redis:new()

    red:set_timeout(2000)

    -- get ip block table
    local res, err = red:hget(blocklist, ngx.var.http_x_remote_addr, blockshm)
    if not res then
        ngx.log(ngx.INFO, err)
        red:close()
        return false
    end

    if res ~= ngx.null then
        red:close()
        ngx.exit(401)
    end

    -- get limit rate
    local resall, err = red:hkeys(limitlist, limitshm)
    if not resall then
        ngx.log(ngx.INFO, err)
        red:close()
        return false
    end

    for i = 1, #resall, 1 do
        if string.match(ngx.var.uri, resall[i]) then
            local limitRate = red:hget(limitlist, resall[i], limitshm)
            if limitRate then
                ngx.var.limit_rate = limitRate
            end
            break
        end
    end

    red:close()
    return true
end

local function doAccess()
    -- init request, set var label, set session id
    request.initRequest()

    ngx.header["X-Request-Uri"] = ngx.var.request_uri

    -- set upstream to uce
    if ngx.req.get_method() == "PURGE" then
        request.getPurgeUpstream()
        return
    end

    -- do auth request
    request.authRequest()

    -- do redirect
    request.antRedirect()

    -- if request.isFirstNode() then
        -- user block and url limit rate by redis
        -- filterByRedis()
    -- end
end

doAccess()
