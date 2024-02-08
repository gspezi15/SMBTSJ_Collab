--[[
	Part of GroundPound.lua
	See the AI file for more info
]]

local npcManager = require("npcManager")
local ai = require("AI/gpSwitch")

local switch = {}
local npcID = NPC_ID

local switchSettings = {
	id = npcID,

	gfxwidth = 48,
	gfxheight = 48,

	width = 32,
	height = 32,

	frames = 4,
	framespeed = 2,

	npcblock = false,
	npcblocktop = false, --Misnomer, affects whether thrown NPCs bounce off the NPC.
	playerblock = false,
	playerblocktop = true, --Also handles other NPCs walking atop this NPC.

	nohurt=true,
	nogravity = false,
	noblockcollision = false,
	nofireball = true,
	noiceball = true,
	noyoshi= true,
	nowaterphysics = true,

	ignorethrownnpcs = true,
	jumphurt = true, --If true, spiny-like
	spinjumpsafe = false, --If true, prevents player hurt when spinjumping
	harmlessgrab = true, --Held NPC hurts other NPCs if false
	harmlessthrown = true, --Thrown NPC hurts other NPCs if false
	notcointransformable = true,
	luahandlesspeed = true,
	
	grabside=false,
	grabtop=false,

	frameHeights = {34, 32, 30, 26}, -- npc height based on frames
	pressSFX = 32, -- https://docs.codehaus.moe/#/concepts/sfx-list
	pressSFXVol = 1, -- volume should be between 0 and 1
}

npcManager.setNpcSettings(switchSettings)
npcManager.registerHarmTypes(npcID, {}, {});

ai.register(npcID)

return switch