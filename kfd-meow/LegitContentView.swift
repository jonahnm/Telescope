//
//  ContentView.swift
//  TSUI
//
//  Created by knives on 1/20/24.
//

import SwiftUI
import KernelPatchfinder


extension Color
{
    init(hex: UInt, alpha: Double = 1) 
    {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}

extension UIColor {
    static var random: UIColor {
        return .init(hue: .random(in: 0...1), saturation: 1, brightness: 1, alpha: 1)
    }
}

struct VisualEffectView: UIViewRepresentable 
{
    var effect: UIVisualEffect?
    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView { UIVisualEffectView() }
    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) { uiView.effect = effect }
}

struct LegitContentView: View {
    @State var tapped: Bool = false
    @State var result: UInt64 = kpoen_bridge(UInt64(2), 0)
    @State var logging: String = ""
    
    struct Item {
        var clickAction: () -> Void
        var name: String
    }

    let items: [Item] = [
        Item(clickAction: {
            meow_and_kclose()
        }, name: "kclose"),
        Item(clickAction: {
            testKalloc()
        }, name: "kalloc"),
        Item(clickAction: {
            testTC()
        }, name: "tcinject"),
        Item(clickAction: {
            // Handle click action for the second item
            helloworldtest()
        }, name: "jupiter")
    ]

    
    var body: some View {
        // NavigationView
        ZStack
        {
            Image("1_milkyway")
                .resizable()
                .ignoresSafeArea()
                .scaledToFill()
                .blur(radius: 4.0, opaque: true)
            
            VStack(alignment: .leading) {
                Text("Telescope.")
                    .font(.largeTitle)
                    .bold()
                Text("created by bedtime & sora.")
                    .font(.footnote)
                    .bold()
            }
            .foregroundStyle(.white)
            .frame(minWidth: 44, minHeight: 44)
            .offset(x: 0, y: tapped ? 2048: -277)
            
            VStack
            {
                ZStack
                {
                    ZStack {
                        
                        if tapped {
                            ScrollView()
                            {
                                Text(logging)
                                    .transition(.scale(scale: 50.5))
                                    .animation(teleSpring())
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 300)
                                    .font(.caption)
                                    .monospaced()
//                                    .task {
//                                        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
//                                            DispatchQueue.main.async {
//                                                logging = String(cString: GlobalLogging)
//                                            }
//                                        }
//                                    }
                            }.frame(minWidth: 300, maxWidth: 300, maxHeight: (screenHeight() >= 670 ? 500 : 400) - 75)
                        }
                        
                        Image("telescope-50")
                            .scaleEffect(0.7)
                            .opacity(tapped ? 0.0 : 0.75)
                            .colorInvert()
                            .onTapGesture
                        {
                            withAnimation(teleSpring())
                            {
                                tapped.toggle()
                                DispatchQueue.global().async {
                                    //jb()
                                    print("TODO: Jb function");
                                }
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
                .frame(minWidth: tapped ? 300 : 120, minHeight: tapped ? (screenHeight() >= 670 ? 500 : 400) : 50)
                .background( VisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark)) )
                .cornerRadius(tapped ? 0 : 5)
                .offset(x: 0, y: tapped ? -101 : 277)
                .shadow(color: .black.opacity(0.5), radius: 20)
                if !tapped {
                    HStack
                    {
                        ForEach(items.indices, id: \.self) { index in
                            HStack
                            {
                                Spacer().frame(maxWidth: 66);
                            }
                            .blur(radius: 3)
                            .frame(minWidth: 66, minHeight: 50)
                            .background( VisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark)) )
                            .overlay(content: {
                                Color.init(uiColor: UIColor.random).opacity(0.75)
                                Text(self.items[index].name)
                                    .foregroundStyle(.white.opacity(0.75))
                            })
                            .cornerRadius(tapped ? 0 : 5)
                            .offset(x: 0, y: tapped ? -101 : 277)
                            .shadow(color: .black.opacity(0.5), radius: 20)
                            .onTapGesture
                            {
                                withAnimation(teleSpring())
                                {
                                    DispatchQueue.global().async {
                                        self.items[index].clickAction()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            if tapped {
                HStack {
                    ProgressView()
                        .controlSize(.mini)
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                }
                .frame(minWidth: 44, minHeight: 44)
                .background( VisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark)) )
                .cornerRadius(18)
                .shadow(color: .black.opacity(0.5), radius: 20)
                .transition(.scale(scale: 2))
                .offset(y: 277)
                .animation(teleSpring())
            }
        }
        
    }
    
    func teleSpring() -> Animation {
        return .spring()
    }
    
    
    func screenHeight() -> CGFloat {
        return UIScreen.main.bounds.height
    }
}
