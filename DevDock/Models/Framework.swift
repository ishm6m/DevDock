import Foundation

/// A development framework or runtime that DevDock can recognize.
///
/// Each case carries presentation metadata (display name, badge monogram, accent
/// color) used by the UI. Detection logic lives in `FrameworkDetector`; this type
/// is intentionally just data so it stays trivial to test and extend.
enum Framework: String, CaseIterable, Codable, Hashable {
    case nextjs
    case vite
    case react
    case angular
    case vue
    case astro
    case remix
    case nuxt
    case express
    case nestjs
    case node
    case flask
    case fastapi
    case django
    case rails
    case go
    case rust
    case bun
    case deno
    case expo
    case metro
    case laravel
    case php
    case unknown

    enum Category: String, Codable {
        case frontend
        case backend
        case runtime
        case mobile
        case other
    }

    var displayName: String {
        switch self {
        case .nextjs: return "Next.js"
        case .vite: return "Vite"
        case .react: return "React"
        case .angular: return "Angular"
        case .vue: return "Vue"
        case .astro: return "Astro"
        case .remix: return "Remix"
        case .nuxt: return "Nuxt"
        case .express: return "Express"
        case .nestjs: return "NestJS"
        case .node: return "Node"
        case .flask: return "Flask"
        case .fastapi: return "FastAPI"
        case .django: return "Django"
        case .rails: return "Rails"
        case .go: return "Go"
        case .rust: return "Rust"
        case .bun: return "Bun"
        case .deno: return "Deno"
        case .expo: return "Expo"
        case .metro: return "Metro"
        case .laravel: return "Laravel"
        case .php: return "PHP"
        case .unknown: return "Process"
        }
    }

    /// A short label rendered inside the framework badge. Real logo assets can be
    /// dropped into the asset catalog later; monograms keep DevDock license-safe.
    var monogram: String {
        switch self {
        case .nextjs: return "N"
        case .vite: return "V"
        case .react: return "R"
        case .angular: return "NG"
        case .vue: return "Vu"
        case .astro: return "A"
        case .remix: return "Rx"
        case .nuxt: return "Nx"
        case .express: return "Ex"
        case .nestjs: return "Ne"
        case .node: return "No"
        case .flask: return "Fl"
        case .fastapi: return "FA"
        case .django: return "Dj"
        case .rails: return "Ra"
        case .go: return "Go"
        case .rust: return "Rs"
        case .bun: return "Bn"
        case .deno: return "Dn"
        case .expo: return "Xp"
        case .metro: return "M"
        case .laravel: return "La"
        case .php: return "PHP"
        case .unknown: return "?"
        }
    }

    /// Accent color as a hex string; converted to `Color` via `Color(hex:)`.
    var accentColorHex: String {
        switch self {
        case .nextjs: return "#111827"
        case .vite: return "#646CFF"
        case .react: return "#149ECA"
        case .angular: return "#DD0031"
        case .vue: return "#42B883"
        case .astro: return "#FF5D01"
        case .remix: return "#3992FF"
        case .nuxt: return "#00DC82"
        case .express: return "#6B7280"
        case .nestjs: return "#E0234E"
        case .node: return "#339933"
        case .flask: return "#4B5563"
        case .fastapi: return "#009688"
        case .django: return "#0C4B33"
        case .rails: return "#CC0000"
        case .go: return "#00ADD8"
        case .rust: return "#CE422B"
        case .bun: return "#EC4899"
        case .deno: return "#0EA5E9"
        case .expo: return "#1B1F23"
        case .metro: return "#EF4444"
        case .laravel: return "#FF2D20"
        case .php: return "#777BB4"
        case .unknown: return "#8E8E93"
        }
    }

    var category: Category {
        switch self {
        case .nextjs, .vite, .react, .angular, .vue, .astro, .remix, .nuxt:
            return .frontend
        case .express, .nestjs, .flask, .fastapi, .django, .rails, .laravel, .php:
            return .backend
        case .node, .go, .rust, .bun, .deno:
            return .runtime
        case .expo, .metro:
            return .mobile
        case .unknown:
            return .other
        }
    }

    /// SF Symbol used when a framework has no dedicated badge treatment.
    var categorySymbol: String {
        switch category {
        case .frontend: return "globe"
        case .backend: return "server.rack"
        case .runtime: return "cpu"
        case .mobile: return "iphone"
        case .other: return "shippingbox"
        }
    }
}
