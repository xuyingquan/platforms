
local function headerFilter()
    if ngx.status == ngx.HTTP_INTERNAL_SERVER_ERROR then
        ngx.status = ngx.HTTP_BAD_GATEWAY
    end
end

headerFilter()
