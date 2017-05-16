local request = require "ant.request"

local function doAccess()
    -- init request, set var label, set session id
    request.initRequest()

    ngx.header["X-Request-Uri"] = ngx.var.request_uri

    -- set upstream to uce
    if ngx.req.get_method() == "PURGE" then
        request.getPurgeUpstream()
        return
    end

    ngx.req.set_header("ISURE-ADDR", ngx.var.http_x_remote_addr)

    -- do redirect
    request.antRedirect()

end

doAccess()
