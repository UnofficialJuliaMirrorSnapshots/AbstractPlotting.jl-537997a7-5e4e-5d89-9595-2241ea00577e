
"""
Calculates the exact boundingbox of a Scene/Plot, without considering any transformation
"""
function raw_boundingbox(x::Atomic)
    bb = data_limits(x)
end
rootparent(x) = rootparent(parent(x))
rootparent(x::Scene) = x

function raw_boundingbox(x::Annotations)
    bb = raw_boundingbox(x.plots)
    inv(modelmatrix(rootparent(x))) * bb
end
function raw_boundingbox(x::Combined)
    raw_boundingbox(x.plots)
end
function boundingbox(x)
    raw_boundingbox(x)
end

function combined_modelmatrix(x)
    m = Mat4f0(I)
    while true
        m = modelmatrix(x) * m
        if parent(x) !== nothing && parent(x) isa Combined
            x = parent(x)
        else
            break
        end
    end
    m
end

function modelmatrix(x)
    t = transformation(x)
    transformationmatrix(t.translation[], t.scale[], t.rotation[])
end

function boundingbox(x::Atomic)
    bb = raw_boundingbox(x)
    combined_modelmatrix(x) * bb
end

boundingbox(scene::Scene) = raw_boundingbox(scene)
function raw_boundingbox(scene::Scene)
    if scene[Axis] !== nothing
        return raw_boundingbox(scene[Axis])
    elseif scene.limits[] !== automatic
        return scene_limits(scene)
    elseif cameracontrols(scene) == EmptyCamera()
        # Empty camera means this is a parent scene that itself doesn't display anything
        return raw_boundingbox(scene.children)
    else
        plots = plots_from_camera(scene)
        children = filter(scene.children) do child
            child.camera == scene.camera
        end
        return raw_boundingbox([plots; children])
    end
end

function raw_boundingbox(plots::Vector)
    isempty(plots) && return FRect3D()
    plot_idx = iterate(plots)
    bb = FRect3D()
    while plot_idx !== nothing
        plot, idx = plot_idx
        plot_idx = iterate(plots, idx)
        # isvisible(plot) || continue
        bb2 = boundingbox(plot)
        isfinite(bb) || (bb = bb2)
        isfinite(bb2) || continue
        bb = union(bb, bb2)
    end
    bb
end

function project_widths(matrix, vec)
    pr = project(matrix, vec)
    zero = project(matrix, zeros(typeof(vec)))
    pr - zero
end

function boundingbox(x::Text, text::String)
    position = to_value(x[:position])
    @get_attribute x (textsize, font, align, rotation)
    bb = boundingbox(text, position, textsize, font, align, rotation, modelmatrix(x))
    pm = inv(transformationmatrix(parent(x))[])
    wh = widths(bb)
    whp = project_widths(pm, wh)
    aoffset = whp .* to_ndim(Vec3f0, align, 0f0)
    FRect3D(minimum(bb) .- aoffset, whp)
end


boundingbox(x::Text) = boundingbox(x, to_value(x[1]))

function boundingbox(
        text::String, position, textsize;
        font = "default", align = (:left, :bottom), rotation = 0.0
    )
    boundingbox(
        text, position, textsize,
        to_font(font), to_align(align), to_rotation(rotation)
    )

end


function boundingbox(text::String, position, textsize, font, align, rotation, model = Mat4f0(I))
    atlas = get_texture_atlas()
    N = length(text)
    ctext_state = iterate(text)
    ctext_state === nothing && return FRect3D()
    pos_per_char = !isa(position, VecTypes)
    start_pos = Vec(pos_per_char ? first(position) : position)
    start_pos2D = to_ndim(Point2f0, start_pos, 0.0)
    last_pos = Point2f0(0, 0)
    start_pos3d = project(model, to_ndim(Vec3f0, start_pos, 0.0))
    bb = FRect3D(start_pos3d, Vec3f0(0))
    broadcast_foreach(1:N, rotation, font, textsize) do i, rotation, font, scale
        c, text_state = ctext_state
        ctext_state = iterate(text, text_state)
        # TODO fix center + align + rotation
        if c != '\r'
            pos = if pos_per_char
                to_ndim(Vec3f0, position[i], 0.0)
            else
                last_pos = calc_position(last_pos, Point2f0(0, 0), atlas, c, font, scale)
                start_pos3d .+ (rotation * to_ndim(Vec3f0, last_pos, 0.0))
            end
            s = glyph_scale!(atlas, c, font, scale)
            srot = rotation * to_ndim(Vec3f0, s, 0.0)
            bb = GeometryTypes.update(bb, pos)
            bb = GeometryTypes.update(bb, pos .+ srot)
        end
    end
    bb
end
