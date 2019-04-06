module Hockey

include("shared.jl")
include("json_pbp.jl")
include("json_shifts.jl")

import .JSON_PBP
import .JSON_Shifts


export scrape_game


function scrape_game(game_id::AbstractString, scrape_shifts::Bool=false)
    pbp = JSON_PBP.scrape_game(game_id)
    if scrape_shifts
        shifts = JSON_Shifts.scrape_shifts(game_id)
        return pbp, shifts
    else
        return pbp
    end
end

end
