-------------------------------------------------------------------------------
--           DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
--                   Version 2, December 2004
--
--Copyright (C) 2010 BrainDamage
--Everyone is permitted to copy and distribute verbatim or modified
--copies of this license document, and changing it is allowed as long
--as the name is changed.
--
--           DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
--  TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
--
-- 0. You just DO WHAT THE FUCK YOU WANT TO.
-------------------------------------------------------------------------------


function widget:GetInfo()
  return {
    name      = "Bet Engine",
    desc      = "Handles low level logic for spectator bets",
    author    = "BrainDamage",
    date      = "Dec,2010",
    license   = "WTFPL",
    layer     = 0,
    enabled   = true,
  }
end

------------------------------------------------------------------------------------------------------
--                                               WARNING                                            --
-- DO NOT TOUCH THE VALUES BELOW, YOU THINK YOU COULD CHEAT THAT WAY, BUT IN REALITY THE VALUES ARE --
-- CHECKED IN ALL CLIENTS, SO IF YOU CHANGE ONLY FOR YOURSELF YOU'LL EXPERIENCE SOMETHING SIMILAR   --
-- TO SPRING'S DESYNCS, BUT WITHIN THE BET GAME ONLY                                                --
------------------------------------------------------------------------------------------------------
local MIN_BET_TIME = 5*60 -- seconds
local MAX_BETS_TEAM = 3
local WG_INDEX = "betengine"

-- dynamic data tables, hold infos about bets, scores and other players
local playerBets = {} -- indexed by playerID: {[teamID]={{[1]=time,[2]=time}, [teamID]=... }
local playerScores = {} -- indexed by playerID: {points,won,lost}
local teamBets = {} -- indexed by teamID: {[betTime1]=playerID, [betTime2]=playerID}
local incompatiblePlayers = {} -- {[playerID]=true, [playerID]=true, .. }

local GetTeamList = Spring.GetTeamList
local GaiaTeam = Spring.GetGaiaTeamID()
local GetGameFrame = Spring.GetGameFrame
local GetPlayerInfo = Spring.GetPlayerInfo
local GetTeamInfo = Spring.GetTeamInfo
local SendLuaUIMsg = Spring.SendLuaUIMsg
local GetSpectatingState = Spring.GetSpectatingState
local Echo = Spring.Echo
local mod = math.mod
local min = math.min
local myPlayerID = Spring.GetMyPlayerID()

local function getStartingScore()
    return  #GetTeamList() -2 -- minus one to leave last "survivor" in FFA, and minus another because of gaia
end

local function getMinBetTime()
    local currentframe = GetGameFrame()
    local sumtime = currentframe
    if MIN_BET_TIME >= 0 then
        sumtime = math.min(sumtime, MIN_BET_TIME*30)
    end
    return currentframe + sumtime
end

local function isValidBet(playerID, teamID, betTime)
    local playerScore = scores[playerID]
    local _,betterspectator = GetPlayerInfo(playerID)
    if betterspectator == nil then
        return false, "invalid better playerID"
    end
    if not betterspectator then
        return false, "only spectators can bet"
    end
    local _,_,deadTeam = GetTeamInfo(teamID)
    if deadTeam == nil then
        return false, "betted teamID does not exists"
    end
    if deadTeam then
        return false, "cannot bet on dead teams"
    end
    if betTime > getMinBetTime() then
        return false, "bet time too small"
    end
    if not playerScore then
        playerScores[playerID] = {score=getStartingScore(),won=0,lost=0 }
        playerScore = scores[playerID]
    end
    local currentBets = bets[playerID]
    if not currentBets then
        playerBets[playerID] = {}
        currentBets = playerBets[playerID]
    end
    local teamcurrentbets = teamBets[teamID]
    if not teamcurrentbets then
        teamBets[teamID] = {}
        teamcurrentbets =  teamBets[teamID]
    end
    local betCost = #currentBets +1 -- first bet on the same team costs 1, second 2, etc
    if playerScore[score] < betCost then
        return false, "not enough points to bet"
    end
    -- check if there are already existing bets on the opayer with the same time slot
    if teamcurrentbets[betTime] ~= nil then
        return false, "bet time slot already taken"
    end
    return true
end


local function placedBet(playerID,teamID,betTime)
    if not isValidBet(playerID, teamID, betTime) then
        return
    end
    -- decrement points and save infos
    local playerpersonalbets = playerBets[playerID][teamID]
    local betCost = #playerpersonalbets+1 -- in this case the cost has same value of the index
    playerpersonalbets[betCost] = betTime
    playerBets[playerID][teamID] = playerpersonalbets
    playerScores[playerID].score = playerScores[playerID].score - betCost
    teamBets[teamID][betTime] = playerID
    -- updated exported tables
    local exporttable = WG[WG_INDEX]
    exporttable.playerScores = playerScores
    exporttable.teamBets = teamBets
    exporttable.playerBets = playerBets
    WG[WG_INDEX] = exporttable
end

function widget:TeamDied(teamID)
    local betList = teamBets[teamID]
    if not betList then -- there were no bets on that team
        return
    end
    local currentFrame = GetGameFrame()
    local minValue = nil
    local winnerID = nil
    local prizePoints = #betList -- give 1 point reward for every bet to the winner
    if prizePoints == 0 then -- no bets were made
        return
    end
    for time,better in pairs(betList) do
        local deltavalue = mod(currentFrame-time)
        if not minValue then
            minValue = deltaValue
            winnerID = better
        else
            if deltavalue < minValue then -- find player who got closest
                minValue = min(minValue, deltavalue)
                winnerID = better
            end
        end
    end
    for playerID, scores in pairs(playerScores) do
        -- update score for the winner, set also win/loss count
        if playerID == winnerID then
            --we got a winner!
            playerScores[playerID] = {score=scores.score+prizePoints,won=scores.won+1,lost=scores.lost}
        else
            playerScores[playerID] = {score=scores.score,won=scores.won,lost=scores.lost+1}
        end
    end
    -- update shared table
    WG[WG_INDEX].playerScores = playerScores
    -- check if callback is available, if so use it
    local callback = WG[WG_INDEX].betOverCallback
    if callback then
        callback(teamID, playerID, prizePoints)
    end
end


function widget:RecvLuaMsg(msg, playerID)
    if msg:sub(1,12) == "betsettings " then
        msg = msg:sub(13) -- crop the "betsettings " string
        local spaceposition = msg.find(" ")
        if spaceposition == nil then
            return -- malformed message
        end
        local hisMinBetTime = tonumber(msg:sub(1,spaceposition-1))
        local hisMaxBetCount = tonumber(msg:sub(spaceposition+1))
        if hisMinBetTime ~= MIN_BET_TIME or hisMaxBetCount ~= MAX_BETS_TEAM then
            incompatiblePlayers[playerID] = true
        else
            incompatiblePlayers[playerID] = nil
        end
        -- update shared table
        WG[WG_INDEX].incompatiblePlayers = incompatiblePlayers
        return true
    elseif msg:sub(1,4) == "bet " then
        -- here we receive each player's bets, including our own
        if incompatiblePlayers[playerID] then
            return -- reject bets from players with different settings
        end
        msg = msg:sub(5) -- crop the "bet " string
        local spaceposition = msg.find(" ")
        if spaceposition == nil then
            return -- malformed message
        end
        local teamID = tonumber(msg:sub(1,spaceposition-1))
        local time = tonumber(msg:sub(spaceposition+1))
        placedBet(playerID,teamID,time)
        return true
    else
        return
    end
end


local function placeMyBet(teamID, time)
    if not isValidBet(myPlayerID,teamID,time) then
        return
    end
    SendLuaUIMsg("bet " .. teamID .. " " .. time,"s") -- broadcast to everyone our bet, "s" means spectators only
end

function widget:Initialize()
--[[]    if GetGameFrame() ~= 0 then -- we cannot start collecting data mid-game, shut down
        Echo("betting engine cannot be turned on midgame, you wouldn't see other player's previous bets, shutting down")
        WidgetHandler:RemoveWidget()
        return
    end --]]
    if not GetSpectatingState() then
        -- if we're a player, we would miss betting messages
        WidgetHandler:RemoveWidget()
    end
    -- publish all available API functions and tables in the widget shared table
    local exporttable = {}
    --constant stuff
    exporttable.MIN_BET_TIME = MIN_BET_TIME
    exporttable.MAX_BETS_TEAM = MAX_BETS_TEAM
    -- API functions
    exporttable.getStartingScore = getStartingScore
    exporttable.isValidBet = isValidBet
    exporttable.getMinBetTime = getMinBetTime
    exporttable.placeMyBet = placeMyBet
    -- dynamic data tables
    exporttable.playerScores = playerScores
    exporttable.teamBets = teamBets
    exporttable.playerBets = playerBets
    exporttable.incompatiblePlayers = incompatiblePlayers
    --callback
    exporttable.betOverCallback = nil

    WG[WG_INDEX] = exporttable

    SendLuaUIMsg("betsettings " .. MIN_BET_TIME .. " " .. MAX_BETS_TEAM,"s") -- broadcast to everyone our settings, to ensure we all have the same, "s" means spectators only
end

function widget:Remove()
    WG[WG_INDEX] = nil
end

