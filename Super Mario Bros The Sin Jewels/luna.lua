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

function onStart()
    Graphics.setMainFramebufferSize(1280,720)
end

function onCameraUpdate()
    camera.width,camera.height = Graphics.getMainFramebufferSize(1280,720)
end