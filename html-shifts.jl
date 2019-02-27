using Cascadia
using Gumbo
using HTTP
using DataFrames

include("shared.jl")

function get_shifts(game_id::String)::Tuple{String, String}
    # request = HTTP.request("GET", "http://www.nhl.com/scores/htmlreports/20162017/PL020475.HTM")
    A = game_id[1:4] # Year start = 2014
    B = parse(Int16, game_id[1:4]) + 1 # year start + 1
    C = game_id[5:end] #non-date game id
    function scrape_side(side::Char)::String
        if !(side in ('H', 'V')); throw(ArgumentError("Must be 'H' or 'V'")); end
        request = HTTP.request("GET", "http://www.nhl.com/scores/htmlreports/$(A)$(B)/T$(side)$C.HTM")
        response = String(request.body)
        println("http://www.nhl.com/scores/htmlreports/$(A)$(B)/T$(side)$C.HTM")
        return response
    end

    home = scrape_side('H')
    away = scrape_side('V')
    return home, away
end

function get_team_name(response)
    html = parsehtml(response)
    team = eachmatch(Selector("td.teamHeading"), html.root)
    return nodeText(team[1])
end

function analyze_shifts(shift, name, team)

    shift_dict = Dict{Symbol, Any}()

    shift_text = [nodeText(s) for s in shift]
    println(shift_text)
    shift_dict[:player] = uppercase(name)

    period = ifelse(shift_text[2] == "OT", 4, shift_text[2])
    shift_dict[:period] = parse(Int8, period)
    shift_dict[:team] = replace(team, r"\s"=>".")

    start = split(shift_text[3], "/")[1]
    shift_dict[:start] = convert_to_seconds(strip(start))
    duration = split(shift_text[5], "/")[1]
    shift_dict[:duration] = convert_to_seconds(strip(duration))

    # Problematic so we have the failsafe
    if match(r"\d+", shift_text[4]) != nothing
        stop = split(shift_text[4], "/")[1]
        shift_dict[:stop] = convert_to_seconds(strip(stop))
    else
        shift_dict[:stop] = shift_dict[:start] + shift_dict[:duration]
    end
    return shift_dict
end

function reorder_name(last_comma_first::AbstractString)::String
    name_parts = split(last_comma_first, ",")
    first = strip(name_parts[2])
    last = strip(name_parts[1])
    return "$first $last"
end

function parse_html(response, team)
    html = parsehtml(response)

    function get_players_tuples(html_root)
        players = eachmatch(Selector("td.playerHeading"), html_root)
        players = [nodeText(p) for p in players]
        players = [(parse(Int8, p[1:2]), strip(p[3:end])) for p in players]
        return players
    end

    players = get_players_tuples(html.root)
    tds = eachmatch(Selector("td.lborder.bborder"), html.root)

    all_raw_shifts = Dict{String, Array{HTMLElement}}()

    # Store the number of columns in the table (-1 because we aren't including
    # the last column)
    NUM_COLS = 6

    # Store the index and name of the current player
    curr_idx = 0
    curr_name = ""

    # Store the index of the current table cell
    td_idx = 1

    # Use while loop because we can't change the index of a `eachindex` loop
    while td_idx <= length(tds)
        text = nodeText(tds[td_idx])

        if occursin("Shift #", text)
            # If we find the first row of the table, increment the player index
            # and skip the current row.
            curr_idx += 1
            curr_name = reorder_name(players[curr_idx][2])
            println("Found player $curr_name")
            # Initialize an empty array for the player's shift dicts
            all_raw_shifts[curr_name] = []
            # Skip the row (- 1 because we handle the last column separately)
            td_idx += (NUM_COLS - 1)
        elseif occursin("Per", text)
            # If we're at the end of the table, we need to skip to the next player.
            # We can't just increment by a fixed amount as there are summary tables
            # at the end we need to ignore. So this step is to find the length of the
            # summary table and increment to one past it.
            while !occursin("TOT", nodeText(tds[td_idx]))
                # This will find the last row of the summary table.
                td_idx += 7
            end
            # Then we want to increment to one row past it.
            td_idx += 7
        elseif length(strip(text)) == 0 || strip(text) in ("G", "P", "GP") || occursin("EventG", text)
            # Remove the last column which indicates the event due to some weird edge-cases
            # where some cells have inner tables with more cells and others have only one.
            td_idx += 1
        else
            push!(all_raw_shifts[curr_name], tds[td_idx])
            td_idx += 1
        end
    end
    for player in keys(all_raw_shifts)
        first_shift = all_raw_shifts[player][1:5]
        shifts = [analyze_shifts(all_raw_shifts[player][i:i + 4], player, team) for i in 1:5:length(all_raw_shifts[player]) ]
    #     println("Length of $player is $(length(all_raw_shifts[player])) which is $(mod(length(all_raw_shifts[player]), 6) == 0)")
    end
    last_player = curr_name
    shifts = [nodeText(x) for x in all_raw_shifts[last_player]]
    println(shifts)
end

#http://www.nhl.com/scores/htmlreports/20162017/TH020426.HTM
home, away = get_shifts("2016020426")
home_team = get_team_name(home)
away_team = get_team_name(away)

parse_html(home, home_team)
