using Cascadia
using Gumbo
using HTTP
using LightXML
using DataFrames

include("shared.jl")

function get_espn_date(date::String)::String
    # input date as YYYYMMDD
    request = HTTP.request("GET", "http://www.espn.com/nhl/scoreboard?date=$date")
    response = String(request.body)
    return response
end

function get_espn_game_id(date::String, home::String, away::String)::Union{String, Nothing}
    # Scrapes the schedule for the day and finds the matching game id
    response = get_espn_date(date)
    game_ids = get_game_ids(response)
    games = get_teams(response)
    for i in eachindex(games)
        if occursin(home, games[i][1]) || occursin(away, games[i][2])
            return game_ids[i]
        end
    end
    return nothing
end

function get_game_ids(response::String)::Array{String}
    # Extract teams for a specific date from the response
    html = parsehtml(response)
    divs = eachmatch(Selector("div.game-header"), html.root)
    ids = []
    for div in divs
        id = String(split(div.attributes["id"], "-")[1])
        push!(ids, id)
    end
    return ids
end

function get_teams(response::String)::Array{Tuple}
    html = parsehtml(response)
    td = eachmatch(Selector("td.team"), html.root)
    teams = []
    for (i, team_el) in enumerate(td)
        team_name = uppercase(nodeText(team_el))
        if length(team_name) < 1
            continue
        end
        push!(teams, team_name)
    end
    # Split the teams array into groups of 2
    return [Tuple(teams[i:i + 1]) for i in 1:2:length(teams)]
end

function event_type(play_desc::String)::Union{Symbol, Nothing}
    EVENTS = Dict{String, Symbol}("GOAL SCORED" => :GOAL, "SHOT ON GOAL" => :SHOT,
    "SHOT MISSED" => :MISS, "SHOT BLOCKED" => :BLOCK, "PENALTY" => :PENL,
    "FACEOFF" => :FAC, "HIT" => :HIT, "TAKEAWAY" => :TAKE, "GIVEAWAY" => :GIVE)
    event = [EVENTS[e] for e in keys(EVENTS) if occursin(e, play_desc)]
    return length(event) > 0 ? event[1] : nothing
end

function parse_event(event::String)::Dict{Symbol,Any}
    info = Dict{Symbol, Any}()
    fields = split(event, "~")
    if fields[5] == "5"
        return Nothing
    end

    info[:xC] = parse(Float16, fields[1])
    info[:yC] = parse(Float16, fields[2])
    info[:time_elapsed] = convert_to_seconds(String(fields[4]))
    info[:period] = String(fields[5])
    info[:event] = event_type(uppercase(fields[9]))
    # event_type("foo")
    return info
end

function parse_espn(espn_xml::String)::DataFrame
    columns = ("period", "time_elapsed", "event", "xC", "yC")
    # Unicode.normalize(espn_xml, stripcc=true, newline2lf=true)
    # TODO: Strip unicode
    xdoc = parse_string(espn_xml)
    xroot = root(xdoc)
    events = child_elements(xroot["Plays"][1])
    plays = [parse_event(content(event)) for event in events]
    # Get rid of plays that are None
    filter!(p -> p[:event] != Nothing, plays)
    # Convert to dataframe (convert every dict to a dataframe and concatenate them)
    return convert_dict_to_dataframe(plays)
end



##########################################
# Test
##########################################
print(parse_event("49~-21~507~0:50~3~3101~0~0~Shot missed by Alex Ovechkin~0~0~2~0~701~23~0~901~43~0~0"))

response = get_espn_date("20190211")
println(get_game_ids(response))
println(get_teams(response))
println(get_espn_game_id("20190211", "PITTSBURGH PENGUINS", "PHILADELPHIA FLYERS"))
df = parse_espn(String(HTTP.request("GET", "http://www.espn.com/nhl/gamecast/data/masterFeed?lang=en&isAll=true&gameId=401045249").body))
