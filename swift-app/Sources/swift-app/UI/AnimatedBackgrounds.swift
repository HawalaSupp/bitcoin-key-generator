// AnimatedBackgrounds.swift
// Hawala - Exact ReactBits Aurora Background
// https://github.com/DavidHDev/react-bits/blob/main/src/content/Backgrounds/Aurora/Aurora.jsx

import SwiftUI
import WebKit

// MARK: - Background Type Enum

enum AnimatedBackgroundType: String, CaseIterable, Identifiable {
    case none = "none"
    case aurora = "aurora"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .aurora: return "Aurora"
        }
    }
    
    var iconName: String {
        switch self {
        case .none: return "circle.slash"
        case .aurora: return "aqi.medium"
        }
    }
}

// MARK: - Background Picker View

struct BackgroundTypePicker: View {
    @Binding var selectedBackground: String
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(AnimatedBackgroundType.allCases) { bgType in
                Button(action: {
                    selectedBackground = bgType.rawValue
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: bgType.iconName)
                            .font(.system(size: 20))
                        Text(bgType.displayName)
                            .font(.caption2)
                    }
                    .frame(width: 70, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedBackground == bgType.rawValue
                                  ? Color.accentColor.opacity(0.3)
                                  : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedBackground == bgType.rawValue
                                    ? Color.accentColor
                                    : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - WebView Helper

@MainActor
func createBackgroundWebView(html: String) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
    
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.setValue(false, forKey: "drawsBackground")
    webView.loadHTMLString(html, baseURL: nil)
    return webView
}

// MARK: - Aurora Background (Exact ReactBits Code)
// Source: https://github.com/DavidHDev/react-bits/blob/main/src/content/Backgrounds/Aurora/Aurora.jsx

struct AuroraBackground: NSViewRepresentable {
    var colorStops: [String] = ["#00D4FF", "#7C3AED", "#00D4FF"]
    var amplitude: Double = 1.0
    var blend: Double = 0.5
    var speed: Double = 1.0
    
    func makeNSView(context: Context) -> WKWebView {
        createBackgroundWebView(html: Self.makeHTML(
            colorStops: colorStops,
            amplitude: amplitude,
            blend: blend,
            speed: speed
        ))
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    private static func makeHTML(colorStops: [String], amplitude: Double, blend: Double, speed: Double) -> String {
        // Convert hex colors to RGB arrays for the shader
        func hexToRGB(_ hex: String) -> (r: Double, g: Double, b: Double) {
            var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            if h.hasPrefix("#") { h.removeFirst() }
            guard h.count == 6, let int = UInt64(h, radix: 16) else {
                return (0, 0, 0)
            }
            return (
                r: Double((int >> 16) & 0xFF) / 255.0,
                g: Double((int >> 8) & 0xFF) / 255.0,
                b: Double(int & 0xFF) / 255.0
            )
        }
        
        let c0 = hexToRGB(colorStops.count > 0 ? colorStops[0] : "#00D4FF")
        let c1 = hexToRGB(colorStops.count > 1 ? colorStops[1] : "#7C3AED")
        let c2 = hexToRGB(colorStops.count > 2 ? colorStops[2] : "#00D4FF")
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        * { margin: 0; padding: 0; }
        html, body, canvas { width: 100%; height: 100%; overflow: hidden; display: block; }
        body { background: transparent; }
        </style>
        </head>
        <body>
        <canvas id="c"></canvas>
        <script>
        // Exact ReactBits Aurora shader code
        // https://github.com/DavidHDev/react-bits/blob/main/src/content/Backgrounds/Aurora/Aurora.jsx
        
        const canvas = document.getElementById('c');
        const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
        const isWebGL2 = gl instanceof WebGL2RenderingContext;
        
        // Exact VERT shader from ReactBits
        const VERT = isWebGL2 ? `#version 300 es
        in vec2 position;
        void main() {
            gl_Position = vec4(position, 0.0, 1.0);
        }
        ` : `
        attribute vec2 position;
        void main() {
            gl_Position = vec4(position, 0.0, 1.0);
        }
        `;
        
        // Exact FRAG shader from ReactBits
        const FRAG = isWebGL2 ? `#version 300 es
        precision highp float;
        
        uniform float uTime;
        uniform float uAmplitude;
        uniform vec3 uColorStops[3];
        uniform vec2 uResolution;
        uniform float uBlend;
        
        out vec4 fragColor;
        
        vec3 permute(vec3 x) {
            return mod(((x * 34.0) + 1.0) * x, 289.0);
        }
        
        float snoise(vec2 v){
            const vec4 C = vec4(
                0.211324865405187, 0.366025403784439,
                -0.577350269189626, 0.024390243902439
            );
            vec2 i  = floor(v + dot(v, C.yy));
            vec2 x0 = v - i + dot(i, C.xx);
            vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
            vec4 x12 = x0.xyxy + C.xxzz;
            x12.xy -= i1;
            i = mod(i, 289.0);
            
            vec3 p = permute(
                permute(i.y + vec3(0.0, i1.y, 1.0))
                + i.x + vec3(0.0, i1.x, 1.0)
            );
            
            vec3 m = max(
                0.5 - vec3(
                    dot(x0, x0),
                    dot(x12.xy, x12.xy),
                    dot(x12.zw, x12.zw)
                ),
                0.0
            );
            m = m * m;
            m = m * m;
            
            vec3 x = 2.0 * fract(p * C.www) - 1.0;
            vec3 h = abs(x) - 0.5;
            vec3 ox = floor(x + 0.5);
            vec3 a0 = x - ox;
            m *= 1.79284291400159 - 0.85373472095314 * (a0*a0 + h*h);
            
            vec3 g;
            g.x  = a0.x  * x0.x  + h.x  * x0.y;
            g.yz = a0.yz * x12.xz + h.yz * x12.yw;
            return 130.0 * dot(m, g);
        }
        
        struct ColorStop {
            vec3 color;
            float position;
        };
        
        #define COLOR_RAMP(colors, factor, finalColor) { \\
            int index = 0; \\
            for (int i = 0; i < 2; i++) { \\
                ColorStop currentColor = colors[i]; \\
                bool isInBetween = currentColor.position <= factor; \\
                index = int(mix(float(index), float(i), float(isInBetween))); \\
            } \\
            ColorStop currentColor = colors[index]; \\
            ColorStop nextColor = colors[index + 1]; \\
            float range = nextColor.position - currentColor.position; \\
            float lerpFactor = (factor - currentColor.position) / range; \\
            finalColor = mix(currentColor.color, nextColor.color, lerpFactor); \\
        }
        
        void main() {
            vec2 uv = gl_FragCoord.xy / uResolution;
            
            ColorStop colors[3];
            colors[0] = ColorStop(uColorStops[0], 0.0);
            colors[1] = ColorStop(uColorStops[1], 0.5);
            colors[2] = ColorStop(uColorStops[2], 1.0);
            
            vec3 rampColor;
            COLOR_RAMP(colors, uv.x, rampColor);
            
            float height = snoise(vec2(uv.x * 2.0 + uTime * 0.1, uTime * 0.25)) * 0.5 * uAmplitude;
            height = exp(height);
            height = (uv.y * 2.0 - height + 0.2);
            float intensity = 0.6 * height;
            
            float midPoint = 0.20;
            float auroraAlpha = smoothstep(midPoint - uBlend * 0.5, midPoint + uBlend * 0.5, intensity);
            
            vec3 auroraColor = intensity * rampColor;
            
            fragColor = vec4(auroraColor * auroraAlpha, auroraAlpha);
        }
        ` : `
        precision highp float;
        
        uniform float uTime;
        uniform float uAmplitude;
        uniform vec3 uColorStops[3];
        uniform vec2 uResolution;
        uniform float uBlend;
        
        vec3 permute(vec3 x) {
            return mod(((x * 34.0) + 1.0) * x, 289.0);
        }
        
        float snoise(vec2 v){
            const vec4 C = vec4(
                0.211324865405187, 0.366025403784439,
                -0.577350269189626, 0.024390243902439
            );
            vec2 i  = floor(v + dot(v, C.yy));
            vec2 x0 = v - i + dot(i, C.xx);
            vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
            vec4 x12 = x0.xyxy + C.xxzz;
            x12.xy -= i1;
            i = mod(i, 289.0);
            
            vec3 p = permute(
                permute(i.y + vec3(0.0, i1.y, 1.0))
                + i.x + vec3(0.0, i1.x, 1.0)
            );
            
            vec3 m = max(
                0.5 - vec3(
                    dot(x0, x0),
                    dot(x12.xy, x12.xy),
                    dot(x12.zw, x12.zw)
                ),
                0.0
            );
            m = m * m;
            m = m * m;
            
            vec3 x = 2.0 * fract(p * C.www) - 1.0;
            vec3 h = abs(x) - 0.5;
            vec3 ox = floor(x + 0.5);
            vec3 a0 = x - ox;
            m *= 1.79284291400159 - 0.85373472095314 * (a0*a0 + h*h);
            
            vec3 g;
            g.x  = a0.x  * x0.x  + h.x  * x0.y;
            g.yz = a0.yz * x12.xz + h.yz * x12.yw;
            return 130.0 * dot(m, g);
        }
        
        void main() {
            vec2 uv = gl_FragCoord.xy / uResolution;
            
            vec3 rampColor;
            if (uv.x < 0.5) {
                rampColor = mix(uColorStops[0], uColorStops[1], uv.x * 2.0);
            } else {
                rampColor = mix(uColorStops[1], uColorStops[2], (uv.x - 0.5) * 2.0);
            }
            
            float height = snoise(vec2(uv.x * 2.0 + uTime * 0.1, uTime * 0.25)) * 0.5 * uAmplitude;
            height = exp(height);
            height = (uv.y * 2.0 - height + 0.2);
            float intensity = 0.6 * height;
            
            float midPoint = 0.20;
            float auroraAlpha = smoothstep(midPoint - uBlend * 0.5, midPoint + uBlend * 0.5, intensity);
            
            vec3 auroraColor = intensity * rampColor;
            
            gl_FragColor = vec4(auroraColor * auroraAlpha, auroraAlpha);
        }
        `;
        
        function createShader(type, source) {
            const shader = gl.createShader(type);
            gl.shaderSource(shader, source);
            gl.compileShader(shader);
            if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
                console.error('Shader compile error:', gl.getShaderInfoLog(shader));
            }
            return shader;
        }
        
        const program = gl.createProgram();
        gl.attachShader(program, createShader(gl.VERTEX_SHADER, VERT));
        gl.attachShader(program, createShader(gl.FRAGMENT_SHADER, FRAG));
        gl.linkProgram(program);
        gl.useProgram(program);
        
        // Setup geometry (triangle that covers screen, like OGL Triangle)
        const vertices = new Float32Array([-1, -1, 3, -1, -1, 3]);
        const buffer = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
        gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
        
        const posLoc = gl.getAttribLocation(program, 'position');
        gl.enableVertexAttribArray(posLoc);
        gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0);
        
        // Uniforms
        const uTime = gl.getUniformLocation(program, 'uTime');
        const uAmplitude = gl.getUniformLocation(program, 'uAmplitude');
        const uResolution = gl.getUniformLocation(program, 'uResolution');
        const uBlend = gl.getUniformLocation(program, 'uBlend');
        const uColorStops = gl.getUniformLocation(program, 'uColorStops');
        
        // Enable blending like ReactBits does
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
        gl.clearColor(0, 0, 0, 0);
        
        function resize() {
            canvas.width = window.innerWidth * devicePixelRatio;
            canvas.height = window.innerHeight * devicePixelRatio;
            gl.viewport(0, 0, canvas.width, canvas.height);
        }
        window.addEventListener('resize', resize);
        resize();
        
        const startTime = performance.now();
        const speed = \(speed);
        const amplitude = \(amplitude);
        const blend = \(blend);
        
        // Color stops from props
        const colorStops = [
            \(c0.r), \(c0.g), \(c0.b),
            \(c1.r), \(c1.g), \(c1.b),
            \(c2.r), \(c2.g), \(c2.b)
        ];
        
        function render() {
            requestAnimationFrame(render);
            
            gl.clear(gl.COLOR_BUFFER_BIT);
            
            const t = (performance.now() - startTime) * 0.01;
            
            // Exact timing from ReactBits: time * speed * 0.1
            gl.uniform1f(uTime, t * speed * 0.1);
            gl.uniform1f(uAmplitude, amplitude);
            gl.uniform1f(uBlend, blend);
            gl.uniform2f(uResolution, canvas.width, canvas.height);
            gl.uniform3fv(uColorStops, colorStops);
            
            gl.drawArrays(gl.TRIANGLES, 0, 3);
        }
        render();
        </script>
        </body>
        </html>
        """
    }
}
