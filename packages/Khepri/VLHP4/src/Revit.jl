export
    revit,
    all_walls,
    all_floors,
    RevitSystemFamily,
    RevitFileFamily,
    RevitInPlaceFamily

macro rvt_str(str)
    rpc("RVT", str)
end

encode_XYZ = encode_Point3d
decode_XYZ = decode_Point3d
encode_XYZ_array = encode_Point3d_array
decode_XYZ_array = decode_Point3d_array
encode_ElementId = encode_int
decode_ElementId = decode_int_or_error_numbered(-1234) # sometimes, Revit returns a id of -1
encode_ElementId_array = encode_int_array
decode_ElementId_array = decode_int_or_error_numbered_array(-1234) # sometimes, Revit returns a id of -1
encode_Element = encode_ElementId
decode_Element = decode_ElementId
decode_Element_array = decode_ElementId_array
encode_Length = encode_double
decode_Length = decode_double
encode_Length_array = encode_double_array
encode_Level = encode_ElementId
decode_Level = decode_ElementId
encode_Level_array = encode_ElementId_array
decode_Level_array = decode_ElementId_array
encode_FloorFamily = encode_int
decode_FloorFamily = decode_int_or_error

rvt"public Element SurfaceGrid(XYZ[] linearizedMatrix, int n, int m)"
rvt"public void MoveElement(ElementId id, XYZ translation)"
rvt"public void RotateElement(ElementId id, double angle, XYZ axis0, XYZ axis1)"
rvt"public Element InsertDoor(Length deltaFromStart, Length deltaFromGround, Element host, ElementId familyId)"
rvt"public Element InsertWindow(Length deltaFromStart, Length deltaFromGround, Element host, ElementId familyId)"
rvt"public Element InsertRailing(Element host, ElementId familyId)"

rvt"public void CreateFamily(string familyTemplatesPath, string familyTemplateName, string familyName)"
rvt"public void CreateFamilyExtrusionTest(XYZ[] pts, double height)"
rvt"public void InsertFamily(string familyName, XYZ p)"

rvt"public void HighlightElement(ElementId id)"
rvt"public ElementId[] GetSelectedElements()"
rvt"public bool IsProject()"
rvt"public void DeleteAllElements()"
rvt"public void SetView(XYZ camera, XYZ target, double focal_length)"
rvt"public void EnergyAnalysis()"

abstract type RVTKey end
const RVTId = Int
const RVTIds = Vector{RVTId}
const RVTRef = GenericRef{RVTKey, RVTId}
const RVTRefs = Vector{RVTRef}
const RVTNativeRef = NativeRef{RVTKey, RVTId}
const RVT = Socket_Backend{RVTKey, RVTId}

void_ref(b::RVT) = RVTNativeRef(-1)

create_RVT_connection() = create_backend_connection("Revit", 11001)

const revit = RVT(LazyParameter(TCPSocket, create_RVT_connection))

# Levels

rvt"public Level FindOrCreateLevelAtElevation(Length elevation)"
rvt"public Level UpperLevel(Level level, Length addedElevation)"
rvt"public Length GetLevelElevation(Level level)"

realize(b::RVT, s::Level) =
    RVTFindOrCreateLevelAtElevation(connection(b), s.height)

# Revit also considers unconnected walls. These have a top level with id -1
is_unconnected_level(level::Level) = ref(level).value == -1

# Families
#=

Revit families are divided into
1. System Families (for walls, roofs, floors, pipes)
2. Loadable Families (for building components that have an associated file)
3. In-Place Families (for unique elements created just for the current project)

=#

abstract type RevitFamily <: Family end

struct RevitSystemFamily <: RevitFamily
    parameter_map::Dict{Symbol,String}
    ref::Parameter{Int}
end

revit_system_family(pairs...) = RevitSystemFamily(Dict(pairs...), Parameter(-1))

struct RevitFileFamily <: RevitFamily
    path::String
    parameter_map::Dict{Symbol,String}
    ref::Parameter{Int}
end

revit_file_family(path, pairs...) = RevitFileFamily(path, Dict(pairs...), Parameter(-1))

# This is for future use
struct RevitInPlaceFamily <: RevitFamily
    parameter_map::Dict{Symbol,String}
    ref::Parameter{Int}
end


rvt"public ElementId LoadFamily(string fileName)"
rvt"public ElementId FamilyElement(ElementId familyId, string[] namesList, Length[] valuesList)"

backend_get_family(b::RVT, f::RevitSystemFamily) = 0 #Convention for system families
backend_get_family(b::RVT, f::RevitFileFamily) = RVTLoadFamily(connection(b), f.path)
backend_get_family(b::RVT, f::Family) =
    let revit_family = f.based_on # This needs to be fixed
        param_map = revit_family.parameter_map
        params = keys(param_map)
        if isempty(param_map) # no parameters, just use the system family
            0
        else
            RVTFamilyElement(connection(b),
                             ref(revit_family),
                             [param_map[param] for param in params],
                             [getfield(f, param) for param in params])
        end
    end

#

revit_wall_family = wall_family(based_on=revit_system_family())

# This should go into switch_to_backend


revit_beam_family =
    beam_family_element(
        beam_family(
            based_on=revit_file_family(
                "C:\\ProgramData\\Autodesk\\RVT 2017\\Libraries\\US Metric\\Structural Framing\\Wood\\M_Timber.rfa",
                :width=>"b", :height=>"d")),
        width=0.2, height=0.3)

# We need to install families

switch_to_backend(from::Backend, to::RVT) =
    let height = level_height(default_level())

        current_backend(to)
        default_level(level(height))
        default_wall_family(revit_wall_family) # Adjust to the former values?
        default_beam_family(revit_beam_family)
    end



#=
backend_get_family(b::RVT, f::TableFamily) =
    RVTCreateRectangularTableFamily(connection(b), f.length, f.width, f.height, f.top_thickness, f.leg_thickness)
backend_get_family(b::RVT, f::ChairFamily) =
    RVTCreateChairFamily(connection(b), f.length, f.width, f.height, f.seat_height, f.thickness)
backend_get_family(b::RVT, f::TableChairFamily) =
    RVTCreateRectangularTableAndChairsFamily(connection(b),
        ref(f.table_family), ref(f.chair_family),
        f.table_family.length, f.table_family.width,
        f.chairs_top, f.chairs_bottom, f.chairs_right, f.chairs_left,
        f.spacing)

backend_rectangular_table(b::RVT, c, angle, family) =
    RVTTable(connection(b), c, angle, ref(family))

backend_chair(b::RVT, c, angle, family) =
    RVTChair(connection(b), c, angle, ref(family))

backend_rectangular_table_and_chairs(b::RVT, c, angle, family) =
    RVTTableAndChairs(connection(b), c, angle, ref(family))
=#

rvt"public ElementId CreatePolygonalFloor(XYZ[] pts, ElementId levelId)"
rvt"public ElementId CreatePolygonalRoof(XYZ[] pts, ElementId levelId, ElementId famId)"
rvt"public ElementId CreatePathFloor(XYZ[] pts, double[] angles, ElementId levelId)"
rvt"public ElementId CreatePathRoof(XYZ[] pts, double[] angles, ElementId levelId, ElementId famId)"

locs_and_arcs(arc::ArcPath) =
    ([arc.center + vpol(arc.radius, arc.start_angle)],
     [arc.amplitude])

locs_and_arcs(circle::CircularPath) =
    let (locs1, arcs1) = locs_and_arcs(arc_path(circle.center, circle.radius, 0, pi))
        (locs2, arcs2) = locs_and_arcs(arc_path(circle.center, circle.radius, pi, pi))
        ([locs1..., locs2...], [arcs1..., arcs2...])
    end

realize_slab(b::RVT, contour::ClosedPath, level::Level, family::SlabFamily) =
    let (locs, arcs) = locs_and_arcs(contour)
        RVTCreatePathFloor(connection(b), locs, arcs, ref(level).value)
        # we are not using the family yet
        # ref(s.family))
    end

realize_slab(b::RVT, contour::ClosedPolygonalPath, level::Level, family::SlabFamily) =
    RVTCreatePolygonalFloor(
        connection(b),
        convert(ClosedPolygonalPath, contour).vertices,
        ref(level).value)
        # we are not using the family yet
        # ref(s.family))

realize_slab(b::RVT, contour::RectangularPath, level::Level, family::SlabFamily) =
    realize_slab(b, convert(ClosedPolygonalPath, contour), level, family)

rvt"public void CreatePolygonalOpening(XYZ[] pts, Element host)"
rvt"public void CreatePathOpening(XYZ[] pts, double[] angles, Element host)"

realize_slab_openings(b::RVT, s::Slab, s_ref, openings) =
    let s_base_height = s.level.height
        for opening in openings
            realize_slab_opening(b, s, opening)
        end
        s_ref
    end

realize_slab_opening(b::RVT, s::Slab, contour::ClosedPath) =
    let (locs, arcs) = locs_and_arcs(contour)
        RVTCreatePathOpening(connection(b), locs, arcs, ref(s).value)
    end
realize_slab_opening(b::RVT, s::Slab, contour::ClosedPolygonalPath) =
        RVTCreatePolygonalOpening(
            connection(b),
            convert(ClosedPolygonalPath, contour).vertices,
            ref(s).value)

rvt"public ElementId CreateBeam(XYZ p0, XYZ p1, double rotationAngle, ElementId famId)"

#Beams are aligned along the top axis.
realize(b::RVT, s::Beam) =
    let o = loc_from_o_phi(s.cb, s.angle)
        RVTCreateBeam(connection(b), o, add_z(o, s.h), s.angle, ref(s.family))
    end


rvt"public Element CreateColumn(XYZ location, ElementId baseLevelId, ElementId topLevelId, ElementId famId)"
rvt"public Element CreateColumnPoints(XYZ p0, XYZ p1, Level level0, Level level1, ElementId famId)"

#Columns are aligned along the center axis.

realize(b::RVT, s::Column) =
    let b = loc_from_o_phi(s.cb, s.angle)
        t = add_z(o, s.h)
        RVTCreateColumnPoints(connection(b), b, t,
            RVTFindOrCreateLevelAtElevation(connection(b), loc_in_world(b).z),
            RVTFindOrCreateLevelAtElevation(connection(b), loc_in_world(t).z),
            ref(s.family))
    end

#
rvt"public ElementId[] CreateLineWall(XYZ[] pts, ElementId baseLevelId, ElementId topLevelId, ElementId famId)"
rvt"public ElementId[] CreateUnconnectedLineWall(XYZ[] pts, ElementId baseLevelId, double height, ElementId famId)"
rvt"public ElementId CreateSplineWall(XYZ[] pts, ElementId baseLevelId, ElementId topLevelId, ElementId famId, bool closed)"
rvt"public Element CreateLineRailing(XYZ[] pts, ElementId baseLevelId, ElementId familyId)"
rvt"public Element CreatePolygonRailing(XYZ[] pts, ElementId baseLevelId, ElementId familyId)"

realize(b::RVT, s::Wall) =
    if is_unconnected_level(s.top_level)
        RVTCreateUnconnectedLineWall(
            connection(b),
            convert(OpenPolygonalPath, s.path).vertices,
            ref(s.bottom_level).value,
            s.top_level.height - s.bottom_level.height,
            ref(s.family))
    else
        RVTCreateLineWall(
            connection(b),
            convert(OpenPolygonalPath, s.path).vertices,
            ref(s.bottom_level).value,
            ref(s.top_level).value,
            ref(s.family))
    end

############################################

backend_bounding_box(b::RVT, shapes::Shapes) =
  RVTBoundingBox(connection(b), collect_ref(shapes))


backend_name(b::RVT) = "Revit"

import Base.view
view(camera::Loc, target::Loc, lens::Real, b::RVT) =
  RVTSetView(connection(b), camera, target, lens)

get_view(b::RVT) =
  let c = connection(b)
    RVTViewCamera(c), RVTViewTarget(c), RVTViewLens(c)
  end

zoom_extents(b::RVT) = RVTZoomExtents(connection(b))

view_top(b::RVT) =
    RVTViewTop(connection(b))

delete_all_shapes(b::RVT) = RVTDeleteAllElements(connection(b))

prompt_position(prompt::String, b::RVT) =
  let ans = RVTGetPoint(connection(b), prompt)
    length(ans) > 0 && ans[1]
  end

shape_from_ref(r, b::RVT) =
    let c = connection(b)
        code = RVTShapeCode(c, r)
        if code == 1
            point(RVTPointPosition(c, r),
                  backend=b, ref=LazyRef(b, RVTNativeRef(r)))
        elseif code == 2
            circle(maybe_loc_from_o_vz(RVTCircleCenter(c, r), RVTCircleNormal(c, r)),
                   RVTCircleRadius(c, r),
                   backend=b, ref=LazyRef(b, RVTNativeRef(r)))
        elseif 3 <= code <= 6
            line(RVTLineVertices(c, r),
                 backend=b, ref=LazyRef(b, RVTNativeRef(r)))
        elseif code == 7
            spline([xy(0,0)], false, false, #HACK obtain interpolation points
                   backend=b, ref=LazyRef(b, RVTNativeRef(r)))
        elseif code == 9
            let start_angle = mod(RVTArcStartAngle(c, r), 2pi)
                end_angle = mod(RVTArcEndAngle(c, r), 2pi)
                if end_angle > start_angle
                    arc(maybe_loc_from_o_vz(RVTArcCenter(c, r), RVTArcNormal(c, r)),
                        RVTArcRadius(c, r), start_angle, end_angle - start_angle,
                        backend=b, ref=LazyRef(b, RVTNativeRef(r)))
                else
                    arc(maybe_loc_from_o_vz(RVTArcCenter(c, r), RVTArcNormal(c, r)),
                        RVTArcRadius(c, r), end_angle, start_angle - end_angle,
                        backend=b, ref=LazyRef(b, RVTNativeRef(r)))
                end
            end
        elseif code == 10
            let str = RVTTextString(c, r)
                height = RVTTextHeight(c, r)
                loc = RVTTextPosition(c, r)
                text(str, loc, height, backend=b, ref=LazyRef(b, RVTNativeRef(r)))
            end
        elseif code == 11
            let str = RVTMTextString(c, r)
                height = RVTMTextHeight(c, r)
                loc = RVTMTextPosition(c, r)
                text(str, loc, height, backend=b, ref=LazyRef(b, RVTNativeRef(r)))
            end
        elseif code == 50
            block_instance(block("To be finished!"))
        elseif code == 70
            block_instance(block("A viewport to be finished!"))
        elseif 103 <= code <= 106
            polygon(RVTLineVertices(c, r),
                    backend=b, ref=LazyRef(b, RVTNativeRef(r)))
        else
            block_instance(block("Unknown shape. To be finished!"))
            #error("Unknown shape with code $(code)")
        end
    end

all_shapes(b::RVT) =
  [shape_from_ref(r, b) for r in RVTGetAllShapes(connection(b))]

all_shapes_in_layer(layer, b::RVT) =
  [shape_from_ref(r) for r in RVTGetAllShapesInLayer(connection(b), layer)]

disable_update(b::RVT) =
    RVTDisableUpdate(connection(b))

enable_update(b::RVT) =
    RVTEnableUpdate(connection(b))

rvt"public Level[] DocLevels()"
rvt"public Element[] DocElements()"
rvt"public Element[] DocFamilies()"
rvt"public Element[] DocFloors()"
rvt"public Element[] DocCeilings()"
rvt"public Element[] DocWalls()"
rvt"public Element[] DocWallsAtLevel(Level level)"
rvt"public XYZ[] LineWallVertices(Element element)"
rvt"public ElementId ElementLevel(Element element)"
rvt"public ElementId WallTopLevel(Element element)"
rvt"public double WallHeight(Element element)"

all_levels(b::RVT) =
    [level_from_ref(r, b) for r in RVTDocLevels(connection(b))]

level_from_ref(r, b::RVT) =
    let c = connection(b)
        level(r == -1 ?
                error("Level for unconnected height") :
                RVTGetLevelElevation(c, r),
              backend=b, ref=LazyRef(b, RVTNativeRef(r)))
    end

unconnected_level(h::Real, b::RVT) =
    level(h, backend=b, ref=LazyRef(b, RVTNativeRef(-1)))


all_Elements(b::RVT) =
    [element_from_ref(r, b) for r in RVTDocElements(connection(b))]

element_from_ref(r, b::RVT) =
    let c = connection(b)
        Foo(Bar(c, r), backend=b, ref=LazyRef(b, RVTNativeRef(r)))
    end

all_floors(b::RVT) =
    [floor_from_ref(r, b) for r in RVTFloorElements(connection(b))]

floor_from_ref(r, b::RVT) =
    let c = connection(b)
        Foo(Bar(c, r), backend=b, ref=LazyRef(b, RVTNativeRef(r)))
    end

all_walls(b::RVT) =
    [wall_from_ref(r, b) for r in RVTDocWalls(connection(b))]
all_walls_at_level(level::Level, b::RVT) =
    [wall_from_ref(r, b) for r in RVTDocWallsAtLevel(connection(b), ref(level).value)]

wall_from_ref(r, b::RVT) =
    let c = connection(b)
        path = convert(Path, RVTLineWallVertices(c, r))
        bottom_level_id = RVTElementLevel(c, r)
        top_level_id = RVTWallTopLevel(c, r)
        bottom_level = level_from_ref(bottom_level_id, b)
        top_level = top_level_id == -1 ?
                        unconnected_level(bottom_level.height + RVTWallHeight(c, r), b) :
                        level_from_ref(top_level_id, b)
        wall(path,
             bottom_level=bottom_level,
             top_level=top_level,
             backend=b,
             ref=LazyRef(b, RVTNativeRef(r)))
    end

#=

struct revit_family
    path::String
    map::Dict
end

struct archicad_family
    name::String
    map::Dict
end

# for a non-BIM backend
bars_family = beam_family(width=10,height=20,based_on=Dict(
    revit => revit_family(
        "C:\\ProgramData\\Autodesk\\RVT 2017\\Libraries\\US Metric\\Structural Framing\\Steel\\M_HSS-Hollow Structural Section.rfa",
        Dict(:width=>"b", :height=>"d", :angle=>"Cross-Section Rotation"))
#    archicad => archicad_family("SpecialBeam", Dict(:width=>"width", :height=>"height"))
))

=#
