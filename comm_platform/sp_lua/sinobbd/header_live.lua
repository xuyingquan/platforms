local request = require "ant.request"

local function headFilter()
    if request.isFirstNode() then
        if ngx.var.http_origin then
            ngx.header["Access-Control-Allow-Origin"] = ngx.var.http_origin
        end
    end
end

headFilter()
