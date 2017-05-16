local request = require "ant.request"

local function setCacheInfo()
    function getCacheKey()
        bitrate = ngx.var.arg_bitrate or ""
        local key = ngx.var.host .. ngx.var.uri .. bitrate
        ngx.var.ant_consistent_key = key
        return key
    end

    ngx.req.set_header("X-Cache-Key", getCacheKey())
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

    -- set cache key for uce
    setCacheInfo()

    -- do redirect
    request.antRedirect()

end

doAccess()
