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
# Array{Dict{Symbol, Any}}
function convert_dict_to_dataframe(array_of_dict::Array)::DataFrame
    return vcat(DataFrame.(array_of_dict)...)
end

# The native output didn't work because we have Nothings. Julia doesn't like
# when you call println on Nothing which is what the DataFrames approach does.
# Since we're only using this for testing, we'll write an ineffecient version
# that iterates through the dataframe, checks for nothing and prints.
function write_dataframe_to_csv(filename::AbstractString, df::DataFrame)
    open(filename, "w") do io
        # Write column names
        [write(io, "$name, ") for name in names(df)]
        write(io, "\n")

        for row in eachrow(df)
            for col in 1:ncol(df)
                output = row[col] == nothing ? ", " : "$(row[col]), "
                write(io, output);
            end
            write(io, "\n")
        end
    end
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

function fix_name(name::AbstractString)::String
    return replace(uppercase(replace(name, r"\.|\_" => "")), r"\s|\-"=>".")
end
