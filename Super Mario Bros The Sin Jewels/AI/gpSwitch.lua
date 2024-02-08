--[[
	Part of GroundPound.lua
	
	By Marioman2007
	GFX by Master of Disaster

	How does it work:
	- Frame 1 is the idle frame.
	- Frame 2 is the frame when a player is on top.
	- Last frame is when the switch is in pressed state.
	- Every frame between frame 2 and the last frame is used in the pressing animation.
	- Must have at least 3 frames.
]]

local npcManager = require("npcManager")
local npcutils = require("npcs/npcutils")
local GP = require("GroundPound")

local switch = {}

switch.idList = {}
switch.idMap = {}

local STATE_NONE = 1
local STATE_STAND = 2
local STATE_PRESSED = 3

local ANIM_DOWN = 1
local ANIM_UP = -1


local function onTop(v, p)
	return p.standingNPC == v and not GP.isPounding(p)
end

local function changeHeight(v, p, h)
	h = h or NPC.config[v.id].height

	local oldH = v.height

	if onTop(v, p) then
		p.y = p.y + (oldH - h)
	end

	v.height = h
	v.y = v.y + (oldH - h)
end

----------------------
-- Custom functions --
----------------------

function switch.register(id)
	npcManager.registerEvent(id, switch, "onTickEndNPC")
	npcManager.registerEvent(id, switch, "onDrawNPC")
	table.insert(switch.idList, id)
	switch.idMap[id] = true
end

function switch.press(v, suppressSound)
	local config = NPC.config[v.id]

	v.data.animType = ANIM_DOWN
	v.data.animActive = true
	
	if config.pressSFX and not suppressSound then
		SFX.play(config.pressSFX, config.pressSFXVol or 1)
	end
end

function switch.reset(v)
	v.data.resetTimer = 0
	v.data.animType = ANIM_UP
	v.data.animActive = true
end

-----------------
-- Main events --
-----------------

function switch.onTickEndNPC(v)
	if Defines.levelFreeze then return end
	
	local data = v.data
	local settings = data._settings
	local config = NPC.config[v.id]

	local p = npcutils.getNearestPlayer(v)
	local cfg = GP.getData(p.idx)

	if not data.initialized then
		data.initialized = true
		data.state = STATE_NONE
		data.hasBeenPressed = false
		data.animActive = false
		data.animTimer = 0
		data.animFrame = 0
		data.animType = ANIM_DOWN
		data.resetTimer = 0
	end

	v.despawnTimer = 180
	settings.resetInterval = settings.resetInterval or 64
	settings.eventName = settings.eventName or ""

	if v:mem(0x12C, FIELD_WORD) > 0 -- Grabbed
	or v:mem(0x136, FIELD_BOOL)     -- Thrown
	or v:mem(0x138, FIELD_WORD) > 0 -- Contained within
	or (not cfg) or v.isHidden      -- Don't wanna take any risks
	then
		return
	end

	-- logic
	if not data.hasBeenPressed and not data.animActive then
		if onTop(v, p) then
			data.state = STATE_STAND
		else
			data.state = STATE_NONE
		end

		if cfg.state == GP.STATE_POUND and Colliders.collide(v, cfg.collider) then
			switch.press(v)
		end
	end

	-- reset behavior
	if settings.reset and settings.resetInterval > -1 and data.hasBeenPressed and not data.animActive then
		data.resetTimer = data.resetTimer + 1

		if data.resetTimer >= settings.resetInterval then
			switch.reset(v)
		end
	end

	-- animation handling
	if not data.animActive then
		v.animationFrame = (data.state ~= STATE_PRESSED and data.state - 1) or (config.frames - 1)
		changeHeight(v, p, config.frameHeights[v.animationFrame + 1])
	else
		data.animTimer = data.animTimer + 1

		if (data.animType == ANIM_DOWN and data.animFrame < (config.frames - 1)) or (data.animType == ANIM_UP and data.animFrame > 0) then
			data.animFrame = math.floor(data.animTimer / (config.framespeed * data.animType)) % config.frames
			changeHeight(v, p, config.frameHeights[data.animFrame + 1])
		else
			data.animActive = false
			data.animTimer = 0

			if data.animType == ANIM_DOWN then
				data.state = STATE_PRESSED
				data.hasBeenPressed = true
				GP.preventPoundJump(p)
				triggerEvent(settings.eventName)
			else
				data.state = STATE_NONE
				data.hasBeenPressed = false
			end
		end

		v.animationFrame = data.animFrame
	end
end

function switch.onDrawNPC(v)
	if v.isHidden or v.despawnTimer <= 0 then return end

	npcutils.drawNPC(v, {sourceX = (v.data.hasBeenPressed and NPC.config[v.id].gfxwidth) or 0})
	npcutils.hideNPC(v)
end

return switch