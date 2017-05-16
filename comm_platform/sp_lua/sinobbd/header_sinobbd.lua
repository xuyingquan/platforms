
local function headFilter()
    ngx.header["Via"] = nil
end

headFilter()
