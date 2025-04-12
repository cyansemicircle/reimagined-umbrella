local system = {} 
system.files = {
    propFileName = "chassisProp.dat",
    holograms = "chassisHolograms.dat"
}
local properties = {}
function system:init()
    local file = io.open(self.files.propFileName, "r")
    if file then
        properties = textutils.unserialise(file:read("a"))
        file:close()
    else
        properties = {
            mode = "ChassisControl",
            chassisPower = 0,
            maxPower = 100,
            pid = { p = 1.0, i = 0.1, d = 0.05 },
            lastError = 0,
            integral = 0,
            chassisAngle = 0,   
        }
        self:save()
    end
end

function system:save()
    local file = io.open(self.files.propFileName, "w")
    if file then
        file:write(textutils.serialise(properties))
        file:close()
    end
end


local function getComponent(side)
    return peripheral.wrap(side)
end

local advancedComputer  = getComponent("advanced")  
local engineController  = getComponent("right")  
local holoDisplay       = getComponent("back")  
local vehicleController = getComponent("front")  

local PID = {}
PID.__index = PID

function PID:new(p, i, d)
    local o = { p = p, i = i, d = d, lastError = 0, integral = 0 }
    setmetatable(o, self)
    return o
end

function PID:compute(setpoint, measured, dt)
    local error = setpoint - measured
    self.integral = self.integral + error * dt
    local derivative = (error - self.lastError) / dt
    self.lastError = error
    local output = self.p * error + self.i * self.integral + self.d * derivative
    return output
end

local function getChassisStatus()
    local rpm = engineController.getRPM and engineController.getRPM() or 0
    local angle = properties.chassisAngle 
    return { rpm = rpm, angle = angle }
end


local function getControllerInput()
    local input = vehicleController.getInput and vehicleController.getInput() or {}
    return input
end

local chassis_pid = PID:new(properties.pid.p, properties.pid.i, properties.pid.d)

local function controlChassis(dt)
    local input = getControllerInput()
    
    if input.forward then
        properties.chassisPower = math.min(properties.chassisPower + 1, properties.maxPower)
    elseif input.backward then
        properties.chassisPower = math.max(properties.chassisPower - 1, 0)
    end

    local targetAngle = properties.chassisAngle
    if input.left then
        targetAngle = targetAngle - 5
    elseif input.right then
        targetAngle = targetAngle + 5
    end

    local currentStatus = getChassisStatus()
    local currentAngle = currentStatus.angle

    local pidOutput = chassis_pid:compute(targetAngle, currentAngle, dt)

    local finalPower = properties.chassisPower + pidOutput
    finalPower = math.max(0, math.min(finalPower, properties.maxPower))
    
    if engineController.setPower then
        engineController.setPower(finalPower)
    end

    properties.chassisAngle = currentAngle + pidOutput * dt
    system:save()
end

local function updateHUD()
    local status = getChassisStatus()
    local hudText = string.format("功率: %d%%\n转速: %d rpm\n角度: %.1f°", properties.chassisPower, status.rpm, status.angle)
    if holoDisplay.setDisplayText then
        holoDisplay.setDisplayText(hudText)
    end
end

system:init()

while true do
    local dt = 0.1  
    controlChassis(dt)
    updateHUD()
    if advancedComputer.sleep then
        advancedComputer.sleep(dt)
    else
        os.sleep(dt)
    end
end
