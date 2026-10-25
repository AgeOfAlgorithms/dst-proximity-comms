-- (the world, on each shard's server) keeps what an admin set with /pc range across saves
local S = require "proxcomms/server"

local Store = Class(function(self, inst)
    self.inst = inst
end)

function Store:OnSave()
    return S.save()
end

function Store:OnLoad(data)
    S.load(data)
end

return Store
