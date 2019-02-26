using Cascadia
using Gumbo
using HTTP
using DataFrames

include("shared.jl")

###############################################################################
#    _  _  _____  __  __  _       ___  ___  ___
#   | || ||_   _||  \/  || |     | _ \| _ )| _ \
#   | __ |  | |  | |\/| || |__   |  _/| _ \|  _/
#   |_||_|  |_|  |_|  |_||____|  |_|  |___/|_|
#   ##########################################################################
#
# TABLE OF CONTENTS
#   1. Data Structures
#   2. Extract Game Details
#       i) Team Names
#      ii) Game Status (scheduled, live, final)
#   3. Parsing Non-Event Columns of Event
#       i) Strength
#      ii) Elapsed Time in Period
#   4. Extract Event Team, Zone and Home-Oriented Zone from Event String
#       i) Extract the event's main team
#      ii) Extract the zone the play occured in for the team described
#     iii) Extract the zone the play occured in, relative to the home team
#   5. All Player Related Methods
#       i) Extract players on ice from html into our Player namedtuple data structure
#      ii) Return a dictionary of player names and the goalie name to add to the event string
#     iii) Search for a player by number in our Game object's player list
#      iv) Add an array of players to the Game object's player list if they aren't already there
#   6. Parse The Different Types of Events That Can Be Described in an Event String
#       i) Faceoffs
#      ii) Shot, Miss, Takeaways, Giveaways
#     iii) Hits
#      iv) Blocks
#       v) Goals
#      vi) Penalties
#   7. Increment Score if a Goal Was Scored
#   8. Scraping & Main Methods

###############################################################################
# Data Structures
###############################################################################

const Player = Tuple{String, Symbol, Int8}
const Nullable{T} = Union{T, Nothing}

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

function extract_strength(strength::String, home_players::Array{Player}, away_players::Array{Player})::Nullable{Symbol}
    if home_players == nothing || away_players == nothing ||
        (length(home_players) == 0 && length(away_players) == 0)
        return Symbol(strength)
    end
    home = [1 for plyr in home_players if plyr[2] != :goalie]
    away = [1 for plyr in away_players if plyr[2] != :goalie]
    return Symbol("$(length(home))x$(length(away))")
end

function extract_elapsed_time(both_times::String)::Int64
    # The time is provided as a total time and elapsed time. THis splits
    # the results into two different strings
    total_time = collect(eachmatch(r"\d*:\d\d", both_times))
    # This extracts the first match, converts it to a string and then extracts
    # the seconds
    return convert_to_seconds(String(total_time[1].match))
end

###############################################################################
# Extract Event Team, Zone and Home-Oriented Zone from Event String
###############################################################################
function extract_event_team(short_event::Symbol, event_long::String)::Nullable{String}
    if short_event in (:GOAL, :SHOT, :MISS, :BLOCK,
         :PENL, :FAC, :HIT, :TAKE, :GIVE)
        return strip(split(event_long, " ")[1])
    end
    return nothing
end

function extract_zone(play_desc::String)::Nullable{Symbol}
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

function get_home_zone(event_short::Symbol, event_team::Nullable{String}, zone::Nullable{Symbol}, game::Game)::Nullable{Symbol}
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
            # try
                name_pos_str = eachmatch(Selector("font"), plyrs[i])[1].attributes["title"]
                name_pos_parts = split(name_pos_str, " - ")
                # Get the player's name
                name = uppercase(name_pos_parts[2])
                # Get the position as a symbol
                pos = Symbol(lowercase(replace(strip(name_pos_parts[1]), " "=>"_")))
                # Get the player's number
                number = parse(Int8, strip(nodeText(plyrs[i])))
                # println("$name\t$pos\t$number")
                push!(players, (name, pos, number))
            # catch BoundsError
                # Some rows don't have players
            # end
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

function get_player_by_num_on_team(team::String, player_num::Int8, game::Game)::Nullable{Player}
    player = nothing
    if team == game.home_team
        player = [p for p in game.home_players if player_num == p[3]]
    else
        player = [p for p in game.away_players if player_num == p[3]]
    end
    if length(player) == 1
        return player[1]
    else
        return nothing
    end
end

function populate_players(players::Array{Player}, team::String, game::Game)
    for player in players
        if team == game.home_team && get_player_by_num_on_team(team, player[3], game) == nothing
            # println("adding player $(player[1]) to the home team")
            push!(game.home_players, player)
        end
        if team == game.away_team && get_player_by_num_on_team(team, player[3], game) == nothing
            # println("adding player $(player[1]) to the away team")
            push!(game.away_players, player)
        end
    end
end

###############################################################################
# Parse The Different Types of Events That Can Be Described in an Event String
#       i) Faceoffs
#      ii) Shot, Miss, Takeaways, Giveaways
#     iii) Hits
#      iv) Blocks
#       v) Goals
#      vi) Penalties
###############################################################################

"""
    parse_fac(event_long, game)

MTL won Neu. Zone - MTL #11 GOMEZ vs TOR #37 BRENT
"""
function parse_fac(event_long::String, event_team::String, game::Game)::Dict{Symbol, Union{String, Int8}}
    regex = eachmatch(r"(.{3})\s+#(\d+)", event_long)
    names = collect(regex)

    # If team that won is the away team (away team is first, home_team is second)
    if event_team == names[1].captures[1]
        p1_num = parse(Int8, names[1].captures[2])
        p1_team = String(names[1].captures[1])
        p2_num = parse(Int8, names[2].captures[2])
        p2_team = String(names[2].captures[1])
    else # if the team that won is the home team
        p1_num = parse(Int8, names[2].captures[2])
        p1_team = String(names[2].captures[1])
        p2_num = parse(Int8, names[1].captures[2])
        p2_team = String(names[1].captures[1])
    end

    p1 = get_player_by_num_on_team(p1_team, p1_num, game)
    p2 = get_player_by_num_on_team(p2_team, p2_num, game)
    return Dict{Symbol, Union{String, Int8}}(:p1_name => p1[1], :p1_num => p1_num,
     :p2_name => p2[1], :p2_num => p2_num)
end

"""
Parse the description field for a: SHOT, MISS, TAKE, GIVE

MTL ONGOAL - #81 ELLER, Wrist, Off. Zone, 11 ft.
ANA #23 BEAUCHEMIN, Slap, Wide of Net, Off. Zone, 42 ft.
TOR GIVEAWAY - #35 GIGUERE, Def. Zone
TOR TAKEAWAY - #9 ARMSTRONG, Off. Zone
"""
function parse_shot_miss_take_give(event_long::String, event_team::String, game::Game)::Dict{Symbol, Union{String, Int8}}
    regex = match(r"(\d+)", event_long)
    p1_num = parse(Int8, regex.captures[1])
    p1 = get_player_by_num_on_team(event_team, p1_num, game)
    return Dict{Symbol, Union{String, Int8}}(:p1_name => p1[1], :p1_num => p1_num)
end

"""
    parse_hit(args)

 MTL #20 O'BYRNE HIT TOR #18 BROWN, Def. Zone
"""
function parse_hit(event_long::String, event_team::String, game::Game)::Dict{Symbol, Union{String, Int8}}
    regex = eachmatch(r"(.{3})\s+#(\d+)", event_long)
    names = collect(regex)
    p1_team = String(names[1].captures[1])
    p1_num = parse(Int8, names[1].captures[2])
    p1 = get_player_by_num_on_team(p1_team, p1_num, game)

    hit_info = Dict{Symbol, Union{String, Int8}}(:p1_name => p1[1], :p1_num => p1_num)

    if length(names) > 1
        p2_team = String(names[2].captures[1])
        p2_num = parse(Int8, names[2].captures[2])
        p2 = get_player_by_num_on_team(p2_team, p2_num, game)
        hit_info[:p2_name] = p2[1]
        hit_info[:p2_num] = p2_num
    end
    return hit_info
end

"""
    parse_block()

MTL #76 SUBBAN BLOCKED BY TOR #2 SCHENN, Wrist, Def. Zone
"""
function parse_block(event_long::String, event_team::String, game::Game)::Dict{Symbol, Union{String, Int8}}
    regex = eachmatch(r"(.{3})\s+#(\d+)", event_long)
    names = collect(regex)
    p1_team = String(names[end].captures[1])
    p1_num = parse(Int8, names[end].captures[2])
    p1 = get_player_by_num_on_team(p1_team, p1_num, game)

    block_info = Dict{Symbol, Union{String, Int8}}(:p1_name => p1[1], :p1_num => p1_num)

    if length(names) > 1
        p2_team = String(names[1].captures[1])
        p2_num = parse(Int8, names[1].captures[2])
        p2 = get_player_by_num_on_team(p2_team, p2_num, game)
        block_info[:p2_name] = p2[1]
        block_info[:p2_num] = p2_num
    end
    return block_info
end

"""
    parse_goal()

    TOR #81 KESSEL(1), Wrist, Off. Zone, 14 ft. Assists: #42 BOZAK(1); #8 KOMISAREK(1)
"""
function parse_goal(event_long::String, event_team::String, game::Game)::Dict{Symbol, Union{String, Int8}}
    regex = eachmatch(r"#(\d+)\s+", event_long)
    names = collect(regex)
    p1_team = String(names[1].captures[1])
    p1_num = parse(Int8, names[1].captures[2])
    p1 = get_player_by_num_on_team(p1_team, p1_num, game)

    goal_info = Dict{Symbol, Union{String, Int8}}(:p1_name => p1[1], :p1_num => p1_num)

    if length(names) >= 2
        p2_team = String(names[2].captures[1])
        p2_num = parse(Int8, names[2].captures[2])
        p2 = get_player_by_num_on_team(p2_team, p2_num, game)
        goal_info[:p2_name] = p2[1]
        goal_info[:p2_num] = p2_num

        if length(names) == 3
            p3_team = String(names[3].captures[1])
            p3_num = parse(Int8, names[3].captures[2])
            p3 = get_player_by_num_on_team(p3_team, p3_num, game)
            goal_info[:p3_name] = p3[1]
            goal_info[:p3_num] = p3_num
        end
    end
    return goal_info
end

"""
 MTL #81 ELLER Hooking(2 min), Def. Zone Drawn By: TOR #11 SJOSTROM
"""
function parse_penalty(event_long::String, event_team::String, game::Game)::Dict{Symbol, Union{String, Int8}}
    up_evlng = uppercase(event_long)

    penalty_info = Dict{Symbol, Union{String, Int8}}()

    # Check if it's a Bench/Team Penalties
    if occursin("BENCH", up_evlng) || occursin("TEAM", up_evlng)
        penalty_info[:p1_name] = "TEAM"
    else #STANDARD PENALTY
        regex = eachmatch(r"(.{3})\s+#(\d+)", event_long)
        names = collect(regex)
        if !isempty(names)
            p1_team = String(names[1].captures[1])
            p1_num = parse(Int8, names[1].captures[2])
            p1 = get_player_by_num_on_team(p1_team, p1_num, game)
            penalty_info[:p1_name] = p1[1]
            penalty_info[:p1_num] = p1_num

            # When there are three the penalty was served by someone else
            # The Person who served the penalty is placed as the 3rd event player
            if length(names) == 3
                p3_team = String(names[2].captures[1])
                p3_num = parse(Int8, names[2].captures[2])
                p3 = get_player_by_num_on_team(p3_team, p3_num, game)

                p2_team = String(names[3].captures[1])
                p2_num = parse(Int8, names[3].captures[2])
                p2 = get_player_by_num_on_team(p2_team, p2_num, game)

                penalty_info[:p2_name] = p2[1]
                penalty_info[:p2_num] = p2_num
                penalty_info[:p3_name] = p3[1]
                penalty_info[:p3_num] = p3_num

            elseif length(names) == 2
                p2_team = String(names[2].captures[1])
                p2_num = parse(Int8, names[2].captures[2])
                p2 = get_player_by_num_on_team(p2_team, p2_num, game)
                penalty_info[:p2_name] = p2[1]
                penalty_info[:p2_num] = p2_num
            end
        end
    end

    return penalty_info
end

################################################################################
# Add Types of Events (i.e. shot type, or penalty type)
################################################################################
function get_penalty_type(event_long::String, game::Game)
    up_evlng = uppercase(event_long)

    # Check if it's a Bench/Team Penalties
    if occursin("BENCH", up_evlng) || occursin("TEAM", up_evlng)
        beg_penl_idx = findfirst("TEAM", up_evlng).stop + 5
        end_pel_idx = findfirst(")", up_evlng).start + 1
        return event_long[beg_penl_idx:end_pel_idx]
    else
        regex = eachmatch(r"(.{3})\s+#(\d+)", event_long)
        names = collect(regex)

        if isempty(names)
            return nothing
        end
        p_team = String(names[1].captures[1])
        p_num = parse(Int8, names[1].captures[2])
        plyr = get_player_by_num_on_team(p_team, p_num, game)

        # Find the player's number and last name specified then use that as the
        # beginning index for the penalty type.
        # Spaces are included to handle Del Zotto for now. May switch to period names
        penalty_type_regex = match(r"(\#\d+\s[A-Z\s]+)", event_long)
        num_name = penalty_type_regex.captures[1]
        # -2 because the index returns the second letter of the name
        # https://regexr.com/493hp
        beg_penl_idx = findfirst(String(num_name), event_long).stop - 2
        end_pel_idx = findfirst("(", event_long).start - 1
        return strip(event_long[beg_penl_idx:end_pel_idx])
    end
end

function get_shot_type(event_long::String, game::Game)
    TYPES = ("wrist", "snap", "slap", "deflected", "tip-in", "backhand", "wrap-around")
    play_parts = [lowercase(strip(x)) for x in split(event_long, ",")]
    for p in play_parts
        if p in TYPES
            if p in ("wrist", "snap", "slap")
                return Symbol("$(p)shot")
            else
                return Symbol(p)
            end
        end
    end

    return nothing
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

    plays = Array{Dict{Symbol, Any}}(undef, 0)
    errored_events = String[]

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

        play[:time_elapsed] = extract_elapsed_time(nodeText(tds[4]))

        event_short = Symbol(nodeText(tds[5]))
        event_long =  nodeText(tds[6])
        play[:event_short] = event_short
        play[:event_long] = event_long
        play[:event_team] = extract_event_team(event_short, event_long)

        play[:event_zone] = extract_zone(event_long)
        play[:home_zone] = get_home_zone(event_short, play[:event_team], play[:event_zone], game)

        away_players = extract_players_on_ice(tds[7])
        home_players = extract_players_on_ice(tds[8])
        play[:num_away_players] = length(away_players)
        play[:num_home_players] = length(home_players)
        merge!(play, extract_player_names(away_players, false))
        merge!(play, extract_player_names(home_players, true))

        populate_players(away_players, game.away_team, game)
        populate_players(home_players, game.home_team, game)

        # play[:strength] = extract_strength(nodeText(tds[3]))
        # Ignore the strength field and manually compute to make home-relative
        play[:strength] = extract_strength(home_players, away_players)
        play[:home_team] = game.home_team
        play[:away_team] = game.away_team
        play[:home_score] = game.home_score
        play[:away_score] = game.away_score

        event_info = nothing
        # Add Event Players
        # Sometimes a player records an event while not being on the ice.
        # This is due to the scorekeeper forgetting to mark them on the ice.
        # To handle these situations, we'll keep track of which ones fail and
        # try adding them again at the end of the game.
        try
            if event_short == :FAC
                # parse faceoff
                event_info = parse_fac(event_long, play[:event_team], game)
            elseif event_short in (:SHOT, :MISS, :GIVE, :TAKE)
                event_info = parse_shot_miss_take_give(event_long, play[:event_team], game)
            elseif event_short == :HIT
                event_info = parse_hit(event_long, play[:event_team], game)
            elseif event_short == :BLOCK
                event_info = parse_block(event_long, play[:event_team], game)
            elseif event_short == :GOAL
                event_info = parse_goal(event_long, play[:event_team], game)
            elseif event_short == :PENL
                event_info = parse_penalty(event_long, play[:event_team], game)
            end
            if event_info != nothing
                merge!(play, event_info)
            end
        catch err
            # When the player does not exist, we get method errors as we try to
            # call a method on a player that does not exist. Let's store these
            # events and throw the remaining ones so we don't catch everything.
            if isa(err, MethodError) || isa(err, BoundsError)
                push!(errored_events, event_long)
            else
                rethrow(err)
            end
        end

        if event_short == :PENL
            play[:type] = get_penalty_type(event_long, game)
        elseif event_short in (:SHOT, :MISS, :GOAL)
            play[:type] = get_shot_type(event_long, game)
        end

        push!(plays, play)
    end
    println(errored_events)
    add_missing_columns!(plays)
    return convert_dict_to_dataframe(plays)
end

println("--------------------------------------------------------------------")
response = get_pbp("fooo")
away_team, home_team = extract_teams(response)
game = Game(home_team, away_team, 0, 0, Player[], Player[])
game_status(response)
df = scrape_pbp(game, response)
println("--------------------------------------------------------------------")
