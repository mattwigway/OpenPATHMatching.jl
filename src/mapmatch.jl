"""
    mapmatch(osrm, points, user, trip_id)

Match the OpenPATH recorded points to an OSRM network, for the given user ID and trip ID. osrm is an
OSRMInstance, points is the output of get_all_points, and 
"""
function tripmatch(osrm, points, user, trip_id)
    trip_pts = points[points.user .== user .&& points.trip_id .== trip_id, :]

    sort!(trip_pts, :seq)

    lls = map(zip(trip_pts.latitude, trip_pts.longitude)) do (lat, lon)
        LatLon{Float64}(lat, lon)
    end

    # from https://github.com/e-mission/e-mission-server/blob/638005a/emission/core/wrapper/location.py#L19:
    # "accuracy": ecwb.WrapperBase.Access.RO,  # horizontal accuracy of the point in meters.
    #       This is the radius of the 68% confidence, so a lower
    #       number means better accuracy
    # MWBC: 68% confidence, i.e. 1 standard error
    # accuracy currently slows the match down too much. We probably need to cap the accuracy.
    return mapmatch(osrm, lls; timestamps=trip_pts.time, tidy=true #= std_error_meters=trip_pts.accuracy, =#)
end