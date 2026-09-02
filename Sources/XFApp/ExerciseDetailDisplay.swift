// SPDX-License-Identifier: GPL-3.0-only

/// Lo que necesita la ventana de detalle de un truco (`docs/UI_DESIGN.md`
/// §3.6b): a la izquierda el dibujo TTM + descripción + historia; a la derecha
/// las variantes con la puntuación que se lleva sacada. Value type puro.
public struct ExerciseDetailDisplay: Equatable, Sendable {

    /// Una fila de la lista de variantes: la opción (con su candado) + la marca
    /// que se ha conseguido en ella.
    public struct VariantRow: Equatable, Sendable, Identifiable {
        public var option: VariantOption
        public var stars: Int
        /// Mejor puntuación, ya formateada ("3.840" o "—").
        public var bestScore: String
        public var attempts: Int

        public var id: String { option.variantId }

        public init(option: VariantOption, stars: Int, bestScore: String, attempts: Int) {
            self.option = option
            self.stars = stars
            self.bestScore = bestScore
            self.attempts = attempts
        }
    }

    /// Un miembro de una **familia** (Flare, Transformer): un truco de verdad con
    /// su dibujo, su ejercicio y sus variantes. La ficha de la familia lista
    /// varios de estos; `members` vacío = ficha de un solo truco.
    public struct MemberBlock: Equatable, Sendable, Identifiable {
        public var scratchId: String
        public var name: String
        public var thumbnail: TTMThumbnail?
        /// Ejercicio a lanzar (`nil` = sin ejercicio en el currículo todavía).
        public var exerciseId: String?
        public var variants: [VariantRow]
        public var id: String { scratchId }

        public init(scratchId: String, name: String, thumbnail: TTMThumbnail?,
                    exerciseId: String?, variants: [VariantRow]) {
            self.scratchId = scratchId
            self.name = name
            self.thumbnail = thumbnail
            self.exerciseId = exerciseId
            self.variants = variants
        }
    }

    public var scratchId: String
    public var name: String
    public var family: String
    /// Nivel del currículo donde se practica (no el del scratch).
    public var level: Int?
    public var technique: String
    public var description: String
    public var history: String?
    public var thumbnail: TTMThumbnail?
    /// El ejercicio que se lanza al pulsar "Practicar" (`nil` = no hay ejercicio
    /// para este scratch todavía, o es una ficha de familia: se practica por
    /// miembro).
    public var exerciseId: String?
    public var variants: [VariantRow]
    /// Miembros, si esto es la ficha de una **familia**. Vacío = truco suelto.
    public var members: [MemberBlock]

    public init(scratchId: String, name: String, family: String, level: Int?,
                technique: String, description: String, history: String?,
                thumbnail: TTMThumbnail?, exerciseId: String?, variants: [VariantRow],
                members: [MemberBlock] = []) {
        self.scratchId = scratchId
        self.name = name
        self.family = family
        self.level = level
        self.technique = technique
        self.description = description
        self.history = history
        self.thumbnail = thumbnail
        self.exerciseId = exerciseId
        self.variants = variants
        self.members = members
    }
}
