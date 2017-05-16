local request = require "ant.request"

local function setCacheInfo()
    ngx.req.set_header("X-Cache-Division", "mgtv-ottvideost.hifuntv.com")
    local arange, muri = string.match(string.sub(ngx.var.uri, 35), "^%x+%-?(%d-)(/.+)")
    if not muri then
        return
    end

    ngx.req.set_header("X-Cache-Key", ngx.var.host .. muri .. arange)
    ngx.var.ant_consistent_key = ngx.var.host .. muri .. arange
end

local function UserAgentFilter()
    local useragent = ngx.var.http_user_agent
    if useragent == nil or not useragent or useragent == "-" then
        ngx.exit(ngx.HTTP_FORBIDDEN)
        return
    end
end

local function requestFilter()
    if string.match(ngx.var.uri, "%.hb$") then
        ngx.exit(ngx.HTTP_OK)
    end
    if string.match(ngx.var.uri, "%.sb$") then
        ngx.exit(ngx.HTTP_OK)
    end
end

local function doAccess()
    -- init request, set var label, set session id
    request.initRequest()

    ngx.header["X-Request-Uri"] = ngx.var.request_uri

    -- set cache info for uce
    setCacheInfo()

    -- set upstream to uce
    if ngx.req.get_method() == "PURGE" then
        request.getPurgeUpstream()
        return
    end

    -- .hb file filter
    requestFilter()

    -- forbidden nil useragent access
    UserAgentFilter()

    -- do auth request
    request.authRequest()

    -- do redirect
    request.antRedirect()

    -- do select upstream
    request.selectUpstream({})
end

doAccess()

