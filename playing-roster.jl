using Cascadia
using Gumbo
using HTTP
using DataFrames

include("shared.jl")

function get_roster(game_id::String)
    A = game_id[1:4] # Year start = 2014
    B = parse(Int16, game_id[1:4]) + 1 # year start + 1
    C = game_id[5:end] #non-date game id
    request = HTTP.request("GET", "http://www.nhl.com/scores/htmlreports/$(A)$(B)/RO$C.HTM")
    response = String(request.body)
    return response
end

function get_coaches(response)
    html = parsehtml(response)
    coaches = eachmatch(Selector("tr#HeadCoaches"), html.root)
    if coaches == nothing
        return coaches
    end

    tds = eachmatch(Selector("td"), coaches[1])

    return Dict{Symbol, String}(
        :away => uppercase(nodeText(tds[2])),
        :home => uppercase(nodeText(tds[4]))
    )
end


"""
    fix_name(player::Array)
    Get rid of (A) or (C) when a player has it attached to their name

    :param player: list of player info -> [number, position, name]

    :return: fixed list
"""
function fix_name(player::Array)
    fixed = player
    fixed[3] = replace(player[3], "(A)" => "")
    fixed[3] = replace(fixed[3], "(C)" => "")
    fixed[3] = strip(fixed[3])
    return fixed
end

function get_players(response)
    html = parsehtml(response)

    tables = eachmatch(Selector("td.border > table"), html.root)
    player_info = [eachmatch(Selector("td"), table) for table in tables]
    player_info = [[nodeText(x) for x in group] for group in player_info]
    # Make list of list of 3 each. The three are: number, position, name (in that order)
    player_info = [[group[i:i+2] for i in 1:3:length(group) - 3] for group in player_info]
    # Get rid of header column
    player_info = [[player for player in group if player[1] != "#"] for group in player_info]


    for i in range(1, length(player_info))
        for j in range(1, length(player_info[i]))
            # Need to use strings here as the array is typed to Strings
            was_scratched = i == 3 || i == 4 ? "true" : "false"
            push!(player_info[i][j], was_scratched)
        end
    end

    players = Dict{Symbol, Array}(:away => player_info[1], :home => player_info[2])

    # Merge scratches back into player dataframe
    # Sometimes scratches aren't included
    if length(player_info) > 2
        append!(player_info[3], players[:away])
        append!(player_info[4], players[:home])
    end

    # Get rid when just whitespace
    # For those with (A) or (C) in name field get rid of it
    # First condition is to control when we get whitespace as one of the indices
    players[:away] = [p[1] != "\xa0" ? fix_name(p) : p for p in players[:away]]
    players[:home] = [p[1] != "\xa0" ? fix_name(p) : p for p in players[:home]]
    players[:away] = [p for p in players[:away] if p[1] != "\xa0"]
    players[:home] = [p for p in players[:home] if p[1] != "\xa0"]

    return players
end

function get_content(response)
    players = get_players(response)
    coaches = get_coaches(response)
    return players, coaches
end

response = get_roster("2016020426")
print(get_coaches(response))
get_players(response)

players, coaches = get_content(response)
