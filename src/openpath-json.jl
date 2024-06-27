"""
    read_json_gz(filename)

Read a (possibly GZipped) JSON file.
"""
function read_json_gz(filename)
    ofunc = isgzfile(filename) ? GZip.open : open

    local result

    ofunc(filename) do inp
        result = JSON.parse(inp)
    end

    return result
end


"""
    isgzfile(filename)

Check for the GZip magic number to see if something is a GZipped file.
"""
function isgzfile(filename)
    open(filename, "r") do file
        return read(file, UInt8) == 0x1f && read(file, UInt8) == 0x8b
    end
end

"""
    parse_time(dtstring)

Parse an OpenPATH formatted time. Drops time zone information, and floors the seconds position.
"""
function parse_time(dtstring)
    m = match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}", dtstring)
    !isnothing(m) || error("Failed to parse string $dtstring")
    return DateTime(m.match)
end

"""
    get_all_points(parsed_json)

Return a GeoDataFrame containing all points from the parsed JSON.
"""
function get_all_points(json)
    all_points_raw = [d for d in json if d["metadata"]["key"] == "background/location"]
    all_points = DataFrame(map(all_points_raw) do p
        (
            user = p["user_id"]["\$uuid"],
            time = unix2datetime(p["data"]["ts"]),
            altitude = p["data"]["altitude"],
            accuracy = p["data"]["accuracy"],
            sensed_speed = p["data"]["sensed_speed"],
            geom = ArchGDAL.createpoint((p["data"]["longitude"], p["data"]["latitude"]))
        )
    end)

    sort!(all_points, [:user, :time])
    metadata!(all_points, "geometrycolumns", (:geom,))
    metadata!(all_points, "crs", GFT.EPSG(4326))

    return all_points
end

"""
    get_all_trips(data)

Get all trips from a JSON OpenPATH export. Returns two dataframes:

trips: the trip data
points: information about individual points in each trip
"""
function get_all_trips(data)
    all_trips_raw = [d for d in data if d["metadata"]["key"] == "analysis/composite_trip"]

    points = []
    trips = []

    for trip in all_trips_raw
        user = trip["user_id"]["\$uuid"]
        trip_id = trip["_id"]["\$oid"]

        coords = Vector{Float64}[]

        seq = 1
        for loc in trip["data"]["locations"]
            push!(points, (
                user = user,
                trip_id = trip_id,
                altitude = loc["data"]["altitude"],
                time = unix2datetime(loc["data"]["ts"]),
                latitude = loc["data"]["latitude"],
                longitude = loc["data"]["longitude"],
                seq = seq
            ))

            push!(coords, [loc["data"]["longitude"], loc["data"]["latitude"]])

            seq += 1
        end

        has_pred = haskey(trip["data"], "inferred_labels") && !isempty(trip["data"]["inferred_labels"])

        push!(trips, (
            user = user,
            trip_id = trip_id,
            # this is in GMT not local time
            start_time = unix2datetime(trip["data"]["start_ts"]),
            end_time = unix2datetime(trip["data"]["end_ts"]),
            duration = trip["data"]["duration"],
            distance = trip["data"]["distance"],
            geom = ArchGDAL.createlinestring(coords),
            p = has_pred ? first(trip["data"]["inferred_labels"])["p"] : missing,
            (has_pred ? [Symbol(a) => b for (a, b) in pairs(first(trip["data"]["inferred_labels"])["labels"])] : ())...
        ))
    end

    tripdf = DataFrame(dictrowtable(trips))
    metadata!(tripdf, "geometrycolumns", (:geom,))
    metadata!(tripdf, "crs", GFT.EPSG(4326))
    pointdf = DataFrame(points)

    return tripdf, pointdf
end

"""
    get_all_labels(data)

Get inferred labels for trips.
"""
function get_all_labels(data)
    lbl_raw = [d for d in data if d["metadata"]["key"] == "analysis/inferred_labels"]
    # DictRowTable to handle different sets of column names:
    # https://discourse.julialang.org/t/construct-dataframe-from-uneven-named-tuples/102970/5
    lbls = DataFrame(dictrowtable(map(lbl_raw) do lbl
        has_pred = !isempty(lbl["data"]["prediction"])
        (
            user = lbl["user_id"]["\$uuid"],
            trip_id = lbl["data"]["trip_id"]["\$oid"],
            p = has_pred ? first(lbl["data"]["prediction"])["p"] : missing,
            (has_pred ? [Symbol(a) => b for (a, b) in pairs(first(lbl["data"]["prediction"])["labels"])] : ())...
        )
    end))

    return lbls
end

"""
    json_to_gdf(data)

Convert JSON OpenPATH export data to a GeoDataFrame.
"""
function json_to_gdf(data)
    # first, find all the trips
    trips = get_all_trips(data)

    # # join with labels
    # labels = get_all_labels(data)
    # leftjoin!(trips, labels, on=[:user, :trip_id])

    # next, find all the points
    pts = get_all_points(data)

    # TODO: this is probably horribly inefficient, because
    # 1) I don't think it's type stable
    # 2) it's not using any indices, or even a binary search
    trips.geom = map(zip(trips.user, trips.start_time, trips.end_time)) do (user, start_time, end_time)
        ArchGDAL.createlinestring(ArchGDAL.getpoint.(pts[pts.user .== user .&& pts.time .≥ start_time .&& pts.time .≤ end_time, :geom], 0))
    end

    trips.npts = ArchGDAL.ngeom.(trips.geom)

    metadata!(trips, "geometrycolumns", (:geom,))
    metadata!(trips, "crs", GFT.EPSG(4326))

    return trips
end