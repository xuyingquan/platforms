local request = require "ant.request"

local function setCacheInfo()
    function getCacheKey()
        local key = "pao.clientdown.sdo.com" .. ngx.var.uri
        ngx.var.ant_consistent_key = key
        return key
    end

    ngx.req.set_header("X-Cache-Key", getCacheKey())
    ngx.req.set_header("X-Cache-Division", "sdo-pao.clientdown.sdo.com")
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

    -- do redirect
    request.antRedirect()

end

doAccess()
