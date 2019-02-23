# JSON Shifts are only available from 2010 onwards
using Cascadia
using Gumbo
using HTTP
import JSON

include("shared.jl")

function get_pbp(game_id::String)::Dict{String, Any}
    request = HTTP.request("GET", "http://statsapi.web.nhl.com/api/v1/game/2016020475/feed/live")
    response = String(request.body)
    return JSON.parse(response)
end

function get_teams(response::Dict{String, Any})::Dict{Symbol, String}
    return Dict{Symbol, String}(
        :home => uppercase(response["gameData"]["teams"]["home"]["name"]),
        :away => uppercase(response["gameData"]["teams"]["away"]["name"])
    )
end

function event_type(event_desc::String)::Union{Symbol, Nothing}
    EVENTS = Dict{String, Symbol}(
        "PERIOD_START" => :PSTR,
        "FACEOFF" => :FAC,
        "BLOCKED_SHOT" => :BLOCK,
        "GAME_END" => :GEND,
        "GIVEAWAY" => :GIVE,
        "GOAL" => :GOAL,
        "HIT" => :HIT,
        "MISSED_SHOT" => :MISS,
        "PERIOD_END" => :PEND,
        "SHOT" => :SHOT,
        "STOP" => :STOP,
        "TAKEAWAY" => :TAKE,
        "PENALTY" => :PENL,
        "EARLY_INT_START" => :EISTR,
        "EARLY_INT_END" => :EIEND,
        "SHOOTOUT_COMPLETE" => :SOC,
        "CHALLENGE" => :CHL,
        "EMERGENCY_GOALTENDER" => :EGPID
    )
    event = [EVENTS[e] for e in keys(EVENTS) if occursin(e, event_desc)]
    return length(event) > 0 ? event[1] : nothing
end

function create_missing_columns(play_dict::Dict{Symbol, Any}, event::Dict{String,Any})
    N = "players" in keys(event) ? length(event["players"]) : 1
    # There are at most three events...
    MAX_N::Int8 = 4

    for i in range(N, MAX_N)
        play_dict[Symbol("p$(i)_name")] = nothing
        play_dict[Symbol("p$(i)_id")] = nothing
    end
end

function parse_event(event::Dict{String, Any})::Dict{Symbol, Any}
    play = Dict{Symbol, Any}()
    play[:event_id] = event["about"]["eventIdx"]
    play[:period] = event["about"]["period"]
    play[:event] = event_type(uppercase(event["result"]["eventTypeId"]))
    play[:time_elapsed] = convert_to_seconds(event["about"]["periodTime"])

    # If an event occured on the play, then that means an event occured on the play
    if "players" in keys(event)
        for i in eachindex(event["players"])
            if event["players"][i]["playerType"] !== "Goalie"
                play[Symbol("p$(i)_name")] = uppercase(event["players"][i]["player"]["fullName"])
                play[Symbol("p$(i)_id")] = string(event["players"][i]["player"]["id"])
            end
        end
    end

    # All rows need to have the same exact number of columns. So this just zeros
    # them out if they don't exist (or if the event only has one player for instance)
    create_missing_columns(play, event)

    try
        play[:xC] = event["coordinates"]["x"]
        play[:yC] = event["coordinates"]["y"]
    catch
        play[:xC] = nothing
        play[:yC] = nothing
    end

    return play
end


function parse_json(response::Dict{String, Any})::DataFrame
    plays = response["liveData"]["plays"]["allPlays"]
    events = [parse_event(play) for play in plays]
    # Filter out events that are not common with the HTML PBP
    filter!(e -> e[:event] !== nothing, events)
    df = convert_dict_to_dataframe(events)
    sort!(df, (:event_id), rev=(false))
    return df
end

###############################

response = get_pbp("foobar")
println(get_teams(response))

x = parse_json(response)
