
function widget:GetInfo()
  return {
    name      = "Bet Console Frontend",
    desc      = "minimal crappy console frontend for betting",
    author    = "BrainDamage",
    date      = "Dec,2010",
    license   = "WTFPL",
    layer     = 0,
    enabled   = true,
  }
end

WG_INDEX = "betengine"

function placeBet(_,_,parms)
    local spaceposition = parms.find(" ")
    if spaceposition == nil then
        return -- malformed message
    end
    local teamID = tonumber(parms:sub(1,spaceposition-1))
    local time = tonumber(parms:sub(spaceposition+1))
    WG[WG_INDEX].placeMyBet(teamID,time*30)
end

function printbets(_,_,parms)
  local bets = WG[WG_INDEX].teamBets(tonumber(parms))
  for time,playerid in pairs(bets) do
    Spring.Echo("time: " .. time .. " id: " .. playerid)
  end
end

function printscores(_,_,parms)
  local scores = WG[WG_INDEX].playerScores()
  for playerID, score in pairs(scores) do
    Spring.Echo("player " .. playerID .. " score " .. score.score .. " won " .. score.won .. " lost " .. score.lost )
  end
end


function widget:Initialize()
	widgetHandler:AddAction("placebet", placeBet, nil, "t")
	widgetHandler:AddAction("printbets", printbets, nil, "t")
	widgetHandler:AddAction("printscores", printscores, nil, "t")
end

