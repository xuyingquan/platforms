local balancer = require "ngx.balancer"
local hc = require "ant.healthcheck"

local _M = {}

local function chooseServers( upstream )

    local server  = nil

    local index   = upstream.index
    if not index or index == "" or index < 0 then
        upstream.index = 1
        index          = 1
    end

    if index > #upstream.subNames then
        return nil
    end

    server = upstream.servers[upstream.subNames[index]]
    if not server or not next(server) then
        return nil
    end

    if upstream.currentPeer and upstream.currentPeer > #server then
        upstream.currentPeer = nil
    end

    return server
end

local function checkDown( upstream, servers, peer )

    hc.update_peer_down_status(upstream.name, upstream.subNames[upstream.index], peer)

    local timeNow     = ngx.time()

    local failTime    = servers[peer].failTime
    local checkedTime = servers[peer].checkedTime
    local failTimeOut = servers[peer].failTimeOut or 30

    if failTime and failTime + failTimeOut <= timeNow then

        servers[peer].fails   = 0
        servers[peer].failTime = nil

        return true
    end

    if not servers[peer].down or servers[peer].down == false then
        if checkedTime and checkedTime + failTimeOut <= timeNow then
            servers[peer].fails = 0
        end

        if servers[peer].fails and servers[peer].fails >= (servers[peer].maxFails or 1) then
            return false
        end

        return true
    end

    return false
end

local function roundWeightPolicy( upstream )

    local servers = chooseServers(upstream)
    if not servers then return -1 end

    local totalWeight = 0

    local peer = upstream.currentPeer or 0
    if peer < 0 or peer > #servers then peer = 0 end

    local status = false

    for i = 1, #servers, 1 do

        local checked = checkDown(upstream, servers, i)

        if checked == true then

            status = true

            if not servers[i].weight then servers[i].weight = 1 end
            if not servers[i].effectiveWeight then servers[i].effectiveWeight = servers[i].weight end
            servers[i].currentWeight = (servers[i].currentWeight or 0) + servers[i].effectiveWeight

            totalWeight = totalWeight + servers[i].effectiveWeight

            if servers[i].effectiveWeight < servers[i].weight then
                servers[i].effectiveWeight = servers[i].effectiveWeight + 1
            end

            if peer < 1 or (servers[i].currentWeight or 0) > (servers[peer].currentWeight or 0) then
                peer = i
            end
        end
    end

    if status == false then

        upstream.index = (upstream.index or 0) + 1
        upstream.currentPeer = nil

        peer = roundWeightPolicy(upstream)
    else
        servers[peer].currentWeight = servers[peer].currentWeight - totalWeight
        servers[peer].checkedTime   = ngx.time()

        upstream.currentPeer        = peer
    end

    return peer

end

local function roundPolicy( upstream )

    local servers = chooseServers(upstream)
    if not servers then return -1 end

    local peer = ngx.ctx.lastPeer or 0

    if peer < 0 or peer > #servers then peer = 0 end

    peer = (peer % #servers) + 1

    local count = 0

    while servers[peer].down == true do
        peer = (peer % #servers) + 1
        count = count + 1
        if count >= #servers then break end
    end

    if count >= #servers then

        upstream.index = (upstream.index or 0) + 1
        upstream.currentPeer = nil

        peer = roundWeightPolicy(upstream)
    else
        servers[peer].checkedTime   = ngx.time()
    end

    return peer

end

local function handleFails( upstream )

    local servers = chooseServers(upstream)
    if not servers then return false end

    local lastPeer = ngx.ctx.lastPeer

    if not lastPeer or lastPeer < 1 or lastPeer > #servers then return false end

    local name, status = balancer.get_last_failure()
    if name then

        servers[lastPeer].fails = (servers[lastPeer].fails or 0) + 1

        if servers[lastPeer].fails >= (servers[lastPeer].maxFails or 1) then

            local effectiveWeight = (servers[lastPeer].weight or 1) - math.floor((servers[lastPeer].weight or 1) / (servers[lastPeer].maxFails or 1))

            if effectiveWeight < 0 then effectiveWeight = 0 end
            servers[lastPeer].effectiveWeight = effectiveWeight

            servers[lastPeer].failTime = ngx.time()

            hc.set_peer_down(upstream.name, upstream.subNames[upstream.index], lastPeer, true)
        end
    end
end

function _M.getUpstreamPeer( upstream )

    if not upstream or not next(upstream) then
        return nil, nil
    end

    if not ngx.ctx.lastPeer then
        upstream.index = 1
        upstream.currentPeer = nil
    end

    handleFails(upstream)

    local peer

    if not ngx.ctx.lastPeer then
        peer = roundWeightPolicy(upstream)
    else
        peer = roundPolicy(upstream)
    end

    ngx.ctx.lastPeer = peer

    local servers = chooseServers(upstream)
    if not servers then return nil, nil end

    if peer < 1 or peer > #servers then
        ngx.log(ngx.ERR, "get upstream peer failed!")
        return nil, nil, nil
    end

    return servers[peer].host, servers[peer].port, servers[peer].https
end

return setmetatable(_M, { __index = balancer })
