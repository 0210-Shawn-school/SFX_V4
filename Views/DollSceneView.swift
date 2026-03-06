import SwiftUI

struct DollSceneView: View {
    @ObservedObject var audio: AudioManager


    @State private var masterDrag: CGSize = .zero
    @State private var isMasterDragging = false


    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundColor.ignoresSafeArea()

                VStack {
                    skull

//                    Text("Dist: \(String(format: "%.2f", audio.distAmount))  Delay: \(String(format: "%.2f", audio.delayTime))")
//                        .font(.system(size: 12, weight: .bold, design: .rounded))
//                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .gesture(
                audio.uiLevel == .basic
                ? masterDragGesture(in: geo)
                : nil
            )
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        
    }
    
}
extension DollSceneView {

    private var skull: some View {
        ZStack {

            if audio.delayOn {

                ForEach(0..<shadowCount, id: \.self) { i in
                    
                    let spacingX = -masterDrag.width * 0.3
                    let spacingY = -masterDrag.height * 0.3
                    skullCore
                        .offset(
                            x: CGFloat(i) * spacingX,
                            y: CGFloat(i) * spacingY
                        )
                        .opacity(max(0.05, 0.8 - Double(i) * 0.06))
                        .scaleEffect(1 - Double(i) * 0.03)
                }
            }

            skullCore
        }
        .offset(
            x: shakeOffset.width,
            y: shakeOffset.height
        )
        .animation(.linear(duration: 0.05), value: audio.distAmount)
        .scaleEffect(1 + audio.delayTime * 0.3)
    }
    private var shadowCount: Int {
        guard audio.delayOn else { return 0 }

        if audio.delayTime < 0.05 {
            return 0
        }
        return Int(5 + audio.delayTime * 20)
    }

    private var shakeOffset: CGSize {
        let intensity = audio.distAmount * 8
        return CGSize(
            width: CGFloat.random(in: -intensity...intensity),
            height: CGFloat.random(in: -intensity...intensity)
        )
    }
}
extension DollSceneView {

    private var skullCore: some View {
        ZStack {

            // 頭
            Circle()
                .fill(headColor)
                .frame(width: 150, height: 150)

            // 眼睛
            HStack(spacing: 40) {
                eye
                eye
            }
            .offset(y: -15)

            // 鼻子
            Triangle()
                .fill(.black)
                .frame(width: 20, height: 18)
                .offset(y: noseOffsetY)

            // Wah 嘴巴
            if audio.wahOn {
                mouth
                    .offset(y: 30)

                tears
            }
        }
    }

    private var headColor: Color {
        guard audio.distOn else { return .yellow }

        return Color(
                hue: 0.14 - audio.distAmount * 0.14,
                saturation: 1,
                brightness: 1 - audio.distAmount * 0.2
            )
    }

    private var eye: some View {
        let amount = audio.distOn ? audio.distAmount : 0

        let size = 30 + amount * 20
        let pupilSize = 8 + amount * 12

        return Circle()
            .fill(.black)
            .overlay(
                Group {
                    if amount > 0.01 {
                        Circle()
                            .fill(.red)
                            .frame(width: pupilSize, height: pupilSize)
                    }
                }
            )
            .frame(width: size, height: size)
    }
    private var noseOffsetY: CGFloat {
        5 - CGFloat(audio.wahPedal) * 30
    }
}
extension DollSceneView {

    private var mouth: some View {
        let size = 20 + audio.wahPedal * 60

        return Circle()
            .stroke(.black, lineWidth: 6)
            .frame(width: size, height: size)
            .animation(.easeOut(duration: 0.1), value: audio.wahPedal)
    }

    private var tears: some View {
        HStack(spacing: 50) {
            tear(xOffset: -20)
            tear(xOffset: 20)
        }
        .offset(y: 5 + audio.wahPedal * 20)
    }

    private func tear(xOffset: CGFloat) -> some View {
        Text("💧")
            .font(.system(size: 24))
            .offset(
                x: xOffset,
                y: CGFloat(15 + audio.wahPedal * 30)
            )
            .opacity(0.3 + audio.wahPedal * 0.7)
    }
}
extension DollSceneView {

    private func masterDragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isMasterDragging = true
                
                audio.distAmount = 0
                audio.delayTime = 0
                audio.wahPedal = 0.5

                let center = CGPoint(
                    x: geo.size.width / 2,
                    y: geo.size.height / 2
                )
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y

                masterDrag = CGSize(width: dx, height: dy)

                let maxDistance: CGFloat = 200
                
                let distance = sqrt(dx*dx + dy*dy)
                let rawDist = min(abs(dx) / maxDistance, 1)
                let rawWah = min(abs(dy) / maxDistance, 1)
                let rawDelay = min(distance / maxDistance, 1)

                let distNorm = audio.uiLevel == .basic
                    ? min(rawDist, audio.basicDistMax)
                    : rawDist

                let wahNorm = audio.uiLevel == .basic
                    ? min(rawWah, audio.basicWahMax)
                    : rawWah

                let delayNorm = audio.uiLevel == .basic
                    ? min(rawDelay, audio.basicDelayMax)
                    : rawDelay
                
                if audio.distOn {
                    audio.distAmount = distNorm
                }

                if audio.wahOn {
                    audio.wahPedal = wahNorm
                }

                if audio.delayOn {
                    audio.delayTime = delayNorm
                }
            }
            .onEnded { _ in
                isMasterDragging = false

                withAnimation(.spring()) {
                    masterDrag = .zero
                }

                // 回到初始
                audio.distAmount = 0
                audio.delayTime = 0
                audio.wahPedal = 0.5
            }
    }

    private var backgroundColor: Color {
        .black.opacity(0.3)
    }
}
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
