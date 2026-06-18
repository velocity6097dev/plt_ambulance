-- =============================================================================
-- plt_ambulance | Death Screen – Server
-- Handles the bleed-out event fired by the client when a downed player's
-- bleed-out timer expires with no revive.
-- =============================================================================

-- Fired by the client once the bleed-out countdown reaches zero.
-- Notifies the player with a localised "bled_out" error message.
RegisterNetEvent("amb_server:bleedOut")
AddEventHandler("amb_server:bleedOut", function()
    local src = source
    Framework.Notify(src, _L("bled_out"), "error")
end)
