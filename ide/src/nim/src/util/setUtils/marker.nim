import re, strutils, os, tables, json, db_sqlite, parseutils 
import ../types
import common

proc getMarkerQuery*(ancestors: seq[int], outerSetName: string): string =
    let parentIdIndexes = getParentIdIndexes(ancestors)
    var markerIdIndex = ""
    let nullIndexes = getNullIndexes(ancestors.len())
    result &= "SELECT lower, upper, name FROM domain WHERE name like '"

    if ancestors.len() == 0:
        result &= outerSetName & "\\_%\\_Marker%' escape '\\' " & parentIdIndexes 
    else:
        result &= outerSetName & "\\_%\\_Marker\\_%' escape '\\' " & parentIdIndexes 

    result &= " " & markerIdIndex 
    result &= nullIndexes 
    result &= " and nodeId = ? ;"

proc getMarkerValuesQuery*(ancestors: seq[int], parentLower: int, outerSetName: string): string =
    let parentIdIndexes = getParentIdIndexes(ancestors)
    let markerIdIndex = getSingleIndexLE(ancestors.len(), parentLower)
    let nullIndexes = getNullIndexes(ancestors.len() + 1)
    result &= "SELECT lower, name FROM domain WHERE lower = upper and name like '" 
    result &= outerSetName & "\\_%\\Marker_Values\\_%' escape '\\' " & parentIdIndexes 
    result &= markerIdIndex & nullIndexes & " and nodeId = ?;"
