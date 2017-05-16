local request = require "ant.request"

local function setCacheInfo()
    local key = "meitu-mvvideo11.meitudata.com" .. ngx.var.uri .. ngx.var.is_args .. (ngx.var.args or "")

    ngx.var.ant_consistent_key = key

    ngx.req.set_header("X-Cache-Key", key)
    ngx.req.set_header("X-Cache-Division", "meitu-mvvideo11.meitudata.com")
end

local function doAccess()

    request.initRequest()

    ngx.header["X-Request-Uri"] = ngx.var.request_uri

    setCacheInfo()

    request.authRequest()

    if ngx.req.get_method() == "PURGE" then
        request.getPurgeUpstream()
        return
    end

    if request.isFirstNode() then

        request.selectUpstream({})

        ngx.req.set_header("CDN", "shata")

    end

    request.antRedirect()

end

doAccess()
