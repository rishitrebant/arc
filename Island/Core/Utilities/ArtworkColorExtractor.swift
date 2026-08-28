import SwiftUI
import AppKit

enum ArtworkColorExtractor {

    // MARK: - Public API

    static func dominantColor(
        from image: NSImage?,
        fallback: Color
    ) -> Color {

        guard
            let image,
            let bitmap = makeBitmap(from: image)
        else {
            return fallback
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh

        guard
            width > 0,
            height > 0
        else {
            return fallback
        }

        // We use a hue histogram instead of simply picking the
        // brightest or most saturated pixel.
        //
        // This prevents a tiny yellow/green logo or text pixel
        // from becoming the entire album's glow color.
        var hueWeights = Array(
            repeating: 0.0,
            count: 24
        )

        var hueSaturationWeights = Array(
            repeating: 0.0,
            count: 24
        )

        var neutralRed = 0.0
        var neutralGreen = 0.0
        var neutralBlue = 0.0
        var neutralWeight = 0.0

        let bytesPerPixel = 4
        let bytesPerRow = bitmap.bytesPerRow

        guard
            let data = bitmap.bitmapData
        else {
            return fallback
        }

        // Sample every few pixels rather than every pixel.
        //
        // This keeps the calculation cheap while still giving us
        // enough information for album artwork.
        let step = max(
            1,
            max(width, height) / 64
        )

        for y in stride(
            from: 0,
            to: height,
            by: step
        ) {

            for x in stride(
                from: 0,
                to: width,
                by: step
            ) {

                let offset =
                    y * bytesPerRow
                    + x * bytesPerPixel

                let r =
                    Double(data[offset]) / 255.0

                let g =
                    Double(data[offset + 1]) / 255.0

                let b =
                    Double(data[offset + 2]) / 255.0

                let a =
                    Double(data[offset + 3]) / 255.0

                // Ignore transparent pixels.
                guard a > 0.05 else {
                    continue
                }

                let hsv =
                    rgbToHSV(
                        r: r,
                        g: g,
                        b: b
                    )

                let saturation = hsv.s
                let brightness = hsv.v
                let hue = hsv.h

                // ----------------------------------------------------
                // DARK PIXELS
                // ----------------------------------------------------
                //
                // Don't let black backgrounds dominate a colour
                // histogram.
                // ----------------------------------------------------

                if brightness < 0.10 {

                    neutralRed += r
                    neutralGreen += g
                    neutralBlue += b
                    neutralWeight += 1.0

                    continue
                }

                // ----------------------------------------------------
                // VERY LIGHT / WHITE PIXELS
                // ----------------------------------------------------

                if brightness > 0.94 &&
                    saturation < 0.12 {

                    neutralRed += r
                    neutralGreen += g
                    neutralBlue += b
                    neutralWeight += 0.35

                    continue
                }

                // ----------------------------------------------------
                // LOW SATURATION
                // ----------------------------------------------------
                //
                // Gray/beige pixels shouldn't create a strong hue.
                // We still remember them as neutral information.
                // ----------------------------------------------------

                if saturation < 0.18 {

                    neutralRed += r
                    neutralGreen += g
                    neutralBlue += b
                    neutralWeight += 0.7

                    continue
                }

                // ----------------------------------------------------
                // COLOURFUL PIXELS
                // ----------------------------------------------------

                let bucket = min(
                    23,
                    Int(
                        hue * 24.0
                    )
                )

                // Weight by saturation, but not linearly enough
                // to let one highly saturated pixel dominate.
                //
                // Saturation is capped at 0.75 for this reason.
                let saturationWeight =
                    min(
                        saturation,
                        0.75
                    )

                // Mid-tone pixels are more useful than extremely
                // dark or extremely bright pixels.
                let brightnessWeight =
                    1.0
                    - abs(
                        brightness - 0.55
                    ) * 0.8

                let weight =
                    saturationWeight
                    * max(
                        brightnessWeight,
                        0.2
                    )
                    * a

                hueWeights[bucket] += weight

                hueSaturationWeights[bucket] +=
                    saturationWeight * a
            }
        }

        // ------------------------------------------------------------
        // FIND THE DOMINANT HUE
        // ------------------------------------------------------------

        guard
            let winningBucket =
                hueWeights
                    .enumerated()
                    .max(
                        by: {
                            $0.element < $1.element
                        }
                    )?.offset
        else {

            return makeNeutralColor(
                red: neutralRed,
                green: neutralGreen,
                blue: neutralBlue,
                weight: neutralWeight,
                fallback: fallback
            )
        }

        let winnerWeight =
            hueWeights[winningBucket]

        // If the entire artwork contains almost no meaningful colour,
        // don't invent one.
        //
        // This is what prevents a mostly-black album with one tiny
        // coloured pixel from becoming neon yellow.
        let totalHueWeight =
            hueWeights.reduce(
                0,
                +
            )

        guard
            totalHueWeight > 0,
            winnerWeight / totalHueWeight > 0.12
        else {

            return makeNeutralColor(
                red: neutralRed,
                green: neutralGreen,
                blue: neutralBlue,
                weight: neutralWeight,
                fallback: fallback
            )
        }

        // ------------------------------------------------------------
        // AVERAGE THE WINNING HUE
        // ------------------------------------------------------------
        //
        // Rather than taking one pixel, average all pixels that belong
        // to the dominant hue bucket.
        // ------------------------------------------------------------

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var colorWeight = 0.0

        // Second pass through the bitmap.
        for y in stride(
            from: 0,
            to: height,
            by: step
        ) {

            for x in stride(
                from: 0,
                to: width,
                by: step
            ) {

                let offset =
                    y * bytesPerRow
                    + x * bytesPerPixel

                let r =
                    Double(data[offset]) / 255.0

                let g =
                    Double(data[offset + 1]) / 255.0

                let b =
                    Double(data[offset + 2]) / 255.0

                let a =
                    Double(data[offset + 3]) / 255.0

                guard a > 0.05 else {
                    continue
                }

                let hsv =
                    rgbToHSV(
                        r: r,
                        g: g,
                        b: b
                    )

                guard
                    hsv.s >= 0.18,
                    hsv.v >= 0.10,
                    hsv.v <= 0.96
                else {
                    continue
                }

                let bucket = min(
                    23,
                    Int(
                        hsv.h * 24.0
                    )
                )

                guard
                    bucket == winningBucket
                else {
                    continue
                }

                let weight =
                    min(
                        hsv.s,
                        0.75
                    ) * a

                red += r * weight
                green += g * weight
                blue += b * weight

                colorWeight += weight
            }
        }

        guard
            colorWeight > 0
        else {
            return fallback
        }

        red /= colorWeight
        green /= colorWeight
        blue /= colorWeight

        // ------------------------------------------------------------
        // GENTLY TAME THE RESULT
        // ------------------------------------------------------------
        //
        // Don't allow the extracted color to become ridiculously
        // saturated just because the artwork contains a strong accent.
        // ------------------------------------------------------------

        var resultHSV =
            rgbToHSV(
                r: red,
                g: green,
                b: blue
            )

        resultHSV.s =
            min(
                resultHSV.s,
                0.72
            )

        resultHSV.v =
            min(
                max(
                    resultHSV.v,
                    0.20
                ),
                0.85
            )

        let finalRGB =
            hsvToRGB(
                h:
                    resultHSV.h,

                s:
                    resultHSV.s,

                v:
                    resultHSV.v
            )

        return Color(
            red:
                finalRGB.r,

            green:
                finalRGB.g,

            blue:
                finalRGB.b
        )
    }

    // MARK: - Bitmap conversion

    private static func makeBitmap(
        from image: NSImage
    ) -> NSBitmapImageRep? {

        let targetSize =
            NSSize(
                width: 128,
                height: 128
            )

        let bitmap =
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 128,
                pixelsHigh: 128,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: 128 * 4,
                bitsPerPixel: 32
            )

        guard
            let bitmap
        else {
            return nil
        }

        guard
            let graphicsContext =
                NSGraphicsContext(
                    bitmapImageRep:
                        bitmap
                )
        else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()

        NSGraphicsContext.current =
            graphicsContext

        image.draw(
            in:
                NSRect(
                    origin: .zero,
                    size: targetSize
                ),

            from:
                .zero,

            operation:
                .copy,

            fraction:
                1.0
        )

        graphicsContext.flushGraphics()

        NSGraphicsContext.restoreGraphicsState()

        return bitmap
    }

    // MARK: - RGB -> HSV

    private static func rgbToHSV(
        r: Double,
        g: Double,
        b: Double
    ) -> (
        h: Double,
        s: Double,
        v: Double
    ) {

        let maxValue =
            max(
                r,
                g,
                b
            )

        let minValue =
            min(
                r,
                g,
                b
            )

        let delta =
            maxValue
            - minValue

        var hue = 0.0

        if delta != 0 {

            if maxValue == r {

                hue =
                    (
                        (
                            g - b
                        )
                        / delta
                    )
                    .truncatingRemainder(
                        dividingBy: 6
                    )

            } else if maxValue == g {

                hue =
                    (
                        (b - r) / delta
                    )
                    + 2

            } else {

                hue =
                    (
                        (r - g) / delta
                    )
                    + 4
            }

            hue /= 6.0

            if hue < 0 {
                hue += 1
            }
        }

        let saturation =
            maxValue == 0
            ? 0
            : delta / maxValue

        return (
            h: hue,
            s: saturation,
            v: maxValue
        )
    }

    // MARK: - HSV -> RGB

    private static func hsvToRGB(
        h: Double,
        s: Double,
        v: Double
    ) -> (
        r: Double,
        g: Double,
        b: Double
    ) {

        let scaled =
            h * 6.0

        let sector =
            Int(
                floor(
                    scaled
                )
            )

        let fraction =
            scaled
            - Double(sector)

        let p =
            v * (
                1 - s
            )

        let q =
            v * (
                1
                - s * fraction
            )

        let t =
            v * (
                1
                - s * (
                    1 - fraction
                )
            )

        switch sector % 6 {

        case 0:
            return (
                r: v,
                g: t,
                b: p
            )

        case 1:
            return (
                r: q,
                g: v,
                b: p
            )

        case 2:
            return (
                r: p,
                g: v,
                b: t
            )

        case 3:
            return (
                r: p,
                g: q,
                b: v
            )

        case 4:
            return (
                r: t,
                g: p,
                b: v
            )

        default:
            return (
                r: v,
                g: p,
                b: q
            )
        }
    }

    // MARK: - Neutral fallback

    private static func makeNeutralColor(
        red: Double,
        green: Double,
        blue: Double,
        weight: Double,
        fallback: Color
    ) -> Color {

        guard
            weight > 0
        else {
            return fallback
        }

        let r =
            red / weight

        let g =
            green / weight

        let b =
            blue / weight

        let brightness =
            max(
                r,
                g,
                b
            )

        // For very dark artwork, return a restrained neutral color
        // instead of falling back to the yellow accent.
        if brightness < 0.18 {

            return Color(
                red: 0.20,
                green: 0.20,
                blue: 0.22
            )
        }

        // Neutral gray.
        //
        // We intentionally don't inject the app's yellow accent here.
        let gray =
            (
                r + g + b
            ) / 3.0

        let restrained =
            min(
                max(
                    gray,
                    0.18
                ),
                0.55
            )

        return Color(
            red: restrained,
            green: restrained,
            blue: restrained
        )
    }
}
