import Foundation

/// Minimal 3D vector type. We avoid `simd` so the core compiles on Linux for unit tests.
struct Vector3: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static let zero = Vector3(0, 0, 0)
    static let unitX = Vector3(1, 0, 0)
    static let unitY = Vector3(0, 1, 0)
    static let unitZ = Vector3(0, 0, 1)

    var length: Double { (x * x + y * y + z * z).squareRoot() }

    var normalized: Vector3 {
        let l = length
        return l > 1e-12 ? self / l : .zero
    }

    func dot(_ o: Vector3) -> Double { x * o.x + y * o.y + z * o.z }

    func cross(_ o: Vector3) -> Vector3 {
        Vector3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    /// Angle between two vectors in degrees.
    func angle(to o: Vector3) -> Double {
        let d = normalized.dot(o.normalized)
        return acos(max(-1, min(1, d))) * 180 / .pi
    }

    /// Removes the component along `axis` (axis does not need to be normalized).
    func orthogonalized(against axis: Vector3) -> Vector3 {
        let a = axis.normalized
        return self - a * dot(a)
    }

    var absolute: Vector3 { Vector3(abs(x), abs(y), abs(z)) }

    static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static prefix func - (a: Vector3) -> Vector3 { Vector3(-a.x, -a.y, -a.z) }
    static func * (a: Vector3, s: Double) -> Vector3 { Vector3(a.x * s, a.y * s, a.z * s) }
    static func * (s: Double, a: Vector3) -> Vector3 { a * s }
    static func / (a: Vector3, s: Double) -> Vector3 { Vector3(a.x / s, a.y / s, a.z / s) }
    static func += (a: inout Vector3, b: Vector3) { a = a + b }
}

/// Unit quaternion (x, y, z, w) as delivered by CoreMotion's `CMQuaternion`.
struct Quaternion: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double
    var w: Double

    init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    static let identity = Quaternion(x: 0, y: 0, z: 0, w: 1)

    /// Rotation of `angle` radians about `axis`.
    init(axis: Vector3, angle: Double) {
        let a = axis.normalized
        let s = sin(angle / 2)
        self.init(x: a.x * s, y: a.y * s, z: a.z * s, w: cos(angle / 2))
    }

    /// Rotation whose matrix has the given columns (the images of the x, y and z axes).
    init(rotationColumns c0: Vector3, _ c1: Vector3, _ c2: Vector3) {
        let m00 = c0.x, m10 = c0.y, m20 = c0.z
        let m01 = c1.x, m11 = c1.y, m21 = c1.z
        let m02 = c2.x, m12 = c2.y, m22 = c2.z
        let trace = m00 + m11 + m22
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            self.init(x: (m21 - m12) / s, y: (m02 - m20) / s, z: (m10 - m01) / s, w: 0.25 * s)
        } else if m00 > m11 && m00 > m22 {
            let s = (1 + m00 - m11 - m22).squareRoot() * 2
            self.init(x: 0.25 * s, y: (m01 + m10) / s, z: (m02 + m20) / s, w: (m21 - m12) / s)
        } else if m11 > m22 {
            let s = (1 + m11 - m00 - m22).squareRoot() * 2
            self.init(x: (m01 + m10) / s, y: 0.25 * s, z: (m12 + m21) / s, w: (m02 - m20) / s)
        } else {
            let s = (1 + m22 - m00 - m11).squareRoot() * 2
            self.init(x: (m02 + m20) / s, y: (m12 + m21) / s, z: 0.25 * s, w: (m10 - m01) / s)
        }
    }

    var conjugate: Quaternion { Quaternion(x: -x, y: -y, z: -z, w: w) }

    static func * (a: Quaternion, b: Quaternion) -> Quaternion {
        Quaternion(
            x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
        )
    }

    /// Rotates `v` by this quaternion (q * v * q⁻¹).
    func rotate(_ v: Vector3) -> Vector3 {
        let p = Quaternion(x: v.x, y: v.y, z: v.z, w: 0)
        let r = self * p * conjugate
        return Vector3(r.x, r.y, r.z)
    }
}
