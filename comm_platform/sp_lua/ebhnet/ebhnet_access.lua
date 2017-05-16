local request = require "ant.request"

local function doAccess()
    -- init request, set var label, set session id
    request.initRequest()

    if request.isFirstNode() then
        ngx.header["Access-Control-Allow-Origin"] = "*"
    end

    ngx.header["X-Request-Uri"] = ngx.var.request_uri

    -- set upstream to uce
    if ngx.req.get_method() == "PURGE" then
        request.getPurgeUpstream()
        return
    end

    -- do redirect
    request.antRedirect()

end

doAccess()
