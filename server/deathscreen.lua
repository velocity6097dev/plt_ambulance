RegisterNetEvent("amb_server:bleedOut", function()
    local src = source
    Framework.Notify(src, _L("bled_out"), "error")
end)