# JSON Shifts are only available from 2010 onwards
using Cascadia
using Gumbo
using HTTP
import JSON

include("shared.jl")

function get_shifts(game_id::String)
    request = HTTP.request("GET", "http://www.nhl.com/stats/rest/shiftcharts?cayenneExp=gameId=2010020001")
    response = String(request.body)
    return JSON.parse(response)
end

function parse_shift(shift)
    shift_dict = Dict{Symbol, Any}()
    name = shift["firstName"] * " " * shift["lastName"]
    shift_dict[:Player] = name
    shift_dict[:Player_Id] = shift["playerId"]
    shift_dict[:Period] = shift["period"]
    shift_dict[:Team] = shift["teamAbbrev"]

    # At the end of the json they list when all the goal events happened. They are the only one"s which have their
    # eventDescription be not null
    if shift["eventDescription"] == nothing
        shift_dict[:Start] = convert_to_seconds(shift["startTime"])
        shift_dict[:End] = convert_to_seconds(shift["endTime"])
        shift_dict[:Duration] = convert_to_seconds(shift["duration"])
    else
        shift_dict = Dict{Symbol, String}()
    end

    return shift_dict
end


function parse_json(shift_json, game_id::String)
    shifts = [parse_shift(shift) for shift in shift_json["data"]]
    filter!(s -> !isempty(s), shifts)
    df = convert_dict_to_dataframe(shifts)
    df[:game_id] = String(game_id)[6:end]
    sort!(df, (:Period, :Start), rev=(false, false))
    return df
end

shift_json = get_shifts("foobar")
print(parse_json(shift_json, "2010020001"))
