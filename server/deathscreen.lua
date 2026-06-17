RegisterNetEvent("amb_server:bleedOut", function()
    local src = source
    
    -- Notify the player that they have bled out
    Framework.Notify(src, _L("bled_out"), "error")
end)