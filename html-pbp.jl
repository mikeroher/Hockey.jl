using Cascadia
using Gumbo
using HTTP
using DataFrames

include("shared.jl")

###############################################################################
# Data Structures
###############################################################################

const Player = NamedTuple{(:name, :position, :number),Tuple{String, Symbol, Int8}} #Tuple{String, Symbol, Int8}

mutable struct Game
    home_team::String # Short form (e.g. TBL)
    away_team::String # Short form (e.g. TOR)
    home_score::Int16
    away_score::Int16
    home_players::Array{Player}
    away_players::Array{Player}
end

###############################################################################
# Extract Game Details
#   - Team names
#   - Game status
###############################################################################

function extract_teams(response::String)::Tuple{String, String}
    html = parsehtml(response)
    tables = eachmatch(Selector("tr:not(.evenColor)"), html.root)
    # Get the third row
    tds = [eachmatch(Selector("td.bborder"), i) for i in tables]
    filter!(arr -> !isempty(arr), tds)
    # The header row is the first row
    header_row = tds[1]
    away = nodeText(header_row[7])
    function split_strip(name::String)::String
        text = split(name, " ")[1]
        text = strip(text)
        return text
    end
    home = nodeText(header_row[8])
    return split_strip(away), split_strip(home)
end


function game_status(response::String)::Symbol
        html = parsehtml(response)
        divs = eachmatch(Selector("table#GameInfo"), html.root)
        tds = eachmatch(Selector("td"), divs[1])
        status = lowercase(nodeText(tds[end]))

        if occursin("end", status)
            return :intermission
        elseif occursin("final", status)
            return :final
        else
            return :live
        end
end

###############################################################################
# Parsing Non-Event Columns of Event
#   - Strength
#   - Time
###############################################################################

function extract_strength(raw_strength::String)::Symbol
    return Symbol(raw_strength)
end

function extract_elapsed_time(both_times::String)::Int64
    # The time is provided as a total time and elapsed time. THis splits
    # the results into two different strings
    total_time = collect(eachmatch(r"\d*:\d\d", both_times))
    # This extracts the first match, converts it to a string and then extracts
    # the seconds
    return convert_to_seconds(String(total_time[1].match))
end

function extract_event_team(short_event::Symbol, event_long::String)::Union{String, Nothing}
    if short_event in (:GOAL, :SHOT, :MISS, :BLOCK,
         :PENL, :FAC, :HIT, :TAKE, :GIVE)
        return strip(split(event_long, " ")[1])
    end
    return nothing
end

###############################################################################
# Extract Zone and Home-Oriented Zone from Event String
###############################################################################

function extract_zone(play_desc::String)::Union{Symbol, Nothing}
    parts = [strip(s) for s in split(play_desc, ",")]
    zone = [x for x in parts if occursin("Zone", x)]  # Find if list contains which zone
    if isempty(zone)
        return nothing
    end
    zone_str = zone[1]

    if occursin("Off", zone_str)
        return :off
    elseif occursin("Def", zone_str)
        return :def
    elseif occursin("Neu", zone_str)
        return :neu
    end
end

function get_home_zone(event_short::Symbol, event_team::Union{String, Nothing}, zone::Union{Symbol, Nothing}, game::Game)::Union{Symbol, Nothing}
    if zone == nothing
        return nothing
    end

    if (event_team != game.home_team && event_short != :BLOCK) ||
        (event_team == game.away_team && event_short == :BLOCK)
        if zone == :off
            return :def
        elseif zone == :def
            return :off
        else
            return zone
        end
    else
        return zone
    end
end

###############################################################################
# All Player Related Methods
#   - Extract players on ice from html into our Player namedtuple data structure
#   - Return a dictionary of player names and the goalie name to add to the event string
#   - Search for a player by number in our Game object's player list
#   - Add an array of players to the Game object's player list if they aren't already there
###############################################################################

function extract_players_on_ice(player_elm::HTMLElement)::Array{Player}
    team = eachmatch(Selector("td"), player_elm)
    plyrs = [team[i] for i in eachindex(team) if i % 4 != 0]
    players = Player[]
    for i in eachindex(plyrs)
        if i % 3 == 0
            try
                name_pos_str = eachmatch(Selector("font"), plyrs[i])[1].attributes["title"]
                name_pos_parts = split(name_pos_str, " - ")
                # Get the player's name
                name = uppercase(name_pos_parts[2])
                # Get the position as a symbol
                pos = Symbol(lowercase(replace(strip(name_pos_parts[1]), " "=>"_")))
                # Get the player's number
                number = parse(Int8, strip(nodeText(plyrs[i])))
                # println("$name\t$pos\t$number")
                push!(players, Player(name, pos, number))
            catch BoundsError
                # Some rows don't have players
            end
        end
    end
    return players
end
# input is the function above
function extract_player_names(players::Array{Player}, is_home::Bool)::Dict{Symbol, String}
    play = Dict{Symbol, String}()
    side = is_home ? :home : :away
    for i in eachindex(players)
        if players[i][2] != :goalie
            play[Symbol("$(side)_player$(i)_name")] = players[i][1]
        else
            play[Symbol("$(side)_goalie")] = players[i][1]
        end
    end
    return play
end

function get_player_by_num_on_team(team::String, player_num::Int8, game::Game)::Union{Player, Nothing}
    player = nothing
    if team == game.home_team
        player = [p for p in game.home_players if player_num == p[2]]
    else
        player = [p for p in game.home_players if player_num == p[2]]
    end
    if length(player) > 1
        return player[1]
    else
        return nothing
    end
end

function populate_players(players::Array{Player}, team::String, game::Game)
    for player in players
        println(player)
        if team == game.home_team && get_player_by_num_on_team(team, player.number, game) == nothing
            push!(game.home_players, player)
        end
        if team == game.away_team && get_player_by_num_on_team(team, player.number, game) == nothing
            println("adding player $(player.name) to the away team")
            push!(game.away_players, player)
        end
    end
end

###############################################################################
# Parse The Different Types of Events That Can Be Described in an Event String
# 1. Faceofff
###############################################################################

"""
    parse_fac(event_long, game)

MTL won Neu. Zone - MTL #11 GOMEZ vs TOR #37 BRENT
"""
function parse_fac(event_long, event_team, game)
    regex = eachmatch(r"(.{3})\s+#(\d+)", event_long)
    names = collect(regex)
    if event_team == names[1].captures[1]
        p1 = names[1].captures[2]
        p2 = names[2].captures[2]
    else
        p1 = names[2].captures[2]
        p2 = names[1].captures[2]
    end
    return Dict{Symbol, String}(:p1_name => p1, :p2_name => p2)
end

# increment_score_if_goal(event_short, event_team, home_team)
"""
    increment_score_if_goal(event_team::String, home_team::String)
    event_team  ==> indicates which team the event occured for
    home_team   ==> indicates which team is home

    This is the only function that mutates the Score object. Other functions
        only read from it in a serial manner.
"""
function increment_score(event_team::String, game::Game)
    # print(game.home_team, game.away_team, event_team, "\n")
    if event_team == home_team
        game.home_score += 1
    else
        game.away_score += 1
    end
end

function get_pbp(game_id::String)::String
    request = HTTP.request("GET", "http://www.nhl.com/scores/htmlreports/20162017/PL020475.HTM")
    response = String(request.body)
    return response
end

function scrape_pbp(game::Game, response::String)
    html = parsehtml(response)
    trs = eachmatch(Selector("tr.evenColor"), html.root)


    # columns = ['Period', 'Event', 'Description', 'Time_Elapsed', 'Seconds_Elapsed', 'Strength', 'Ev_Zone', 'Type',
    #        'Ev_Team', 'Home_Zone', 'Away_Team', 'Home_Team', 'p1_name', 'p1_ID', 'p2_name', 'p2_ID', 'p3_name',
    #        'p3_ID', 'awayPlayer1', 'awayPlayer1_id', 'awayPlayer2', 'awayPlayer2_id', 'awayPlayer3', 'awayPlayer3_id',
    #        'awayPlayer4', 'awayPlayer4_id', 'awayPlayer5', 'awayPlayer5_id', 'awayPlayer6', 'awayPlayer6_id',
    #        'homePlayer1', 'homePlayer1_id', 'homePlayer2', 'homePlayer2_id', 'homePlayer3', 'homePlayer3_id',
    #        'homePlayer4', 'homePlayer4_id', 'homePlayer5', 'homePlayer5_id', 'homePlayer6', 'homePlayer6_id',
    #        'Away_Goalie', 'Away_Goalie_Id', 'Home_Goalie', 'Home_Goalie_Id', 'Away_Players', 'Home_Players',
    #        'Away_Score', 'Home_Score']
    for row in trs
        tds = eachmatch(Selector("td.bborder"), row)
        play = Dict{Symbol, Any}()
        play[:event_id] = parse(Int32, nodeText(tds[1]))

        try
            play[:period] = parse(Int8, nodeText(tds[2]))
        catch
            play[:period] = 0
        end

        play[:strength] = extract_strength(nodeText(tds[3]))
        play[:time_elapsed] = extract_elapsed_time(nodeText(tds[4]))

        event_short = Symbol(nodeText(tds[5]))
        event_long =  nodeText(tds[6])
        play[:event_long] = event_long
        play[:event_team] = extract_event_team(event_short, event_long)

        play[:event_zone] = extract_zone(event_long)
        play[:home_zone] = get_home_zone(event_short, play[:event_team], play[:event_zone], game)

        if event_short == :FAC
            # parse faceoff
            event_info = parse_fac(event_long, play[:event_team], game)
        elseif event_short in (:SHOT, :MISS, :GIVE, :TAKE)
            # parse shot, miss, take, give
        elseif event_short == :HIT
            # parse hit
        elseif event_short == :BLOCK
        elseif event_short == :GOAL
        elseif event_short == :PENL
        end

        away_players = extract_players_on_ice(tds[7])
        home_players = extract_players_on_ice(tds[8])
        play[:num_away_players] = length(away_players)
        play[:num_home_players] = length(home_players)
        merge!(play, extract_player_names(away_players, false))
        merge!(play, extract_player_names(home_players, true))

        populate_players(away_players, game.away_team, game)
        populate_players(home_players, game.home_team, game)


        play[:home_team] = game.home_team
        play[:away_team] = game.away_team
        play[:home_score] = game.home_score
        play[:away_score] = game.away_score

        println(play)
        if play[:time_elapsed] > 200; break; end
    end
end

println("--------------------------------------------------------------------")
response = get_pbp("fooo")
away_team, home_team = extract_teams(response)
game = Game(home_team, away_team, 0, 0, Player[], Player[])
game_status(response)
scrape_pbp(game, response)
extract_teams(response)
println("--------------------------------------------------------------------")
