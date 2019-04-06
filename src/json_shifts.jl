# JSON Shifts are only available from 2010 onwards
module JSON_Shifts

import JSON

include("shared.jl")

function get_shifts(game_id::AbstractString)
    request = HTTP.request("GET", "http://www.nhl.com/stats/rest/shiftcharts?cayenneExp=gameId=$game_id")
    response = String(request.body)
    return JSON.parse(response)
end

function parse_shift(shift::Dict{String, Any})
    shift_dict = Dict{Symbol, Union{String, Int64}}()
    name = shift["firstName"] * " " * shift["lastName"]
    shift_dict[:player] = name
    shift_dict[:player_id] = shift["playerId"]
    shift_dict[:period] = shift["period"]
    shift_dict[:team] = shift["teamAbbrev"]

    # At the end of the json they list when all the goal events happened. They are the only one"s which have their
    # eventDescription be not null
    if shift["eventDescription"] == nothing
        shift_dict[:start] = convert_to_seconds(shift["startTime"])
        shift_dict[:end] = convert_to_seconds(shift["endTime"])
        shift_dict[:duration] = convert_to_seconds(shift["duration"])
    else
        shift_dict = Dict{Symbol, Union{String, Int64}}()
    end

    return shift_dict
end


function parse_json(shift_json::Dict{String, Any}, game_id::String)
    shifts = [parse_shift(shift) for shift in shift_json["data"]]
    filter!(s -> !isempty(s), shifts)
    println(shifts)
    println(typeof(shifts))
    df = convert_dict_to_dataframe(shifts)
    df[:game_id] = String(game_id)[6:end]
    sort!(df, (:period, :start), rev=(false, false))
    return df
end

function scrape_shifts(game_id::AbstractString)
    shift_json = get_shifts(game_id)
    return parse_json(shift_json, game_id)
end

end
