import GhosttyKit

protocol OcclusionControlled: AnyObject {
    var isWindowVisible: Bool { get set }
    var canControlOcclusion: Bool { get }
    func applyOcclusion(_ visible: Bool)
}

enum SurfaceOcclusion {
    static func sync<Surface: OcclusionControlled>(
        _ surfaces: [Surface],
        windowVisible: Bool,
        isInVisibleTree: (Surface) -> Bool
    ) {
        for surface in surfaces where surface.canControlOcclusion {
            let visible = windowVisible && isInVisibleTree(surface)
            guard surface.isWindowVisible != visible else { continue }
            surface.applyOcclusion(visible)
            surface.isWindowVisible = visible
        }
    }
}

extension Ghostty.SurfaceView: OcclusionControlled {
    var canControlOcclusion: Bool { surface != nil }

    func applyOcclusion(_ visible: Bool) {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, visible)
    }
}
