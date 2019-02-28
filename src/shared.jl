################################################################################
# PACKAGES USED BY ALL SUBMODULES
################################################################################
using Cascadia
using Gumbo
using HTTP
using DataFrames

# Used by shared.jl
using Dates

################################################################################
# Data Structures
################################################################################

const Nullable{T} = Union{T, Nothing}

################################################################################
# Convenience Methods
################################################################################


function convert_to_seconds(minutes::AbstractString)::Integer
    # A small workaround to get the total seconds
    mins = Dates.DateTime(minutes, "MM:SS")
    # Round down to the nearest date
    dfloor = DateTime(Date(mins))
    secs_obj = convert(Dates.Second, Dates.Period(mins - dfloor))
    return Dates.value(secs_obj)
end

function convert_dict_to_dataframe(array_of_dict::Array{Dict{Symbol, Any}})::DataFrame
    return vcat(DataFrame.(array_of_dict)...)
end


function add_missing_columns!(plays::Array{Dict{Symbol, Any}})
    all_keys = Set{Symbol}()
    [union!(all_keys, keys(play)) for play in plays]
    for play in plays
        missing_keys = setdiff(all_keys, keys(play))
        new_dict = Dict(key=>nothing for key in missing_keys)
        merge!(play, new_dict)
    end
end

function fix_name(name::String)::String
    return replace(uppercase(replace(name, r"\.|\_" => "")), r"\s|\-"=>".")
end
