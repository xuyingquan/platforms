local frame = require "ant.frame"
local redis = require "resty.redis"
local _M = {}

local function connect(self)
    if self.connected then
        return true, nil
    end

    local res, err = redis.connect(self, frame.env.redis.ip, frame.env.redis.port)
    if not res then
        return res, err
    end

    if frame.env.redis.auth and frame.env.redis.auth ~= "" then
        local res, err = redis.auth(self, frame.env.redis.auth)
        if not res then
            return res, err
        end
    end

    self.connected = true
    return true, nil
end

local function hkeys(self, hlistname, shm)

    local isKeys = "__Is_Keys__"
    local dict
    local removeKeyFlags = function (restab, key) 
        if not restab then
            return
        end
        for i = 1, #restab do
            if restab[i] == key then
                table.remove(restab, i)
                break
            end
        end
    end

    if shm and shm ~= "" then
        dict = ngx.shared[shm]
    end

    if dict then
        local ok, err = dict:get(isKeys)
        if ok then
            local resall, err =  dict:get_keys()
            removeKeyFlags(resall, isKeys)
            return resall, err
        end
    end

    local ok, err = connect(self)
    if not ok then
        return nil, err
    end

    local resall, err = redis.hgetall(self, hlistname)
    if not resall then 
        return resall, err
    end

    local keys = {}
    for i = 1, #resall, 2 do
        if dict then
            local ok, err = dict:set(resall[i], resall[i+1], self.interval)
        end
        keys[(i + 1) / 2] = resall[i];
    end
    
    if dict then
        dict:set(isKeys, true, self.interval)
    end

    return keys, nil
end

local function hget(self, hlistname, key, shm)

    local nilFlag = "__nil"
    local dict 

    if shm and shm ~= "" then
        dict = ngx.shared[shm]
        if dict then
            local res, err = dict:get(key)
            if res then
                if res == nilFlag then res = ngx.null end
                return res, err
            end
        end
    end

    local ok, err = connect(self)
    if not ok then
        return nil, err
    end

    local res, err = redis.hget(self, hlistname, key)

    if res and res ~= ngx.null then 
        nilFlag = res
    end

    if dict then
        dict:set(key, nilFlag, self.interval)
    end

    return res, err

end

local function setInterval(self, val)

    if type(val) == "number" then
        self.interval = val
    end

end

function _M.new()

    local o = redis:new()

    o.hget  = hget
    o.hkeys = hkeys
    o.setInterval = setInterval

    o.interval = 10
    o.connected = false

    return o;

end

return _M

