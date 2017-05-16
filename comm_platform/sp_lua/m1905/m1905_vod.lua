local request = require "ant.request"

local function setCacheInfo()
    local uri = string.match(ngx.var.uri, "^/[^/]+/[^/]+(/.*)$")
    ngx.req.set_uri(uri)
    ngx.req.set_header("X-Cache-Key", ngx.var.host .. uri)
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

    -- do redirect
    request.antRedirect()

    -- do auth request
    request.authRequest()

    if request.isFirstNode() then
        setCacheInfo()
    end
end

doAccess()

