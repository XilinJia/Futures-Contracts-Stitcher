
# Project: Stitcher
# Copyright (c) 2014 Xilin Jia <https://github.com/XilinJia>
# This software is released under the MIT license
# https://opensource.org/licenses/MIT

__precompile__(true)

module DataRoutines

using Dates
using CSV
using DataFrames

export Stitch

# use Quandl's "Open_Interest" instead of the old "Interest"

function Stitch(Instr=""; StartDate="2010-01-01", EndDate="2050-12-31", AdjMethod="M", openInterest::Symbol=:Open_Interest)
    if Instr==""
        DataDir = pwd() * "/"
    else
        DataDir = pwd() * "/Data/" * Instr * "/"
    end
    println("Stitch files in directory: ", DataDir)

    filenames = readdir(DataDir)
    filter!(fname -> occursin("Contract", fname), filenames)
    nfiles = length(filenames)
    println(filenames)
    dfs = Array{DataFrame}(undef, nfiles)

    df = DataFrame()

    fIndex = 1
    for i=1:nfiles
        fname = filenames[i]
        if fname[end-3:end] == ".csv" && occursin("Contract", fname)
            println("Reading: ", fname)
            colTypes = Dict(:Open=>Float64, :High=>Float64, :Low=>Float64, :Close=>Float64, openInterest=>Float64)
            dfs[i] = CSV.read(DataDir * fname, DataFrame, types=colTypes, missingstring = "NA")  
            dfs[i] = DropDatesOutside(dfs[i], StartDate, EndDate)
            dfs[i] = DropNAValues(dfs[i])
            NameCol = Array{String}(undef, nrow(dfs[i]))
            [NameCol[j]=fname[1:end-4] for j=1:nrow(dfs[i])]
            dfs[i][!, :Contract] = NameCol
            if fIndex==1
                df = dfs[i]
            else
                df = vcat(df, dfs[i])
            end
            fIndex += 1
        end
    end
    println("Total number of combined rows: ", nrow(df))
    unique!(df)
    println("Number of rows after unique: ", nrow(df))

    if hasproperty(df, openInterest)
        sort!(df, [order(:Date, rev=false), order(openInterest, rev=true)])
    else
        println("Data file has no $openInterest column")
        return
    end

    curRow = 1
    curDate = df[!, :Date][curRow]
    rows=[curRow]
    rollrows=Array{Int64}(undef, 0)
    CurContract=df[!, :Contract][curRow]
    for i=1:nrow(df)
        if df[!, :Date][i] != curDate
            if df[!, :Contract][i] == CurContract
                curRow=i
                curDate = df[!, :Date][curRow]
                push!(rows, curRow)
            else
                println("Roll date: ", i, " ", df[!, :Date][i], " ", CurContract, " ", df[!, :Contract][i])
                push!(rollrows, i)
                for j=i:i+12+1
                    if df[!, :Contract][j] == CurContract
                        curRow=j
                        curDate = df[!, :Date][curRow]
                        push!(rows, curRow)
                        CurContract = df[!, :Contract][i]
                        break
                    end
                end
            end
        end
    end

    dfStitch = df[intersect(1:end,rows), :]
    dfRoll = df[intersect(1:end,rollrows), :]

    println("Total number of stitched rows: ", nrow(df))

    ofname = DataDir * "Stitched.csv"
    CSV.write(ofname, dfStitch)

    ofname = DataDir * "Roll.csv"
    CSV.write(ofname, dfRoll)

    if AdjMethod=="M"
        AdjustDF = AdjustDFM
    else
        AdjustDF = AdjustDFA
    end

    for i=1:nrow(dfRoll)
        for j=1:nrow(dfStitch)
            if dfStitch[!, :Date][j] == dfRoll[!, :Date][i]
                AdjustDF(dfStitch, dfRoll[!, :Close][i], dfStitch[!, :Close][j], j)
            end
        end
    end

    ofname = DataDir * "StitchedAdj" * AdjMethod * ".csv"
    println("Stitch final output file is: ", ofname)
    CSV.write(ofname, dfStitch)
    nothing
end

function AdjustDFM(dfStitch::DataFrame, NewClose::Real, OldClose::Real, j::Int64)
    adjRatio = NewClose / OldClose
    for k=j:-1:1
        dfStitch[!, :Open][k] = dfStitch[!, :Open][k] * adjRatio
        dfStitch[!, :High][k] = dfStitch[!, :High][k] * adjRatio
        dfStitch[!, :Low][k] = dfStitch[!, :Low][k] * adjRatio
        dfStitch[!, :Close][k] = dfStitch[!, :Close][k] * adjRatio
    end
    nothing
end

function AdjustDFA(dfStitch::DataFrame, NewClose::Real, OldClose::Real, j::Int64)
    adjRatio = NewClose - OldClose
    for k=j:-1:1
        dfStitch[!, :Open][k] = dfStitch[!, :Open][k] + adjRatio
        dfStitch[!, :High][k] = dfStitch[!, :High][k] + adjRatio
        dfStitch[!, :Low][k] = dfStitch[!, :Low][k] + adjRatio
        dfStitch[!, :Close][k] = dfStitch[!, :Close][k] + adjRatio
    end
    nothing
end

function DropNAValues(df::DataFrame)
    rows=Array{Int64}(undef, 0)
    for ii=1:nrow(df)
        if ismissing(df.Open[ii]) || ismissing(df.High[ii]) || ismissing(df.Low[ii]) || ismissing(df.Close[ii])
            push!(rows, ii)
        end
    end
    return df[setdiff(1:end,rows), :]
end

function DropDatesOutside(df::DataFrame, StartDate::String, EndDate::String)
    rows=Array{Int64}(undef, 0)
    dlim1 = "y-m-d"
    if occursin("-", StartDate)
        dlim1 = "y-m-d"
    elseif occursin("/", StartDate)
        dlim1 = "y/m/d"
    else
        println("StartDate format error: ", StartDate)
        return DataFrame()
    end
    dlim2 = "y-m-d"
    if occursin("-", EndDate)
        dlim2 = "y-m-d"
    elseif occursin("/", EndDate)
        dlim2 = "y/m/d"
    else
        println("EndDate format error: ", EndDate)
        return DataFrame()
    end
    for ii=1:nrow(df)
        if df.Date[ii] < Date(StartDate, DateFormat(dlim1)) || df.Date[ii] > Date(EndDate, DateFormat(dlim2))
            push!(rows, ii)
        end
    end
    return df[setdiff(1:end,rows), :]
end

end     # module
