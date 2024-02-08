local GP = require("GroundPound")
GP.applyDefaultSettings()

-- example code, feel free to remove
function onEvent(n)
    if n == "switch" then
        Text.showMessageBox("Switch pounded!")
    elseif n == "abc" then
        Text.showMessageBox("You wasted this one time press switch.")
    end
end