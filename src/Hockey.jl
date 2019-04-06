##############################################################################
# The HTML scraper is not working at the moment. For now, we have the JSON
# functionality working correctly, and we'll work to get the HTML PBP working
# now.
##############################################################################


module Hockey

include("shared.jl")
include("html_pbp.jl")
include("json_pbp.jl")
include("html_shifts.jl")
include("json_shifts.jl")
include("espn_shots.jl")



# Used submodules due to the overlapping functionality between the different components
# That is, each file is its own module as the methods are overlapping with no distinguishing
# features (e.g. both HTML_PBP and JSON_PBP have a `scrape_game`) method. The compiler would not
# be able to differentiate between the two methods due to their same type signature. The way around
# this would be to rename methods but that seems messy or create subpackages but that seems excessive.
# Thus, this solution was selected as it was the neatest.
# See here for more info: https://stackoverflow.com/questions/40310787/julia-code-encapsulation-is-this-a-generally-good-idea

import .HTML_PBP
html_pbp = HTML_PBP.scrape_game("2016020426")
write_dataframe_to_csv("outputs/html_pbp.csv", html_pbp)

import .JSON_PBP
json_pbp = JSON_PBP.scrape_game("2016020426")
write_dataframe_to_csv("outputs/json_pbp.csv", json_pbp)

import .HTML_Shifts
home_shifts, away_shifts = HTML_Shifts.scrape_shifts("2016020426")
write_dataframe_to_csv("outputs/html_shifts_home.csv", home_shifts)
write_dataframe_to_csv("outputs/html_shifts_away.csv", away_shifts)

# # TODO Figure out why `convert_dict_to_dataframe` isn't working for json_shifts
import .JSON_Shifts
json_shifts = JSON_Shifts.scrape_shifts("2016020426")
write_dataframe_to_csv("outputs/json_shifts.csv", json_shifts)

import .ESPN_Shots
shots = ESPN_Shots.scrape_shots("20190211", "PITTSBURGH PENGUINS", "PHILADELPHIA FLYERS")
write_dataframe_to_csv("outputs/shots.csv", shots)

import .PlayingRoster
roster, coaches = PlayingRoster.scrape_roster_and_coaches("2016020426")
write_dataframe_to_csv("outputs/playing_roster.csv", roster)
write_dataframe_to_csv("outputs/playing_coaches.csv", coaches)

end # module
