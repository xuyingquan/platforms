local request = require "ant.request"

local function setCacheControl()
    local args = ngx.req.get_uri_args(0)

    if args["avinfo"] ~= nil or args["stat"] ~= nil then
        ngx.header["Cache-Control"] = "no-cache"
        return
    end

    local res = string.match(ngx.var.uri, "537ae9448d9fe3639%.mp4$")
    if res ~= nil and res ~= "" then
        ngx.header["Cache-Control"] = "no-cache"
        return
    end

    local res = string.match(ngx.var.uri, "%.mp4$")
    if res ~= nil and res ~= "" and args["_upv"] ~= nil then
        ngx.header["Cache-Control"] = "no-cache"
        return
    end

end

local function doHeaderFilter()

    request.statusExpire()

    setCacheControl()

end

doHeaderFilter()
