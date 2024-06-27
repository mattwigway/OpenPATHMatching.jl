module OpenPATHMatching
import GZip, JSON
import Dates: DateTime, Second, unix2datetime
import DataFrames: DataFrame, metadata!, leftjoin!
import ArchGDAL
import GeoFormatTypes as GFT
import Tables: dictrowtable
import OSRM: mapmatch
import Geodesy: LatLon

include("openpath-json.jl")
include("mapmatch.jl")

export json_to_gdf, tripmatch
end